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

    func testRequestStreamsAndCachesSystemPrompt() throws {
        let request = try TranscriptCleaner(apiKey: "k").makeRequest(transcript: "hello there", vocabulary: [])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        let system = try XCTUnwrap(body["system"] as? [[String: Any]])
        XCTAssertEqual(system.first?["text"] as? String, TranscriptCleaner.systemPrompt)
        XCTAssertNotNil(system.first?["cache_control"])
        XCTAssertLessThanOrEqual(try XCTUnwrap(body["max_tokens"] as? Int), 4096)
    }

    func testRequestCarriesContext() throws {
        let context = DictationContext(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap",
                                       textBefore: "Thanks Priyanka, I'll", textAfter: "")
        let request = try TranscriptCleaner(apiKey: "k").makeRequest(transcript: "send it tomorrow", vocabulary: [],
                                                                     context: context)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        let content = try XCTUnwrap((body["messages"] as? [[String: Any]])?.first?["content"] as? String)
        XCTAssertTrue(content.contains("<app>\nSlack — com.tinyspeck.slackmacgap"))
        XCTAssertTrue(content.contains("chat app"))
        XCTAssertTrue(content.contains("<before_cursor>\nThanks Priyanka, I'll\n</before_cursor>"))
        XCTAssertFalse(content.contains("<after_cursor>"))
    }

    func testStreamEvents() {
        XCTAssertEqual(TranscriptCleaner.streamEvent(from: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#), .text("Hi"))
        XCTAssertEqual(TranscriptCleaner.streamEvent(from: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":1}}"#), .stop("refusal"))
        XCTAssertEqual(TranscriptCleaner.streamEvent(from: #"data: {"type":"message_stop"}"#), .end)
        XCTAssertEqual(TranscriptCleaner.streamEvent(from: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#), .error("Overloaded"))
        XCTAssertNil(TranscriptCleaner.streamEvent(from: "event: content_block_delta"))
        XCTAssertNil(TranscriptCleaner.streamEvent(from: #"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"x"}}"#))
    }
}

final class DictationContextTests: XCTestCase {
    func testStyleFromBundleID() {
        XCTAssertEqual(WritingStyle.forApp(bundleID: "com.tinyspeck.slackmacgap"), .casual)
        XCTAssertEqual(WritingStyle.forApp(bundleID: "com.apple.mail"), .formal)
        XCTAssertEqual(WritingStyle.forApp(bundleID: "com.microsoft.VSCode"), .technical)
        XCTAssertEqual(WritingStyle.forApp(bundleID: "com.example.unknown"), .neutral)
        XCTAssertEqual(WritingStyle.forApp(bundleID: nil), .neutral)
    }

    func testNearbyTermsPicksNamesNotSentenceStarts() {
        let context = DictationContext(textBefore: "Hello team. Can Priyanka review the PR4 changes in HushtypeCore? The")
        let terms = context.nearbyTerms
        XCTAssertTrue(terms.contains("Priyanka"))
        XCTAssertTrue(terms.contains("PR4"))
        XCTAssertTrue(terms.contains("HushtypeCore"))
        XCTAssertFalse(terms.contains("Hello"))
        XCTAssertFalse(terms.contains("Can"))
        XCTAssertFalse(terms.contains("The"))
    }

    func testFitContinuesSentence() {
        let context = DictationContext(textBefore: "I think we should", textAfter: "")
        XCTAssertEqual(context.fit("Ship it on Friday."), " ship it on Friday.")
        XCTAssertEqual(context.fit("I agree."), " I agree.")
        XCTAssertEqual(context.fit("API changes first."), " API changes first.")
    }

    func testFitAfterSentenceKeepsCapitalAndAddsSpace() {
        let context = DictationContext(textBefore: "Done.", textAfter: "")
        XCTAssertEqual(context.fit("Next step is review."), " Next step is review.")
        XCTAssertEqual(DictationContext(textBefore: "Done. ").fit("Next."), "Next.")
        XCTAssertEqual(DictationContext().fit("Hello."), "Hello.")
    }

    func testFitMidSentenceDropsPeriodAndSpacesAfter() {
        let context = DictationContext(textBefore: "we can ", textAfter: "tomorrow if needed")
        XCTAssertEqual(context.fit("Meet at noon."), "meet at noon ")
    }

    func testFitLeavesSelectionReplacementAlone() {
        let context = DictationContext(textBefore: "we", textAfter: "", selectedText: "old words")
        XCTAssertEqual(context.fit("New words."), "New words.")
    }
}

final class LatencyStatsTests: XCTestCase {
    func testPercentiles() throws {
        let stats = try XCTUnwrap(LatencyStats([0.5, 0.4, 0.6, 0.3, 2.0, 0.5, 0.45, 0.55, 0.35, 0.7]))
        XCTAssertEqual(stats.count, 10)
        XCTAssertEqual(stats.median, 0.5)
        XCTAssertEqual(stats.p90, 0.7)
        XCTAssertNil(LatencyStats([]))
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
