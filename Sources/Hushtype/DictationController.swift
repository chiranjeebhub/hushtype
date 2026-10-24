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
        /// A short, non-blocking message after a dictation, like "Claude was slow".
        case notice(String)

        var menuBarSymbol: String {
            switch self {
            case .idle: return "waveform"
            case .recording: return "mic.fill"
            case .transcribing, .cleaning: return "ellipsis.circle"
            case .error: return "exclamationmark.triangle"
            case .notice: return "waveform"
            }
        }
    }

    /// Taps shorter than this are treated as accidental and discarded.
    private static let minimumRecordingSeconds = 0.3
    /// How long the mic stays open after a dictation, so back-to-back ones start instantly.
    private static let warmAfterUse: Duration = .seconds(30)

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var history: [DictationResult] = []
    @Published private(set) var hotkeyActive = false
    /// The current recording is a spoken command for the selected text, not dictation.
    @Published private(set) var isCommand = false

    private let settings: SettingsStore
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private lazy var overlay = OverlayPanel(controller: self)
    private var pipelineTask: Task<Void, Never>?
    private var transcription: AppleSpeechTranscriber?
    /// The app and text around the cursor, read in the background when the key goes down.
    private var focusCapture: Task<(context: DictationContext, field: FocusedField?), Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var coolDownTask: Task<Void, Never>?
    /// True while the Mac is asleep or the screen is locked; the mic is always closed then.
    private var micSuspended = false
    private var systemObservers: [NSObjectProtocol] = []

    init(settings: SettingsStore) {
        self.settings = settings
        hotkey.onPress = { [weak self] in Task { @MainActor in self?.beginRecording() } }
        hotkey.onRelease = { [weak self] in Task { @MainActor in self?.finishRecording() } }
        hotkey.onCancel = { [weak self] in Task { @MainActor in self?.cancelRecording() } }
        hotkey.onCommand = { [weak self] in Task { @MainActor in self?.switchToCommand() } }
        recorder.onLevel = { [weak self] value in Task { @MainActor in self?.level = value } }
        observeSleepAndLock()
    }

    var statusLine: String {
        if !hotkeyActive { return "Finish setup to turn on the dictation key" }
        switch phase {
        case .idle: return "Hold \(settings.triggerKey.displayName) to dictate"
        case .recording: return isCommand ? "Listening for a command…" : "Listening…"
        case .transcribing: return "Transcribing…"
        case .cleaning: return "Polishing…"
        case .error(let message), .notice(let message): return message
        }
    }

    /// Starts the hotkey listener. Safe to call again after permissions or the trigger key change.
    func start() {
        hotkey.triggerKey = settings.triggerKey
        hotkeyActive = hotkey.start()
        prepareSpeechModel()
        applyMicMode()
    }

    /// Opens or readies the mic to match the "Always-ready microphone" setting. Call again
    /// whenever that setting or the microphone permission changes.
    func applyMicMode() {
        guard Permission.microphone.isGranted, !micSuspended, phase != .recording else { return }
        if settings.alwaysReadyMic {
            coolDownTask?.cancel()
            try? recorder.warmUp()
        } else if recorder.isWarm {
            scheduleCoolDown()
        } else {
            recorder.prepare()
        }
    }

    private func scheduleCoolDown() {
        coolDownTask?.cancel()
        guard !settings.alwaysReadyMic else { return }
        coolDownTask = Task { [weak self] in
            try? await Task.sleep(for: Self.warmAfterUse)
            guard !Task.isCancelled, let self, self.phase != .recording else { return }
            self.recorder.coolDown()
            self.recorder.prepare()
        }
    }

    private func observeSleepAndLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let suspend: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.suspendMic(true) }
        }
        let resume: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.suspendMic(false) }
        }
        systemObservers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: suspend),
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: resume),
            distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: suspend),
            distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: resume),
        ]
    }

    private func suspendMic(_ suspended: Bool) {
        micSuspended = suspended
        if suspended {
            coolDownTask?.cancel()
            if phase == .recording { cancelRecording() }
            recorder.coolDown()
        } else {
            applyMicMode()
        }
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
        guard phase == .idle || isError || isNotice else { return }
        errorDismissTask?.cancel()
        coolDownTask?.cancel()
        finishWatchingForCorrections()
        let capture = captureFocus()
        let session = AppleSpeechTranscriber(options: settings.transcriptionOptions) {
            await capture?.value.context.nearbyTerms ?? []
        }
        do {
            try recorder.start(onBuffer: session.append)
            transcription = session
            focusCapture = capture
            settings.makeCleaner()?.prewarm()
            phase = .recording
            overlay.show()
            if settings.soundsEnabled { Chime.playStart() }
        } catch {
            session.cancel()
            show(error: error.localizedDescription)
        }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        _ = recorder.stop()
        scheduleCoolDown()
        transcription?.cancel()
        transcription = nil
        focusCapture = nil
        reset()
    }

    /// Starts reading the frontmost app, its selection, and (when context is on) the text around
    /// its cursor.
    private func captureFocus() -> Task<(context: DictationContext, field: FocusedField?), Never>? {
        let app = FocusReader.frontmostApp()
        // Hushtype's own windows aren't a dictation target worth describing.
        guard app.bundleID != Bundle.main.bundleIdentifier else { return nil }
        let includeText = settings.useContext
        return Task.detached(priority: .userInitiated) {
            FocusReader.capture(appName: app.name, bundleID: app.bundleID, pid: app.pid, includeText: includeText)
        }
    }

    private func switchToCommand() {
        guard phase == .recording, !isCommand else { return }
        isCommand = true
        if settings.soundsEnabled { Chime.playStart() }
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        let releasedAt = Date()
        let seconds = recorder.stop()
        scheduleCoolDown()
        if settings.soundsEnabled { Chime.playStop() }
        guard let session = transcription else { return reset() }
        transcription = nil
        let capture = focusCapture
        focusCapture = nil
        guard seconds >= Self.minimumRecordingSeconds else {
            session.cancel()
            reset()
            return
        }

        phase = .transcribing
        if isCommand { return runCommand(session, capture: capture, releasedAt: releasedAt) }
        let cleaner = settings.makeCleaner()
        let vocabulary = settings.vocabulary
        let useContext = settings.useContext
        let snippets = settings.snippets
        // The controller lives for the whole app session, so capturing it strongly is fine.
        pipelineTask = Task {
            do {
                let transcript = try await session.finish()
                let transcribedAt = Date()
                let captured = await capture?.value
                let context = useContext ? captured?.context : nil
                let pipeline = DictationPipeline(cleaner: cleaner, vocabulary: vocabulary, context: context,
                                                 snippets: snippets)
                let result = try await pipeline.polish(transcript, releasedAt: releasedAt,
                                                       transcribedAt: transcribedAt) {
                    Task { @MainActor in self.phase = .cleaning }
                }
                deliver(result, into: captured)
            } catch HushtypeError.noSpeech {
                reset()
            } catch {
                show(error: error.localizedDescription)
            }
        }
    }

    /// Command mode: the speech is an instruction for the selected text, or for new text at the
    /// cursor when nothing is selected. The result replaces the selection.
    private func runCommand(_ session: AppleSpeechTranscriber,
                            capture: Task<(context: DictationContext, field: FocusedField?), Never>?,
                            releasedAt: Date) {
        guard let assistant = settings.makeAssistant() else {
            session.cancel()
            return show(error: "Add your Anthropic key in Settings to use commands.")
        }
        let vocabulary = settings.vocabulary
        pipelineTask = Task {
            do {
                let instruction = try await session.finish()
                let transcribedAt = Date()
                let captured = await capture?.value
                var context = captured?.context ?? DictationContext()
                if !context.hasSelection, let copied = await TextInserter.copySelection() {
                    // Apps that don't expose their selection to Accessibility still copy it.
                    context.selectedText = copied
                }
                phase = .cleaning
                let pipeline = DictationPipeline(cleaner: assistant, vocabulary: vocabulary, context: context)
                var result = try await pipeline.command(instruction, selection: context.selectedText,
                                                        releasedAt: releasedAt, transcribedAt: transcribedAt)
                if !context.hasSelection {
                    result = DictationResult(id: result.id, raw: result.raw, cleaned: context.fit(result.cleaned),
                                             date: result.date, timings: result.timings, kind: .command,
                                             appName: result.appName)
                }
                deliver(result, into: captured)
            } catch HushtypeError.noSpeech {
                reset()
            } catch {
                show(error: error.localizedDescription)
            }
        }
    }

    private func deliver(_ result: DictationResult, into target: (context: DictationContext, field: FocusedField?)?) {
        history.insert(result, at: 0)
        if history.count > 50 { history.removeLast() }
        reset()
        TextInserter.insert(result.text)
        if let reason = result.fallbackReason { show(notice: reason) }
        if let field = target?.field, let location = target?.context.selectionLocation {
            watchForCorrections(PendingCorrection(field: field, location: location, inserted: result.text))
        }
    }

    // MARK: - Learning from corrections

    struct PendingCorrection: Sendable {
        let field: FocusedField
        let location: Int
        let inserted: String
    }

    private var pendingCorrection: PendingCorrection?
    private var correctionTask: Task<Void, Never>?

    /// Re-reads the field a few times after pasting. If the user respelled a word Hushtype typed,
    /// the new spelling joins the dictionary.
    private func watchForCorrections(_ pending: PendingCorrection) {
        correctionTask?.cancel()
        guard settings.learnFromCorrections else { return }
        pendingCorrection = pending
        correctionTask = Task { [weak self] in
            for delay in [8, 20, 45] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.checkForCorrections(pending)
            }
        }
    }

    /// Checks once more, then stops watching. Called when the next dictation starts.
    private func finishWatchingForCorrections() {
        correctionTask?.cancel()
        correctionTask = nil
        guard let pending = pendingCorrection else { return }
        pendingCorrection = nil
        Task { await checkForCorrections(pending) }
    }

    private func checkForCorrections(_ pending: PendingCorrection) async {
        let corrections = await Task.detached(priority: .utility) { () -> [CorrectionLearner.Correction] in
            let length = (pending.inserted as NSString).length
            let start = max(0, pending.location - 60)
            guard let window = pending.field.text(in: NSRange(location: start, length: pending.location - start + length + 120))
            else { return [] }
            return CorrectionLearner.corrections(inserted: pending.inserted, edited: window)
        }.value
        let known = Set(settings.vocabulary.map { $0.lowercased() })
        let learned = corrections.filter { Self.worthLearning($0, known: known) }.map(\.to)
        guard !learned.isEmpty else { return }
        settings.addToDictionary(learned)
        if phase == .idle || isNotice {
            let names = learned.map { "“\($0)”" }.joined(separator: ", ")
            show(notice: "Learned \(names). It's in your dictionary now.")
        }
    }

    /// Respellings to remember: names and jargon, not everyday word swaps.
    static func worthLearning(_ correction: CorrectionLearner.Correction, known: Set<String>) -> Bool {
        let word = correction.to
        guard word.count >= 2, !known.contains(word.lowercased()) else { return false }
        if correction.caseOnly {
            // "jen" → "Jen" names someone; "the" → "The" at a sentence start doesn't.
            return !correction.atSentenceStart && word.first?.isUppercase == true
        }
        let mixedCase = word.dropFirst().contains(where: \.isUppercase) && word.contains(where: \.isLowercase)
        if mixedCase || word.contains(where: \.isNumber) { return true }
        // Ordinary dictionary words ("their" → "there") are grammar fixes, not vocabulary.
        let misspelled = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        return misspelled.location != NSNotFound || (word.first?.isUppercase == true && !correction.atSentenceStart)
    }

    /// Release-to-paste percentiles over recent dictations.
    var latency: LatencyStats? {
        LatencyStats(history.filter { $0.kind == .dictation }.map(\.duration))
    }

    private func reset() {
        phase = .idle
        isCommand = false
        level = 0
        overlay.hide()
    }

    private var isError: Bool {
        if case .error = phase { return true }
        return false
    }

    private var isNotice: Bool {
        if case .notice = phase { return true }
        return false
    }

    private func show(notice message: String) {
        phase = .notice(message)
        overlay.show()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self, self.isNotice else { return }
            self.reset()
        }
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
