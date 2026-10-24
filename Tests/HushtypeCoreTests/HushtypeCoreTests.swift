import XCTest
@testable import HushtypeCore

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
    func testTranscriptPassesThroughWithoutCleaner() async throws {
        let pipeline = DictationPipeline(cleaner: nil, vocabulary: [])
        let result = try await pipeline.polish("  hello  ", releasedAt: Date())
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.raw, "hello")
    }

    func testEmptyTranscriptThrowsNoSpeech() async {
        let pipeline = DictationPipeline(cleaner: nil, vocabulary: [])
        do {
            _ = try await pipeline.polish(" ", releasedAt: Date())
            XCTFail("expected noSpeech")
        } catch {
            XCTAssertEqual(error as? HushtypeError, .noSpeech)
        }
    }

    func testShortCleanPhraseSkipsClaude() async throws {
        // An empty key would throw if Claude were called; the raw text coming back proves it wasn't.
        let pipeline = DictationPipeline(cleaner: TranscriptCleaner(apiKey: ""), vocabulary: [])
        let result = try await pipeline.polish("Sounds good, see you then.", releasedAt: Date())
        XCTAssertEqual(result.text, "Sounds good, see you then.")
    }

    func testNeedsPolish() {
        XCTAssertFalse(TranscriptCleaner.needsPolish("Sounds good, see you then."))
        XCTAssertTrue(TranscriptCleaner.needsPolish("Um, can you send it over?"))
        XCTAssertTrue(TranscriptCleaner.needsPolish("Meet at 5, no, 6."))
        XCTAssertTrue(TranscriptCleaner.needsPolish("I think the the build is broken."))
        XCTAssertTrue(TranscriptCleaner.needsPolish("This is a longer sentence that has more than eight words in it."))
    }

    func testVocabularySplitsLinesAndCommas() {
        XCTAssertEqual(DictationPipeline.vocabulary(from: "Hushtype\n  Chiranjeeb , Kubernetes\n\n"),
                       ["Hushtype", "Chiranjeeb", "Kubernetes"])
    }
}

final class APIKeyValidatorTests: XCTestCase {
    func testAnthropicRequestIsAuthenticated() {
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
