import AVFoundation

/// Captures the default microphone, converts it to 16 kHz mono, and hands each buffer to the
/// live transcriber as it arrives.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    /// Called on the audio thread with a 0...1 loudness value for the overlay meter.
    var onLevel: (Float) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var frames = 0
    private var onBuffer: (AVAudioPCMBuffer) -> Void = { _ in }
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: AudioRecorder.sampleRate,
                                             channels: 1, interleaved: false)!

    private(set) var isRecording = false

    /// - Parameter onBuffer: called on the audio thread with each converted buffer.
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isRecording else { return }
        lock.withLock { frames = 0 }
        self.onBuffer = onBuffer

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
        try engine.start()
        isRecording = true
    }

    /// Stops capture and returns the recording's length in seconds.
    func stop() -> Double {
        guard isRecording else { return 0 }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        onBuffer = { _ in }
        return Double(lock.withLock { frames }) / Self.sampleRate
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
        lock.withLock { frames += count }
        onBuffer(output)

        let chunk = UnsafeBufferPointer(start: channel, count: count)
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(max(count, 1)))
        onLevel(min(1, rms * 8))
    }

    enum RecorderError: LocalizedError {
        case noInputDevice
        var errorDescription: String? { "No microphone available." }
    }
}
