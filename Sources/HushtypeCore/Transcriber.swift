import Foundation

public struct TranscriptionOptions: Equatable, Sendable {
    /// ISO-639-1 code such as "en", or nil to let the engine detect the language.
    public var language: String?
    /// Names and jargon from the personal dictionary, used to bias recognition.
    public var vocabulary: [String]

    public init(language: String? = "en", vocabulary: [String] = []) {
        self.language = language
        self.vocabulary = vocabulary
    }
}

/// A speech-to-text engine. Audio is always 16 kHz mono 16-bit WAV.
public protocol Transcriber: Sendable {
    var name: String { get }
    func transcribe(wav: Data, options: TranscriptionOptions) async throws -> String
}

public enum TranscriptionEngine: String, CaseIterable, Identifiable, Sendable {
    case groq
    case deepgram
    case localWhisper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .groq: return "Groq Whisper (cloud)"
        case .deepgram: return "Deepgram Nova-3 (cloud)"
        case .localWhisper: return "whisper.cpp (local, private)"
        }
    }
}
