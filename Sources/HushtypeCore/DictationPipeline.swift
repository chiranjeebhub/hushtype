import Foundation

/// Where the time went between letting go of the key and the text landing.
public struct DictationTimings: Codable, Equatable, Sendable {
    /// Release → final transcript from the on-device transcriber.
    public var transcribe: TimeInterval
    /// Claude request → first word of the reply, when Claude ran.
    public var polishFirstToken: TimeInterval?
    /// Claude request → end of the reply, when Claude ran.
    public var polish: TimeInterval?
    /// Release → text ready to paste.
    public var total: TimeInterval

    public init(transcribe: TimeInterval, polishFirstToken: TimeInterval? = nil, polish: TimeInterval? = nil,
                total: TimeInterval) {
        self.transcribe = transcribe
        self.polishFirstToken = polishFirstToken
        self.polish = polish
        self.total = total
    }
}

public struct DictationResult: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case dictation
        case command
    }

    public let id: UUID
    public let raw: String
    public let cleaned: String
    public let date: Date
    public let timings: DictationTimings
    public var kind: Kind
    public var appName: String?
    /// Why Claude's version wasn't used, when it wasn't ("timed out", an error message).
    public var fallbackReason: String?

    public init(id: UUID = UUID(), raw: String, cleaned: String, date: Date = Date(), timings: DictationTimings,
                kind: Kind = .dictation, appName: String? = nil, fallbackReason: String? = nil) {
        self.id = id
        self.raw = raw
        self.cleaned = cleaned
        self.date = date
        self.timings = timings
        self.kind = kind
        self.appName = appName
        self.fallbackReason = fallbackReason
    }

    public var text: String { cleaned }

    /// Seconds from key release to text ready.
    public var duration: TimeInterval { timings.total }
}

/// Transcript in, polished text out. Transcription itself happens live while the key is held.
public struct DictationPipeline: Sendable {
    let cleaner: TranscriptCleaner?
    let vocabulary: [String]
    let context: DictationContext?

    public init(cleaner: TranscriptCleaner?, vocabulary: [String], context: DictationContext? = nil) {
        self.cleaner = cleaner
        self.vocabulary = vocabulary
        self.context = context
    }

    /// - Parameters:
    ///   - releasedAt: when the key was released.
    ///   - transcribedAt: when the final transcript arrived; defaults to now.
    ///   - onCleanupStart: called when Claude polishing begins (skipped for short, clean phrases).
    public func polish(_ transcript: String, releasedAt start: Date, transcribedAt: Date = Date(),
                       onCleanupStart: @Sendable () -> Void = {}) async throws -> DictationResult {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw HushtypeError.noSpeech }

        var cleaned = raw
        var firstToken: TimeInterval?
        var polishTime: TimeInterval?
        var fallbackReason: String?
        if let cleaner, TranscriptCleaner.needsPolish(raw) {
            onCleanupStart()
            // A failed or slow cleanup should never lose the dictation; fall back to the raw transcript.
            do {
                if let output = try await cleaner.clean(raw, vocabulary: vocabulary, context: context) {
                    cleaned = output.text
                    firstToken = output.firstToken
                    polishTime = output.total
                }
            } catch is TranscriptCleaner.Timeout {
                fallbackReason = "Claude was slow, so the transcript was inserted as heard."
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                fallbackReason = error.localizedDescription
            }
        }
        if let context { cleaned = context.fit(cleaned) }

        let timings = DictationTimings(transcribe: transcribedAt.timeIntervalSince(start),
                                       polishFirstToken: firstToken, polish: polishTime,
                                       total: Date().timeIntervalSince(start))
        return DictationResult(raw: raw, cleaned: cleaned, timings: timings, appName: context?.appName,
                               fallbackReason: fallbackReason)
    }

    /// Runs a spoken command on the selected text (or writes new text when nothing is selected).
    public func command(_ instruction: String, selection: String, releasedAt start: Date,
                        transcribedAt: Date = Date()) async throws -> DictationResult {
        let spoken = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { throw HushtypeError.noSpeech }
        guard let cleaner else { throw HushtypeError.missingAPIKey("Anthropic") }
        guard let output = try await cleaner.rewrite(selection: selection, instruction: spoken, context: context) else {
            throw HushtypeError.badResponse("Claude didn't return any text for that command.")
        }
        let timings = DictationTimings(transcribe: transcribedAt.timeIntervalSince(start),
                                       polishFirstToken: output.firstToken, polish: output.total,
                                       total: Date().timeIntervalSince(start))
        return DictationResult(raw: spoken, cleaned: output.text, timings: timings, kind: .command,
                               appName: context?.appName)
    }

    /// Splits the dictionary text (one entry per line or comma-separated) into terms.
    public static func vocabulary(from text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Percentiles over recent dictations, for the speed readout in Settings.
public struct LatencyStats: Equatable, Sendable {
    public let count: Int
    public let median: TimeInterval
    public let p90: TimeInterval

    public init?(_ durations: [TimeInterval]) {
        guard !durations.isEmpty else { return nil }
        let sorted = durations.sorted()
        count = sorted.count
        median = Self.percentile(sorted, 0.5)
        p90 = Self.percentile(sorted, 0.9)
    }

    /// Nearest-rank percentile of already sorted values.
    static func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[max(0, min(sorted.count - 1, rank - 1))]
    }
}
