import AVFoundation
import HushtypeCore

/// Captures the default microphone and converts it to 16 kHz mono, the format every engine expects.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    /// Called on the audio thread with a 0...1 loudness value for the overlay meter.
    var onLevel: (Float) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: AudioRecorder.sampleRate,
                                             channels: 1, interleaved: false)!

    private(set) var isRecording = false

    func start() throws {
        guard !isRecording else { return }
        lock.withLock { samples.removeAll(keepingCapacity: true) }

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

    /// Stops capture and returns the recording as WAV data along with its length in seconds.
    func stop() -> (wav: Data, seconds: Double) {
        guard isRecording else { return (Data(), 0) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        let captured = lock.withLock { samples }
        let pcm = WAVEncoder.pcm16(from: captured)
        return (WAVEncoder.encode(samples: pcm, sampleRate: Int(Self.sampleRate)), Double(captured.count) / Self.sampleRate)
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
        guard error == nil, let channel = output.floatChannelData?[0] else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        lock.withLock { samples.append(contentsOf: chunk) }

        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(max(chunk.count, 1)))
        onLevel(min(1, rms * 8))
    }

    enum RecorderError: LocalizedError {
        case noInputDevice
        var errorDescription: String? { "No microphone available." }
    }
}
