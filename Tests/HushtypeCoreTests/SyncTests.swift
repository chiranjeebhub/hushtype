import Foundation
import XCTest
@testable import HushtypeCore

final class SyncFormatTests: XCTestCase {
    /// Test vector from `node sync-server/reference.mjs`. Android checks the same values.
    let secret = Data(0..<32)

    func testDerivedValuesMatchReference() throws {
        let keys = try XCTUnwrap(SyncKeys(secret: secret))
        XCTAssertEqual(keys.groupID, "8187ad2336c78c03a3802eb930117608")
        XCTAssertEqual(keys.authToken, "5ZN7bna256_f6Ck-1W9euZAu54gAfn1DpAFt9HDKQzU")
        XCTAssertEqual(keys.pairingCode,
                       "HT1-000G-40R4-0M30-E209-185G-R38E-1W81-24GK-2GAH-C5RR-34D1-P70X-3RFG")
    }

    func testOpensBlobSealedByReference() throws {
        let keys = try XCTUnwrap(SyncKeys(secret: secret))
        let blob = try XCTUnwrap(Data(base64Encoded: "AaChoqOkpaanqKmqq+w8k+U+nxPol7F8T1tCZASQ3/wy82AKchj2R7iDTY3TQIs69xlgRBb1L4rvJ9CKbwB2oHzinE3YmwlvqkSy4Br2oO6oUcsrrfBFr4jElm2vJ+0h+N48uLG4htgtB4jJ+bO+d2k7FNX8HiQnMoCsb4g4ikGQ5MZ6kEwYrIsRrHUWko0gnGbMoV7RK/YwS7/FBd/lMCINf7y4FK623S9TPlSEY0BvqR0NmnKx76YEuUWi1fB4ZNsBC6HPqsWebIvCnldejMu0i92FFo8Fq2GF5c95NXZ+C73lyK3166w0ObXGZZvNXxmnn7/nY2SxMF8RXzo4JGojx+gebk227qUz0jDx56mPtqcdNtzp6s7jXkzpG+DTHTA20TAkLmmeTipmAMH+VRILGTozFnPhkEk2EobL1nqEtpif"))
        let vocabulary = try keys.open(blob)
        XCTAssertEqual(vocabulary.terms, [SyncVocabulary.Term(text: "Kubernetes", createdAt: 1763100000000,
                                                               updatedAt: 1763100000000, learned: true)])
        XCTAssertEqual(vocabulary.snippets.first?.trigger, "my link")
        XCTAssertEqual(vocabulary.snippets.first?.updatedAt, 1763100000001)
    }

    func testSealRoundTripAndTamperDetection() throws {
        let keys = SyncKeys.generate()
        let vocabulary = SyncVocabulary(terms: [.init(text: "Hushtype", createdAt: 1, updatedAt: 2)])
        var blob = try keys.seal(vocabulary)
        XCTAssertEqual(try keys.open(blob), vocabulary)
        XCTAssertThrowsError(try SyncKeys.generate().open(blob))
        blob[blob.count - 1] ^= 1
        XCTAssertThrowsError(try keys.open(blob))
    }

    func testPairingCodeIsForgiving() throws {
        let keys = SyncKeys.generate()
        let code = keys.pairingCode
        XCTAssertEqual(SyncKeys(pairingCode: code), keys)
        XCTAssertEqual(SyncKeys(pairingCode: code.lowercased().replacingOccurrences(of: "-", with: " ")), keys)
        let lookAlike = "HT1" + code.dropFirst(3).replacingOccurrences(of: "0", with: "O").replacingOccurrences(of: "1", with: "l")
        XCTAssertEqual(SyncKeys(pairingCode: lookAlike), keys)
        XCTAssertNil(SyncKeys(pairingCode: "HT1-1234"))
        XCTAssertNil(SyncKeys(pairingCode: "hello"))
    }
}

final class SyncVocabularyTests: XCTestCase {
    typealias Term = SyncVocabulary.Term

    func testNewerEditWinsAndTieKeepsLocal() {
        let local = SyncVocabulary(terms: [Term(text: "kubernetes", createdAt: 1, updatedAt: 5),
                                           Term(text: "Jena", createdAt: 1, updatedAt: 3)])
        let remote = SyncVocabulary(terms: [Term(text: "Kubernetes", createdAt: 1, updatedAt: 6),
                                            Term(text: "jena", createdAt: 1, updatedAt: 3),
                                            Term(text: "Swift", createdAt: 2, updatedAt: 2)])
        let merged = SyncVocabulary.merge(local: local, remote: remote)
        XCTAssertEqual(merged.terms.map(\.text), ["Kubernetes", "Jena", "Swift"])
    }

    func testRemovalSticksUntilReAdded() {
        let local = SyncVocabulary(terms: [Term(text: "Foo", createdAt: 1, updatedAt: 1)])
        let remote = SyncVocabulary(terms: [Term(text: "Foo", createdAt: 1, updatedAt: 4, deleted: true)])
        let merged = SyncVocabulary.merge(local: local, remote: remote)
        XCTAssertEqual(merged.dictionary(keepingOrderOf: ["Foo", "Bar"]), [])

        let readded = merged.reconciled(terms: ["Foo"], snippets: [], now: 10)
        XCTAssertEqual(readded.liveTerms.map(\.text), ["Foo"])
        XCTAssertEqual(SyncVocabulary.merge(local: remote, remote: readded).liveTerms.map(\.text), ["Foo"])
    }

    func testReconcileFollowsLocalEdits() {
        let id = UUID()
        let start = SyncVocabulary().reconciled(terms: ["Alpha", "Beta", "beta"],
                                                snippets: [Snippet(id: id, trigger: "sig", expansion: "Thanks")],
                                                learned: ["beta"], now: 100)
        XCTAssertEqual(start.terms.map(\.text), ["Alpha", "Beta"])
        XCTAssertEqual(start.terms.map(\.learned), [false, true])
        XCTAssertEqual(start.snippets.first?.id, id.uuidString.lowercased())

        let unchanged = start.reconciled(terms: ["Alpha", "Beta"],
                                         snippets: [Snippet(id: id, trigger: "sig", expansion: "Thanks")], now: 200)
        XCTAssertEqual(unchanged, start)

        let edited = start.reconciled(terms: ["Beta"], snippets: [Snippet(id: id, trigger: "sig", expansion: "Cheers")],
                                      now: 300)
        XCTAssertEqual(edited.terms.first { $0.text == "Alpha" }?.deleted, true)
        XCTAssertEqual(edited.terms.first { $0.text == "Alpha" }?.updatedAt, 300)
        XCTAssertEqual(edited.snippets.first?.expansion, "Cheers")
        XCTAssertEqual(edited.snippets.first?.updatedAt, 300)
    }

    func testApplyingKeepsLocalOrder() {
        let id = UUID()
        let vocabulary = SyncVocabulary(
            terms: [Term(text: "New", createdAt: 1, updatedAt: 1), Term(text: "kept", createdAt: 1, updatedAt: 1),
                    Term(text: "Gone", createdAt: 1, updatedAt: 2, deleted: true)],
            snippets: [.init(id: id.uuidString.lowercased(), trigger: "t", expansion: "e", createdAt: 1, updatedAt: 1)])
        XCTAssertEqual(vocabulary.dictionary(keepingOrderOf: ["Gone", "Kept"]), ["kept", "New"])
        XCTAssertEqual(vocabulary.snippetList(keepingOrderOf: []).map(\.id), [id])
    }

    func testCompactionDropsOldTombstones() {
        let now: Int64 = SyncVocabulary.tombstoneLifetime + 1000
        let vocabulary = SyncVocabulary(terms: [Term(text: "old", createdAt: 0, updatedAt: 1, deleted: true),
                                                Term(text: "recent", createdAt: 0, updatedAt: now, deleted: true),
                                                Term(text: "live", createdAt: 0, updatedAt: 1)])
        XCTAssertEqual(vocabulary.compacted(now: now).terms.map(\.text), ["recent", "live"])
    }

    func testJSONFieldNamesMatchAndroid() throws {
        let vocabulary = SyncVocabulary(terms: [Term(text: "a", createdAt: 1, updatedAt: 2)],
                                        snippets: [.init(id: "x", trigger: "t", expansion: "e", createdAt: 1, updatedAt: 2)])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(vocabulary)) as? [String: Any])
        let term = try XCTUnwrap((json["terms"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(term.keys), ["text", "createdAt", "updatedAt", "deleted", "learned"])
        let snippet = try XCTUnwrap((json["snippets"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(snippet.keys), ["id", "trigger", "expansion", "createdAt", "updatedAt", "deleted"])
    }
}

/// A stand-in for the sync server, with the same compare-and-swap rules.
final class FakeSyncServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var blob: Data?
    nonisolated(unsafe) static var version = 0
    nonisolated(unsafe) static var token: String?
    /// Writes another device's copy right before the next PUT lands, to force a conflict.
    nonisolated(unsafe) static var interleave: (() -> Void)?
    static let lock = NSLock()

    static func reset() {
        lock.withLock { blob = nil; version = 0; token = nil; interleave = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (status, body, etag) = Self.lock.withLock { () -> (Int, Data?, String?) in
            let auth = request.value(forHTTPHeaderField: "Authorization")
            if let token = Self.token, auth != token { return (401, nil, nil) }
            switch request.httpMethod {
            case "GET":
                guard let blob = Self.blob else { return (404, nil, nil) }
                return (200, blob, "\"\(Self.version)\"")
            case "PUT":
                if let interleave = Self.interleave {
                    Self.interleave = nil
                    interleave()
                }
                let data = request.httpBody ?? Self.read(request.httpBodyStream)
                if request.value(forHTTPHeaderField: "If-None-Match") == "*" {
                    guard Self.blob == nil else { return (412, nil, nil) }
                } else if request.value(forHTTPHeaderField: "If-Match") != "\"\(Self.version)\"" {
                    return (412, nil, nil)
                }
                Self.blob = data
                Self.version += 1
                Self.token = auth
                return (204, nil, "\"\(Self.version)\"")
            default:
                return (405, nil, nil)
            }
        }
        var headers: [String: String] = [:]
        if let etag { headers["ETag"] = etag }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class SyncClientTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        FakeSyncServer.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeSyncServer.self]
        session = URLSession(configuration: configuration)
    }

    func client(_ keys: SyncKeys) -> SyncClient {
        SyncClient(keys: keys, server: URL(string: "https://sync.test")!, session: session)
    }

    func testTwoDevicesConverge() async throws {
        let keys = SyncKeys.generate()
        let mac = SyncVocabulary().reconciled(terms: ["Kubernetes"], snippets: [], now: 10)
        let phone = SyncVocabulary().reconciled(terms: ["Chiranjeeb"], snippets: [], now: 20)

        let afterMac = try await client(keys).sync(mac)
        XCTAssertEqual(afterMac.liveTerms.map(\.text), ["Kubernetes"])

        let afterPhone = try await client(keys).sync(phone, joining: true)
        XCTAssertEqual(Set(afterPhone.liveTerms.map(\.text)), ["Kubernetes", "Chiranjeeb"])

        let macAgain = try await client(keys).sync(afterMac)
        XCTAssertEqual(Set(macAgain.liveTerms.map(\.text)), ["Kubernetes", "Chiranjeeb"])
    }

    func testJoiningUnknownGroupFails() async {
        do {
            _ = try await client(SyncKeys.generate()).sync(SyncVocabulary(), joining: true)
            XCTFail("Expected noSuchGroup")
        } catch {
            XCTAssertEqual(error as? SyncError, .noSuchGroup)
        }
    }

    func testRetriesAfterConflict() async throws {
        let keys = SyncKeys.generate()
        let other = SyncVocabulary().reconciled(terms: ["Other"], snippets: [], now: 5)
        _ = try await client(keys).sync(SyncVocabulary().reconciled(terms: ["First"], snippets: [], now: 1))
        let otherBlob = try keys.seal(SyncVocabulary.merge(
            local: other, remote: SyncVocabulary().reconciled(terms: ["First"], snippets: [], now: 1)))
        FakeSyncServer.interleave = {
            FakeSyncServer.blob = otherBlob
            FakeSyncServer.version += 1
        }
        let mine = SyncVocabulary().reconciled(terms: ["First", "Mine"], snippets: [], now: 9)
        let merged = try await client(keys).sync(mine)
        XCTAssertEqual(Set(merged.liveTerms.map(\.text)), ["First", "Other", "Mine"])
        let stored = try keys.open(try XCTUnwrap(FakeSyncServer.blob))
        XCTAssertEqual(Set(stored.liveTerms.map(\.text)), ["First", "Other", "Mine"])
    }

    func testWrongTokenIsUnauthorized() async throws {
        let keys = SyncKeys.generate()
        _ = try await client(keys).sync(SyncVocabulary().reconciled(terms: ["A"], snippets: [], now: 1))
        FakeSyncServer.lock.withLock { FakeSyncServer.token = "Bearer something-else" }
        do {
            _ = try await client(keys).sync(SyncVocabulary())
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? SyncError, .unauthorized)
        }
    }
}
