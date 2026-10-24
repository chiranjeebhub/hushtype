import Foundation

public struct DictationResult: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let raw: String
    public let cleaned: String
    public let date: Date
    /// Seconds from key release to text ready.
    public let duration: TimeInterval

    public var text: String { cleaned }
}

/// Transcript in, polished text out. Transcription itself happens live while the key is held.
public struct DictationPipeline: Sendable {
    let cleaner: TranscriptCleaner?
    let vocabulary: [String]

    public init(cleaner: TranscriptCleaner?, vocabulary: [String]) {
        self.cleaner = cleaner
        self.vocabulary = vocabulary
    }

    /// - Parameter onCleanupStart: called when Claude polishing begins (skipped for short, clean phrases).
    public func polish(_ transcript: String, releasedAt start: Date,
                       onCleanupStart: @Sendable () -> Void = {}) async throws -> DictationResult {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw HushtypeError.noSpeech }

        var cleaned = raw
        if let cleaner, TranscriptCleaner.needsPolish(raw) {
            onCleanupStart()
            // A failed cleanup should never lose the dictation; fall back to the raw transcript.
            cleaned = (try? await cleaner.clean(raw, vocabulary: vocabulary)) ?? raw
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
