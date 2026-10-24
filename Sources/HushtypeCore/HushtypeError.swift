import Foundation

public enum HushtypeError: LocalizedError, Equatable {
    case missingAPIKey(String)
    case http(service: String, status: Int, body: String)
    case badResponse(String)
    case localEngine(String)
    case noSpeech

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let service):
            return "Add your \(service) API key in Settings."
        case .http(let service, let status, let body):
            return "\(service) returned HTTP \(status): \(body.prefix(200))"
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        case .localEngine(let detail):
            return "Local Whisper failed: \(detail)"
        case .noSpeech:
            return "No speech detected."
        }
    }
}

enum HTTP {
    /// Sends a request and returns the body, throwing `HushtypeError.http` on non-2xx status.
    static func send(_ request: URLRequest, service: String, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HushtypeError.badResponse("\(service): not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HushtypeError.http(service: service, status: http.statusCode,
                                     body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
