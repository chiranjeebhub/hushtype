import Foundation

/// Deepgram pre-recorded audio API.
public struct DeepgramTranscriber: Transcriber {
    public let name = "Deepgram"
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String = "nova-3", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func transcribe(wav: Data, options: TranscriptionOptions) async throws -> String {
        guard !apiKey.isEmpty else { throw HushtypeError.missingAPIKey(name) }
        let data = try await HTTP.send(makeRequest(wav: wav, options: options), service: name, session: session)
        return try Self.parse(data)
    }

    func makeRequest(wav: Data, options: TranscriptionOptions) -> URLRequest {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var items = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]
        if let language = options.language {
            items.append(URLQueryItem(name: "language", value: language))
        } else {
            items.append(URLQueryItem(name: "detect_language", value: "true"))
        }
        // Nova-3 keyterm prompting boosts recognition of dictionary words.
        items += options.vocabulary.map { URLQueryItem(name: "keyterm", value: $0) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wav
        return request
    }

    static func parse(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Results: Decodable { let channels: [Channel] }
            struct Channel: Decodable { let alternatives: [Alternative] }
            struct Alternative: Decodable { let transcript: String }
            let results: Results
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw HushtypeError.badResponse("Deepgram: \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return (response.results.channels.first?.alternatives.first?.transcript ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
