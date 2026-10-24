import Foundation

/// The services Hushtype holds an API key for.
public enum APIService: String, CaseIterable, Identifiable, Sendable {
    case anthropic

    public var id: String { rawValue }

    public var displayName: String { "Anthropic" }

    /// Where to create a key.
    public var keysURL: URL { URL(string: "https://console.anthropic.com/settings/keys")! }
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
