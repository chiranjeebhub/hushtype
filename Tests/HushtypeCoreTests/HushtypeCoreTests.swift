import XCTest
@testable import HushtypeCore

final class WAVEncoderTests: XCTestCase {
    func testHeaderDescribes16kMonoPCM() {
        let wav = WAVEncoder.encode(samples: [0, 1, -1, Int16.max], sampleRate: 16_000)
        XCTAssertEqual(wav.count, 44 + 8)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(wav.uint32(at: 4), 36 + 8)
        XCTAssertEqual(wav.uint16(at: 22), 1)          // channels
        XCTAssertEqual(wav.uint32(at: 24), 16_000)     // sample rate
        XCTAssertEqual(wav.uint32(at: 28), 32_000)     // byte rate
        XCTAssertEqual(wav.uint32(at: 40), 8)          // data size
        XCTAssertEqual(wav.uint16(at: 50), UInt16(Int16.max))
    }

    func testFloatConversionClips() {
        XCTAssertEqual(WAVEncoder.pcm16(from: [0, 1, -1, 2, -2]), [0, Int16.max, -Int16.max, Int16.max, -Int16.max])
    }
}

final class TranscriberRequestTests: XCTestCase {
    let options = TranscriptionOptions(language: "en", vocabulary: ["Hushtype", "Kubernetes"])

    func testGroqRequestIsMultipartWithPrompt() throws {
        let request = GroqTranscriber(apiKey: "gsk_test").makeRequest(wav: Data([1, 2, 3]), options: options)
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gsk_test")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen"))
        XCTAssertTrue(body.contains("name=\"prompt\"\r\n\r\nHushtype, Kubernetes"))
        XCTAssertTrue(body.contains("filename=\"audio.wav\""))
    }

    func testGroqParsesText() throws {
        XCTAssertEqual(try GroqTranscriber.parse(Data(#"{"text":" Hello world. "}"#.utf8)), "Hello world.")
        XCTAssertThrowsError(try GroqTranscriber.parse(Data("nope".utf8)))
    }

    func testDeepgramRequestCarriesKeyterms() {
        let request = DeepgramTranscriber(apiKey: "dg").makeRequest(wav: Data([1]), options: options)
        let url = request.url!.absoluteString
        XCTAssertTrue(url.hasPrefix("https://api.deepgram.com/v1/listen?"))
        XCTAssertTrue(url.contains("model=nova-3"))
        XCTAssertTrue(url.contains("keyterm=Hushtype"))
        XCTAssertTrue(url.contains("keyterm=Kubernetes"))
        XCTAssertTrue(url.contains("language=en"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token dg")
        XCTAssertEqual(request.httpBody, Data([1]))
    }

    func testDeepgramAutoDetectsLanguageWhenUnset() {
        let request = DeepgramTranscriber(apiKey: "dg")
            .makeRequest(wav: Data(), options: TranscriptionOptions(language: nil))
        XCTAssertTrue(request.url!.absoluteString.contains("detect_language=true"))
    }

    func testDeepgramParsesTranscript() throws {
        let json = #"{"results":{"channels":[{"alternatives":[{"transcript":"Ship it on Friday."}]}]}}"#
        XCTAssertEqual(try DeepgramTranscriber.parse(Data(json.utf8)), "Ship it on Friday.")
    }

    func testLocalWhisperArgumentsAndParsing() {
        let engine = LocalWhisperTranscriber(executablePath: "/bin/whisper-cli", modelPath: "/m.bin")
        XCTAssertEqual(engine.arguments(audioPath: "/a.wav", options: TranscriptionOptions(language: nil)),
                       ["-m", "/m.bin", "-f", "/a.wav", "-nt", "-np", "-l", "auto"])
        XCTAssertEqual(LocalWhisperTranscriber.parse("\n Hello there.\n  How are you?\n"), "Hello there. How are you?")
    }
}

final class TranscriptCleanerTests: XCTestCase {
    func testRequestShape() throws {
        let request = try TranscriptCleaner(apiKey: "sk-ant-test")
            .makeRequest(transcript: "um so the meeting is at 5 no 6", vocabulary: ["Hushtype"])
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "anthropic-version"))

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertNil(body["temperature"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(content.contains("<transcript>\num so the meeting is at 5 no 6\n</transcript>"))
        XCTAssertTrue(content.contains("<dictionary>\nHushtype\n</dictionary>"))
    }

    func testParseJoinsTextBlocksAndSkipsThinking() {
        let json = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"The meeting is at 6."}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(TranscriptCleaner.parse(Data(json.utf8)), "The meeting is at 6.")
    }

    func testParseReturnsNilOnRefusalOrEmpty() {
        XCTAssertNil(TranscriptCleaner.parse(Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)))
        XCTAssertNil(TranscriptCleaner.parse(Data(#"{"content":[{"type":"text","text":"  "}],"stop_reason":"end_turn"}"#.utf8)))
    }
}

final class DictationPipelineTests: XCTestCase {
    struct FakeTranscriber: Transcriber {
        let name = "fake"
        let text: String
        func transcribe(wav: Data, options: TranscriptionOptions) async throws -> String { text }
    }

    func testRawTranscriptPassesThroughWithoutCleaner() async throws {
        let pipeline = DictationPipeline(transcriber: FakeTranscriber(text: "hello"), cleaner: nil, options: .init())
        let result = try await pipeline.run(wav: Data())
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.raw, "hello")
    }

    func testEmptyTranscriptThrowsNoSpeech() async {
        let pipeline = DictationPipeline(transcriber: FakeTranscriber(text: ""), cleaner: nil, options: .init())
        do {
            _ = try await pipeline.run(wav: Data())
            XCTFail("expected noSpeech")
        } catch {
            XCTAssertEqual(error as? HushtypeError, .noSpeech)
        }
    }

    func testVocabularySplitsLinesAndCommas() {
        XCTAssertEqual(DictationPipeline.vocabulary(from: "Hushtype\n  Chiranjeeb , Kubernetes\n\n"),
                       ["Hushtype", "Chiranjeeb", "Kubernetes"])
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[offset + $1]) << (8 * UInt32($1)) }
    }
}

final class APIKeyValidatorTests: XCTestCase {
    func testRequestsAuthenticateEachService() {
        let groq = APIKeyValidator.request(for: .groq, key: "k")
        XCTAssertEqual(groq.url?.host, "api.groq.com")
        XCTAssertEqual(groq.value(forHTTPHeaderField: "Authorization"), "Bearer k")

        let deepgram = APIKeyValidator.request(for: .deepgram, key: "k")
        XCTAssertEqual(deepgram.value(forHTTPHeaderField: "Authorization"), "Token k")

        let anthropic = APIKeyValidator.request(for: .anthropic, key: "k")
        XCTAssertEqual(anthropic.url?.absoluteString, "https://api.anthropic.com/v1/models")
        XCTAssertEqual(anthropic.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertNotNil(anthropic.value(forHTTPHeaderField: "anthropic-version"))
    }

    func testStatusClassification() {
        XCTAssertEqual(APIKeyValidator.classify(status: 200), .valid)
        XCTAssertEqual(APIKeyValidator.classify(status: 401), .invalid)
        XCTAssertEqual(APIKeyValidator.classify(status: 403), .invalid)
        XCTAssertEqual(APIKeyValidator.classify(status: 503), .unreachable("HTTP 503"))
    }
}
