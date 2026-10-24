import AVFoundation

/// Captures the default microphone, converts it to 16 kHz mono, and hands each buffer to the
/// live transcriber as it arrives.
///
/// The engine can stay running between dictations ("warm"), so a key press only flips a flag
/// instead of waking the audio hardware. While warm, the last ~300 ms is kept in memory and
/// replayed at the start of each recording, so a word started just before the press isn't
/// clipped. Idle audio is never stored beyond that window and never leaves this object.
///
/// Engine control (`prepare`, `warmUp`, `start`, `stop`, `coolDown`) happens on the main thread;
/// buffers arrive on the audio thread and shared state is guarded by `lock`.
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    /// How much idle audio to keep for the start of the next recording.
    static let preRollSeconds: Double = 0.3

    /// Called on the audio thread with a 0...1 loudness value for the overlay meter.
    var onLevel: (Float) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var frames = 0
    private var capturing = false
    private var onBuffer: (AVAudioPCMBuffer) -> Void = { _ in }
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollFrames = 0
    private var converter: AVAudioConverter?
    private var configObserver: NSObjectProtocol?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: AudioRecorder.sampleRate,
                                             channels: 1, interleaved: false)!

    /// True while the engine is running, whether or not a recording is in progress.
    private(set) var isWarm = false
    private(set) var isRecording = false

    init() {
        // A new input device (AirPods connecting, a USB mic) stops the engine; bring it back.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restartAfterDeviceChange()
        }
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

    /// Opens the mic and keeps it running between recordings.
    func warmUp() throws {
        guard !isWarm else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isWarm = true
    }

    /// Closes the mic and drops any buffered idle audio.
    func coolDown() {
        guard isWarm, !isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isWarm = false
        lock.withLock {
            preRoll.removeAll()
            preRollFrames = 0
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
    }

    /// Ends the recording and returns its length in seconds. The mic stays warm until
    /// `coolDown()`.
    func stop() -> Double {
        guard isRecording else { return 0 }
        isRecording = false
        let count = lock.withLock {
            capturing = false
            onBuffer = { _ in }
            return frames
        }
        return Double(count) / Self.sampleRate
    }

    private func restartAfterDeviceChange() {
        guard isWarm else { return }
        let wasRecording = isRecording
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isWarm = false
        do {
            try warmUp()
        } catch {
            // No usable input right now. The next press tries again.
            if wasRecording { _ = stop() }
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
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
