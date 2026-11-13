import AppKit
import Carbon.HIToolbox
import HushtypeCore
import os

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
    /// A double-tap is keeping the mic open without the key held.
    @Published private(set) var isHandsFree = false

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
    /// The mic is always closed while the Mac is asleep or the screen is locked. The two are
    /// tracked apart, since the Mac wakes (and would reopen the mic) before the screen unlocks.
    private var asleep = false
    private var screenLocked = false
    private var micSuspended: Bool { asleep || screenLocked }
    private var systemObservers: [NSObjectProtocol] = []
    /// ⌃⌘V pastes the last dictation again, for when a paste missed.
    private var pasteLastShortcut: GlobalShortcut?

    init(settings: SettingsStore) {
        self.settings = settings
        hotkey.onPress = { [weak self] in Task { @MainActor in self?.beginRecording() } }
        hotkey.onRelease = { [weak self] in Task { @MainActor in self?.finishRecording() } }
        hotkey.onCancel = { [weak self] in Task { @MainActor in self?.cancelRecording() } }
        hotkey.onCommand = { [weak self] in Task { @MainActor in self?.switchToCommand() } }
        hotkey.onLock = { [weak self] in Task { @MainActor in self?.lockHandsFree() } }
        recorder.onLevel = { [weak self] value in Task { @MainActor in self?.level = value } }
        recorder.onNoAudio = { [weak self] in
            MainActor.assumeIsolated { self?.micStoppedResponding() }
        }
        observeSleepAndLock()
        if settings.keepHistory { history = HistoryStore.load() }
        pasteLastShortcut = GlobalShortcut(keyCode: kVK_ANSI_V, modifiers: controlKey | cmdKey) { [weak self] in
            Task { @MainActor in self?.pasteLast() }
        }
    }

    var statusLine: String {
        if !hotkeyActive { return "Finish setup to turn on the dictation key" }
        switch phase {
        case .idle: return "Hold \(settings.triggerKey.displayName) to dictate"
        case .recording:
            if isHandsFree { return "Listening hands-free. Tap \(settings.triggerKey.displayName) to finish." }
            return isCommand ? "Listening for a command…" : "Listening…"
        case .transcribing: return "Transcribing…"
        case .cleaning: return "Polishing…"
        case .error(let message), .notice(let message): return message
        }
    }

    /// Starts the hotkey listener. Safe to call again after permissions or the trigger key change.
    func start() {
        hotkey.triggerKey = settings.triggerKey
        hotkey.handsFreeEnabled = settings.handsFree
        // The event tap runs on the Accessibility grant. Creating it before that would make macOS ask for
        // Input Monitoring instead, which it refuses without a prompt.
        hotkeyActive = AXIsProcessTrusted() && hotkey.start()
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
        func on(_ change: @escaping @Sendable @MainActor (DictationController) -> Void) -> @Sendable (Notification) -> Void {
            { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let wasSuspended = self.micSuspended
                    change(self)
                    if self.micSuspended != wasSuspended { self.suspendMic(self.micSuspended) }
                }
            }
        }
        systemObservers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main,
                                  using: on { $0.asleep = true }),
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
                                  using: on { $0.asleep = false }),
            distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main,
                                    using: on { $0.screenLocked = true }),
            distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main,
                                    using: on { $0.screenLocked = false }),
        ]
    }

    private func suspendMic(_ suspended: Bool) {
        if suspended {
            coolDownTask?.cancel()
            if phase == .recording { cancelRecording() }
            recorder.coolDown()
        } else {
            // The old engine can still point at a mic that changed while the Mac slept.
            if phase != .recording { recorder.rebuild() }
            applyMicMode()
        }
    }

    /// The mic gave no audio even after the recorder reopened it.
    private func micStoppedResponding() {
        guard phase == .recording else { return }
        cancelRecording()
        show(error: "Hushtype can't hear your microphone. Check the input in System Settings › Sound.")
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
        // Restarting forgets the held key, so its release would never end a recording.
        if phase == .recording { cancelRecording() }
        hotkey.stop()
        start()
    }

    /// Call when the hands-free setting changes. Takes effect without restarting the listener.
    func applyHandsFreeSetting() {
        hotkey.handsFreeEnabled = settings.handsFree
    }

    /// Types the most recent dictation again at the cursor.
    func pasteLast(delay: Double = 0) {
        guard let last = history.first else { return NSSound.beep() }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { TextInserter.insert(last.text) }
    }

    func clearHistory() {
        history.removeAll()
        HistoryStore.erase()
    }

    /// Call when the "keep history" setting changes.
    func applyHistorySetting() {
        if settings.keepHistory { HistoryStore.save(history) } else { HistoryStore.erase() }
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
            hotkey.reset()
            show(error: error.localizedDescription)
        }
    }

    private func lockHandsFree() {
        guard phase == .recording else { return }
        isHandsFree = true
    }

    private func cancelRecording() {
        hotkey.reset()
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
                    // Only while still waiting: a fast reply can land before this hop runs, and
                    // must not leave the menu bar stuck on "Polishing…".
                    Task { @MainActor in if self.phase == .transcribing { self.phase = .cleaning } }
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
            return show(error: "Add your Anthropic key in Settings to use commands, or switch polishing to on-device.")
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
        if history.count > HistoryStore.limit { history.removeLast(history.count - HistoryStore.limit) }
        if settings.keepHistory { HistoryStore.save(history) }
        reset()
        TextInserter.insert(result.text)
        if let reason = result.fallbackReason { show(notice: reason) }
        if let field = target?.field, let location = target?.context.selectionLocation {
            watchForCorrections(PendingCorrection(field: field, location: location, inserted: result.text))
        } else if settings.learnFromCorrections {
            learningLog.info("No text field to watch for corrections in \(target?.context.appName ?? "this app", privacy: .public)")
        }
    }

    // MARK: - Learning from corrections

    struct PendingCorrection: Sendable {
        let id = UUID()
        let field: FocusedField
        let location: Int
        let inserted: String
    }

    /// How long after a paste Hushtype keeps an eye on the field.
    private static let correctionWatchSeconds = 90.0
    private let learningLog = Logger(subsystem: "app.hushtype.Hushtype", category: "learning")
    private let returnKeyTap = ReturnKeyTap()
    private var pendingCorrection: PendingCorrection?
    private var correctionTask: Task<Void, Never>?
    /// Fixes in the latest settled read of the field, learned when the watch ends.
    private var correctionCandidate: [CorrectionLearner.Correction] = []
    /// The previous poll, so a read only counts once the field has held still for a second.
    private var lastCorrectionRead: String?
    private var failedCorrectionReads = 0

    /// Follows the field after pasting, so a word the user respells joins the dictionary. It reads
    /// the field every second, and right as Return goes down: chat apps send and clear the text on
    /// Return, often a moment after the fix. The fixes are learned once the text is gone, when the
    /// next dictation starts, or after a minute and a half.
    private func watchForCorrections(_ pending: PendingCorrection) {
        stopWatchingForCorrections()
        guard settings.learnFromCorrections else { return }
        pendingCorrection = pending
        correctionCandidate = []
        lastCorrectionRead = nil
        failedCorrectionReads = 0
        learningLog.info("Watching \(pending.inserted.count) characters at \(pending.location) for corrections")

        returnKeyTap.start(read: { Self.readCorrectionWindow(pending) }) { [weak self] window in
            Task { @MainActor in self?.considerCorrectionRead(window, of: pending, settled: true, source: "Return") }
        }
        correctionTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(Self.correctionWatchSeconds)
            while Date() < deadline {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let window = await Task.detached(priority: .utility) { Self.readCorrectionWindow(pending) }.value
                guard !Task.isCancelled, let self else { return }
                if !self.considerCorrectionRead(window, of: pending, settled: false, source: "poll") {
                    // The text is gone. A Return read may still be on its way to the main actor.
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    break
                }
            }
            self?.finishWatchingForCorrections(readAgain: false)
        }
    }

    /// Reads the stretch of the field around the dictation. Runs off the main thread.
    nonisolated private static func readCorrectionWindow(_ pending: PendingCorrection) -> String? {
        let length = (pending.inserted as NSString).length
        let start = max(0, pending.location - 60)
        var range = NSRange(location: start, length: pending.location - start + length + 120)
        if let count = pending.field.characterCount {
            // Asking past the end fails in most apps.
            range.length = max(0, min(range.length, count - start))
        }
        return pending.field.text(in: range)
    }

    /// Takes in one read of the field. Returns false once the dictation is no longer there.
    @discardableResult
    private func considerCorrectionRead(_ window: String?, of pending: PendingCorrection,
                                        settled: Bool, source: String) -> Bool {
        guard pendingCorrection?.id == pending.id else { return false }
        guard let window else {
            failedCorrectionReads += 1
            learningLog.info("Couldn't read the field (\(source, privacy: .public))")
            // The field went away, like a chat box replaced after sending.
            return failedCorrectionReads < 3
        }
        failedCorrectionReads = 0
        let analysis = CorrectionLearner.analyze(inserted: pending.inserted, edited: window)
        guard analysis.isPresent else {
            learningLog.info("Dictation no longer in the field (\(source, privacy: .public))")
            return false
        }
        // A poll mid-word could catch half a fix, so it only counts once the field held still.
        let counts = settled || window == lastCorrectionRead
        if counts { correctionCandidate = analysis.corrections }
        lastCorrectionRead = window
        if !analysis.corrections.isEmpty {
            learningLog.info("Read \(analysis.corrections.count) fix(es) (\(source, privacy: .public), counted: \(counts))")
        }
        return true
    }

    private func stopWatchingForCorrections() {
        correctionTask?.cancel()
        correctionTask = nil
        returnKeyTap.stop()
        pendingCorrection = nil
    }

    /// Learns what the watch found and stops watching. Called when the next dictation starts
    /// (after one last look, off the main thread) and when the watch runs out or the text is gone.
    private func finishWatchingForCorrections(readAgain: Bool = true) {
        guard let pending = pendingCorrection else { return stopWatchingForCorrections() }
        correctionTask?.cancel()
        correctionTask = nil
        returnKeyTap.stop()
        guard readAgain else { return concludeWatch(pending) }
        Task { [weak self] in
            let window = await Task.detached(priority: .utility) { Self.readCorrectionWindow(pending) }.value
            self?.considerCorrectionRead(window, of: pending, settled: true, source: "final")
            self?.concludeWatch(pending)
        }
    }

    private func concludeWatch(_ pending: PendingCorrection) {
        guard pendingCorrection?.id == pending.id else { return }
        let corrections = correctionCandidate
        pendingCorrection = nil
        correctionCandidate = []
        lastCorrectionRead = nil
        learn(from: corrections)
    }

    private func learn(from corrections: [CorrectionLearner.Correction]) {
        let known = Set(settings.vocabulary.map { $0.lowercased() })
        let learned = corrections.filter { Self.worthLearning($0, known: known) }.map(\.to)
        learningLog.info("Watch ended: \(corrections.count) fix(es), \(learned.count) worth learning")
        guard !learned.isEmpty else { return }
        learningLog.info("Learned \(learned.joined(separator: ", "), privacy: .private)")
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
        isHandsFree = false
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
        // A message still waiting to be dismissed would otherwise clear this one, or a recording
        // started after it.
        errorDismissTask?.cancel()
        phase = .notice(message)
        overlay.show()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self, self.isNotice else { return }
            self.reset()
        }
    }

    private func show(error message: String) {
        errorDismissTask?.cancel()
        phase = .error(message)
        overlay.show()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.isError else { return }
            self.reset()
        }
    }
}
