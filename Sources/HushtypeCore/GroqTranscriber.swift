import Foundation

/// Groq's OpenAI-compatible Whisper endpoint.
public struct GroqTranscriber: Transcriber {
    public let name = "Groq"
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String = "whisper-large-v3-turbo", session: URLSession = .shared) {
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
        var form = MultipartForm()
        form.addFile("file", filename: "audio.wav", mimeType: "audio/wav", data: wav)
        form.addField("model", model)
        form.addField("response_format", "json")
        form.addField("temperature", "0")
        if let language = options.language { form.addField("language", language) }
        if !options.vocabulary.isEmpty {
            // Whisper uses the prompt as preceding context, which biases spelling of these terms.
            form.addField("prompt", options.vocabulary.joined(separator: ", "))
        }

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()
        return request
    }

    static func parse(_ data: Data) throws -> String {
        struct Response: Decodable { let text: String }
        do {
            return try JSONDecoder().decode(Response.self, from: data).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw HushtypeError.badResponse("Groq: \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
    }
}
