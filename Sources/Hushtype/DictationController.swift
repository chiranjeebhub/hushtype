import AppKit
import HushtypeCore

/// Runs one dictation at a time: hold key → record and transcribe live → polish → paste.
@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case cleaning
        case error(String)

        var menuBarSymbol: String {
            switch self {
            case .idle: return "waveform"
            case .recording: return "mic.fill"
            case .transcribing, .cleaning: return "ellipsis.circle"
            case .error: return "exclamationmark.triangle"
            }
        }
    }

    /// Taps shorter than this are treated as accidental and discarded.
    private static let minimumRecordingSeconds = 0.3

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var history: [DictationResult] = []
    @Published private(set) var hotkeyActive = false

    private let settings: SettingsStore
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private lazy var overlay = OverlayPanel(controller: self)
    private var pipelineTask: Task<Void, Never>?
    private var transcription: AppleSpeechTranscriber?
    private var errorDismissTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
        hotkey.onPress = { [weak self] in Task { @MainActor in self?.beginRecording() } }
        hotkey.onRelease = { [weak self] in Task { @MainActor in self?.finishRecording() } }
        hotkey.onCancel = { [weak self] in Task { @MainActor in self?.cancelRecording() } }
        recorder.onLevel = { [weak self] value in Task { @MainActor in self?.level = value } }
    }

    var statusLine: String {
        if !hotkeyActive { return "Finish setup to turn on the dictation key" }
        switch phase {
        case .idle: return "Hold \(settings.triggerKey.displayName) to dictate"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .cleaning: return "Polishing…"
        case .error(let message): return message
        }
    }

    /// Starts the hotkey listener. Safe to call again after permissions or the trigger key change.
    func start() {
        hotkey.triggerKey = settings.triggerKey
        hotkeyActive = hotkey.start()
        prepareSpeechModel()
    }

    /// Downloads the on-device speech model in the background if this language doesn't have it yet.
    func prepareSpeechModel() {
        let language = settings.transcriptionOptions.language
        Task.detached {
            if await AppleSpeechModel.status(language: language) == .notInstalled {
                try? await AppleSpeechModel.install(language: language)
            }
        }
    }

    func restartHotkey() {
        hotkey.stop()
        start()
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Pipeline

    private func beginRecording() {
        guard phase == .idle || isError else { return }
        errorDismissTask?.cancel()
        let session = AppleSpeechTranscriber(options: settings.transcriptionOptions)
        do {
            try recorder.start(onBuffer: session.append)
            transcription = session
            settings.makeCleaner()?.prewarm()
            phase = .recording
            overlay.show()
        } catch {
            session.cancel()
            show(error: error.localizedDescription)
        }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        _ = recorder.stop()
        transcription?.cancel()
        transcription = nil
        reset()
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        let releasedAt = Date()
        let seconds = recorder.stop()
        guard let session = transcription else { return reset() }
        transcription = nil
        guard seconds >= Self.minimumRecordingSeconds else {
            session.cancel()
            reset()
            return
        }

        phase = .transcribing
        let pipeline = DictationPipeline(cleaner: settings.makeCleaner(), vocabulary: settings.vocabulary)
        // The controller lives for the whole app session, so capturing it strongly is fine.
        pipelineTask = Task {
            do {
                let transcript = try await session.finish()
                let result = try await pipeline.polish(transcript, releasedAt: releasedAt) {
                    Task { @MainActor in self.phase = .cleaning }
                }
                deliver(result)
            } catch HushtypeError.noSpeech {
                reset()
            } catch {
                show(error: error.localizedDescription)
            }
        }
    }

    private func deliver(_ result: DictationResult) {
        history.insert(result, at: 0)
        if history.count > 20 { history.removeLast() }
        reset()
        TextInserter.insert(result.text)
    }

    private func reset() {
        phase = .idle
        level = 0
        overlay.hide()
    }

    private var isError: Bool {
        if case .error = phase { return true }
        return false
    }

    private func show(error message: String) {
        phase = .error(message)
        overlay.show()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }
}
