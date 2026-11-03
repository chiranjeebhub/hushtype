import Foundation

/// Which model polishes transcripts and runs spoken commands.
public enum CleanupEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Apple's on-device model (Apple Intelligence): free, private and works offline.
    case onDevice
    /// Claude Haiku over the Anthropic API, with the user's own key.
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .onDevice: return "On-device"
        case .claude: return "Claude"
        }
    }

    /// What the engine is called in messages ("Claude was slow…").
    public var serviceName: String {
        switch self {
        case .onDevice: return "Apple Intelligence"
        case .claude: return "Claude"
        }
    }

    /// The engine a fresh install starts on: on-device when this device can run it, unless the
    /// user already set up Claude.
    public static func preferred(hasClaudeKey: Bool) -> CleanupEngine {
        if hasClaudeKey { return .claude }
        return OnDeviceCleaner.availability == .available ? .onDevice : .claude
    }
}

/// Something that cleans dictated transcripts and rewrites selections: Claude or the on-device model.
public protocol TranscriptPolisher: Sendable {
    var engine: CleanupEngine { get }

    /// Gets the engine ready ahead of the request (a TLS handshake, or loading the model).
    func prewarm()

    /// Cleans a transcript. Returns nil when the engine declines or returns nothing.
    func clean(_ transcript: String, vocabulary: [String], context: DictationContext?,
               keepVerbatim: [String]) async throws -> TranscriptCleaner.Output?

    /// Rewrites `selection` (or writes new text when it's empty) following a spoken instruction.
    func rewrite(selection: String, instruction: String, context: DictationContext?) async throws -> TranscriptCleaner.Output?
}

public extension TranscriptPolisher {
    func clean(_ transcript: String, vocabulary: [String], context: DictationContext? = nil) async throws -> TranscriptCleaner.Output? {
        try await clean(transcript, vocabulary: vocabulary, context: context, keepVerbatim: [])
    }
}

extension TranscriptCleaner: TranscriptPolisher {
    public var engine: CleanupEngine { .claude }
}

/// Runs `work`, throwing `TranscriptCleaner.Timeout` if it takes longer than `limit`.
func withDeadline<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw TranscriptCleaner.Timeout()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
