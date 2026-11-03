import Foundation

public enum HushtypeError: LocalizedError, Equatable {
    case missingAPIKey(String)
    case http(service: String, status: Int, body: String)
    case badResponse(String)
    case speechUnavailable(String)
    case noSpeech

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let service):
            return "Add your \(service) API key in Settings."
        case .http(let service, let status, let body):
            return Self.describe(service: service, status: status, body: body)
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        case .speechUnavailable(let detail):
            return detail
        case .noSpeech:
            return "No speech detected."
        }
    }

    /// A short, readable line for an HTTP failure, instead of the raw JSON body.
    static func describe(service: String, status: Int, body: String) -> String {
        struct Envelope: Decodable {
            struct Detail: Decodable { let message: String? }
            let error: Detail?
        }
        let message = (try? JSONDecoder().decode(Envelope.self, from: Data(body.utf8)))?.error?.message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case 401: return "\(service) didn't accept your API key. Check it in Settings."
        case 429: return "\(service) rate limit reached. Try again in a moment."
        case 500...599: return "\(service) is having trouble right now (HTTP \(status)). Try again shortly."
        default:
            if let message, !message.isEmpty { return "\(service): \(message.prefix(160))" }
            return "\(service) returned HTTP \(status)."
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
