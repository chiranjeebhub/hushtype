import Foundation

/// The cloud services Hushtype can use, each with its own API key.
public enum APIService: String, CaseIterable, Identifiable, Sendable {
    case groq, deepgram, anthropic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .deepgram: return "Deepgram"
        case .anthropic: return "Anthropic"
        }
    }

    /// Where to create a key.
    public var keysURL: URL {
        switch self {
        case .groq: return URL(string: "https://console.groq.com/keys")!
        case .deepgram: return URL(string: "https://console.deepgram.com/")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .groq: return "gsk_…"
        case .deepgram: return "Deepgram API key"
        case .anthropic: return "sk-ant-…"
        }
    }
}

public enum KeyValidation: Equatable, Sendable {
    case valid
    case invalid
    /// The check itself failed (offline, service down), so the key may still be fine.
    case unreachable(String)
}

/// Checks a key with a cheap authenticated read, so typos show up during setup instead of mid-dictation.
public enum APIKeyValidator {
    public static func validate(_ key: String, for service: APIService,
                                session: URLSession = .shared) async -> KeyValidation {
        do {
            let (_, response) = try await session.data(for: request(for: service, key: key))
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return .unreachable("No response") }
            return classify(status: status)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    static func request(for service: APIService, key: String) -> URLRequest {
        var request: URLRequest
        switch service {
        case .groq:
            request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .deepgram:
            request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
            request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(TranscriptCleaner.apiVersion, forHTTPHeaderField: "anthropic-version")
        }
        request.timeoutInterval = 10
        return request
    }

    static func classify(status: Int) -> KeyValidation {
        switch status {
        case 200..<300: return .valid
        case 401, 403: return .invalid
        default: return .unreachable("HTTP \(status)")
        }
    }
}
