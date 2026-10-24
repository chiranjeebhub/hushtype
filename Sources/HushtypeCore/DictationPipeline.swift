import Foundation

public struct DictationResult: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let raw: String
    public let cleaned: String
    public let date: Date
    public let duration: TimeInterval

    public var text: String { cleaned }
}

/// Audio in, polished text out. The app supplies the engines; the pipeline owns the order.
public struct DictationPipeline: Sendable {
    let transcriber: Transcriber
    let cleaner: TranscriptCleaner?
    let options: TranscriptionOptions

    public init(transcriber: Transcriber, cleaner: TranscriptCleaner?, options: TranscriptionOptions) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.options = options
    }

    /// - Parameter onCleanupStart: called when transcription finishes and cleanup begins.
    public func run(wav: Data, onCleanupStart: @Sendable () -> Void = {}) async throws -> DictationResult {
        let start = Date()
        let raw = try await transcriber.transcribe(wav: wav, options: options)
        guard !raw.isEmpty else { throw HushtypeError.noSpeech }

        var cleaned = raw
        if let cleaner {
            onCleanupStart()
            // A failed cleanup should never lose the dictation; fall back to the raw transcript.
            cleaned = (try? await cleaner.clean(raw, vocabulary: options.vocabulary)) ?? raw
        }
        return DictationResult(raw: raw, cleaned: cleaned, date: Date(), duration: Date().timeIntervalSince(start))
    }

    /// Splits the dictionary text (one entry per line or comma-separated) into terms.
    public static func vocabulary(from text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
