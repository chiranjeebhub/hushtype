import AVFoundation
import os

/// Captures the default microphone, converts it to 16 kHz mono, and hands each buffer to the
/// live transcriber as it arrives.
///
/// The engine can stay running between dictations ("warm"), so a key press only flips a flag
/// instead of waking the audio hardware. While warm, the last ~300 ms is kept in memory and
/// replayed at the start of each recording, so a word started just before the press isn't
/// clipped. Idle audio is never stored beyond that window and never leaves this object.
///
/// macOS can stop the input stream without telling us (a mic switch, sleep, another app taking
/// the device), and an engine can stay tied to a mic that has gone away. So the recorder checks
/// that buffers are really arriving, and when they aren't it throws the engine away and opens
/// the current default mic on a new one.
///
/// Engine control (`prepare`, `warmUp`, `start`, `stop`, `coolDown`, `rebuild`) happens on the
/// main thread; buffers arrive on the audio thread and shared state is guarded by `lock`.
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    /// How much idle audio to keep for the start of the next recording.
    static let preRollSeconds: Double = 0.3
    /// A running tap delivers a buffer every ~20 ms; this long without one means the stream died.
    static let stallSeconds: Double = 0.5
    /// How many times a silent recording rebuilds the engine before giving up.
    static let maxRecoveries = 2

    /// Called on the audio thread with a 0...1 loudness value for the overlay meter.
    var onLevel: (Float) -> Void = { _ in }
    /// Called on the main thread when a recording gets no audio even after rebuilding the engine.
    var onNoAudio: () -> Void = {}

    private var engine = AVAudioEngine()
    private let lock = NSLock()
    private var frames = 0
    private var capturing = false
    private var onBuffer: (AVAudioPCMBuffer) -> Void = { _ in }
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollFrames = 0
    private var converter: AVAudioConverter?
    /// Uptime of the last buffer from the mic, or of opening it if none has come yet.
    private var lastBufferAt: TimeInterval = 0
    private var configObserver: NSObjectProtocol?
    private var deviceChangePending = false
    private var lastRebuildAt: TimeInterval = 0
    private var watchdog: DispatchWorkItem?
    private let log = Logger(subsystem: "app.hushtype.Hushtype", category: "audio")
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: AudioRecorder.sampleRate,
                                             channels: 1, interleaved: false)!

    /// True while the engine is running, whether or not a recording is in progress.
    private(set) var isWarm = false
    private(set) var isRecording = false

    init() {
        observeConfigurationChanges()
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Readies the audio graph without opening the mic, so a cold start is faster.
    func prepare() {
        guard !isWarm else { return }
        _ = engine.inputNode
        engine.prepare()
    }

    /// Opens the mic and keeps it running between recordings. If it was already open but has
    /// stopped delivering audio, it is reopened on a new engine.
    func warmUp() throws {
        if isWarm {
            guard isStalled else { return }
            log.notice("Mic stream stalled (engine running: \(self.engine.isRunning)); rebuilding")
            rebuild()
            if isWarm { return }
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            log.error("No usable input device")
            throw RecorderError.noInputDevice
        }
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        lock.withLock {
            self.converter = converter
            lastBufferAt = ProcessInfo.processInfo.systemUptime
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            log.error("Couldn't start the mic: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        isWarm = true
        log.info("Mic open: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch")
    }

    /// Closes the mic and drops any buffered idle audio.
    func coolDown() {
        guard isWarm, !isRecording else { return }
        closeMic()
    }

    /// Replaces the audio engine with a new one bound to the current default mic. Use after the
    /// Mac wakes, when the old engine may still point at hardware that's gone. A recording in
    /// progress carries on with the new engine.
    func rebuild() {
        if isWarm { closeMic() }
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine = AVAudioEngine()
        lastRebuildAt = ProcessInfo.processInfo.systemUptime
        observeConfigurationChanges()
        if isRecording {
            do { try warmUp() } catch { log.error("Mic didn't reopen after rebuild") }
        }
    }

    /// Starts a recording, opening the mic first if it isn't warm.
    /// - Parameter onBuffer: called on the audio thread with each converted buffer.
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isRecording else { return }
        try warmUp()
        lock.withLock {
            // Hand over the look-back first so the transcriber hears it before live audio. It
            // doesn't count toward the length, so short accidental taps are still discarded.
            frames = 0
            preRoll.forEach(onBuffer)
            preRoll.removeAll()
            preRollFrames = 0
            self.onBuffer = onBuffer
            capturing = true
        }
        isRecording = true
        scheduleWatchdog(recoveriesLeft: Self.maxRecoveries)
    }

    /// Ends the recording and returns its length in seconds. The mic stays warm until
    /// `coolDown()`.
    func stop() -> Double {
        guard isRecording else { return 0 }
        isRecording = false
        watchdog?.cancel()
        watchdog = nil
        let count = lock.withLock {
            capturing = false
            onBuffer = { _ in }
            return frames
        }
        return Double(count) / Self.sampleRate
    }

    private var isStalled: Bool {
        let last = lock.withLock { lastBufferAt }
        return !engine.isRunning || ProcessInfo.processInfo.systemUptime - last > Self.stallSeconds
    }

    private func closeMic() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isWarm = false
        lock.withLock {
            preRoll.removeAll()
            preRollFrames = 0
        }
    }

    /// Checks shortly after a recording starts that audio is arriving, and rebuilds the engine
    /// if it isn't.
    private func scheduleWatchdog(recoveriesLeft: Int) {
        watchdog?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording, self.isStalled else { return }
            guard recoveriesLeft > 0 else {
                self.log.error("Still no audio after rebuilding the engine")
                self.onNoAudio()
                return
            }
            self.log.notice("No audio since the recording started; rebuilding the engine")
            self.rebuild()
            self.scheduleWatchdog(recoveriesLeft: recoveriesLeft - 1)
        }
        watchdog = check
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stallSeconds, execute: check)
    }

    private func observeConfigurationChanges() {
        // A new input device (AirPods connecting, a USB mic) stops the engine. Bring it back on a
        // new engine, since the old one can stay bound to the previous device.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleDeviceChange()
        }
    }

    private func handleDeviceChange() {
        // Changes often come in a burst; handle them once.
        guard !deviceChangePending else { return }
        deviceChangePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deviceChangePending = false
            // Opening a new engine can itself report a change; don't answer that with another rebuild.
            guard ProcessInfo.processInfo.systemUptime - self.lastRebuildAt > 1 || self.isStalled else { return }
            self.log.notice("Audio configuration changed (warm: \(self.isWarm), recording: \(self.isRecording))")
            let wasWarm = self.isWarm
            self.rebuild()
            guard wasWarm, !self.isWarm else { return }
            do {
                try self.warmUp()
            } catch {
                // No usable input right now. The next press tries again.
                if self.isRecording { _ = self.stop() }
            }
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let converter = lock.withLock {
            lastBufferAt = ProcessInfo.processInfo.systemUptime
            return self.converter
        }
        guard let converter, converter.inputFormat == buffer.format else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }

        let count = Int(output.frameLength)
        let isCapturing = lock.withLock {
            if capturing {
                frames += count
                onBuffer(output)
            } else {
                preRoll.append(output)
                preRollFrames += count
                let limit = Int(Self.preRollSeconds * Self.sampleRate)
                while preRollFrames - Int(preRoll[0].frameLength) >= limit {
                    preRollFrames -= Int(preRoll.removeFirst().frameLength)
                }
            }
            return capturing
        }
        guard isCapturing else { return }

        let chunk = UnsafeBufferPointer(start: channel, count: count)
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(max(count, 1)))
        onLevel(min(1, rms * 8))
    }

    enum RecorderError: LocalizedError {
        case noInputDevice
        var errorDescription: String? { "No microphone available." }
    }
}
