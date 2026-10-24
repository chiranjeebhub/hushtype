@preconcurrency import AVFoundation
import Foundation
import Speech

/// One live dictation on Apple's on-device SpeechAnalyzer. Audio is transcribed while the key is
/// still held, so only the last fraction of a second is left to finish after release.
///
/// Create it at key-down, feed it microphone buffers with `append`, then call `finish` at key-up.
public final class AppleSpeechTranscriber: @unchecked Sendable {
    private let audio: AsyncStream<AVAudioPCMBuffer>
    private let audioInput: AsyncStream<AVAudioPCMBuffer>.Continuation
    private var work: Task<String, Error>!

    public init(options: TranscriptionOptions) {
        (audio, audioInput) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        let audio = self.audio
        // Buffers that arrive before the analyzer is ready wait in the stream, so nothing is lost.
        work = Task { try await Self.run(audio: audio, options: options) }
    }

    /// Feeds a buffer from the microphone. Safe to call from the audio thread.
    public func append(_ buffer: AVAudioPCMBuffer) {
        audioInput.yield(buffer)
    }

    /// Ends the audio and returns the full transcript.
    public func finish() async throws -> String {
        audioInput.finish()
        return try await work.value
    }

    public func cancel() {
        audioInput.finish()
        work.cancel()
    }

    private static func run(audio: AsyncStream<AVAudioPCMBuffer>, options: TranscriptionOptions) async throws -> String {
        guard let locale = await AppleSpeechModel.locale(for: options.language) else {
            throw HushtypeError.speechUnavailable("On-device dictation doesn't support this language yet.")
        }
        guard await AppleSpeechModel.status(language: options.language) == .installed else {
            throw HushtypeError.speechUnavailable("The speech model is still downloading. Try again in a moment.")
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw HushtypeError.speechUnavailable("No audio format available for on-device dictation.")
        }

        if !options.vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = options.vocabulary
            try await analyzer.setContext(context)
        }

        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        let (analyzerInput, analyzerFeed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: analyzerInput)

        var converter: AVAudioConverter?
        for await buffer in audio {
            if Task.isCancelled { break }
            if converter == nil || converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: format)
            }
            if let converted = convert(buffer, to: format, with: converter) {
                analyzerFeed.yield(AnalyzerInput(buffer: converted))
            }
        }
        analyzerFeed.finish()

        if Task.isCancelled {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw CancellationError()
        }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat,
                                with converter: AVAudioConverter?) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

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
        return error == nil ? output : nil
    }
}
