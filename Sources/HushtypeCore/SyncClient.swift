import Foundation

/// Talks to the Hushtype sync server: fetches the group's encrypted copy, merges it with this
/// device's, and writes the result back when it changed. Writes are compare-and-swap on the
/// server's version, so two devices syncing at once can't overwrite each other.
public struct SyncClient: Sendable {
    /// The public server. Self-hosters can point the apps at their own copy of sync-server/.
    public static let defaultServer = URL(string: "https://hushtype-sync.chiranjib-jena.workers.dev")!
    /// Matches the server's limit.
    public static let maxBlobBytes = 512 * 1024

    public let server: URL
    public let keys: SyncKeys
    private let session: URLSession

    public init(keys: SyncKeys, server: URL = SyncClient.defaultServer, session: URLSession = .shared) {
        self.keys = keys
        self.server = server
        self.session = session
    }

    private var groupURL: URL { server.appendingPathComponent("v1/groups/\(keys.groupID)") }

    /// One round: pull, merge, push if anything is new to the server.
    /// - Parameters:
    ///   - local: this device's copy, already `reconciled` with its current words and snippets.
    ///   - joining: true when pairing with an existing group, which then has to exist.
    /// - Returns: the merged copy, for the device to apply and keep.
    public func sync(_ local: SyncVocabulary, joining: Bool = false) async throws -> SyncVocabulary {
        var attempt = 0
        while true {
            attempt += 1
            let remote = try await fetch()
            if remote == nil, joining { throw SyncError.noSuchGroup }
            let merged = (remote.map { SyncVocabulary.merge(local: local, remote: $0.vocabulary) } ?? local).compacted()
            if let remote, remote.vocabulary == merged { return merged }
            do {
                try await store(merged, replacing: remote?.version)
                return merged
            } catch SyncError.server(412) where attempt < 4 {
                // Another device wrote first; merge with its copy and try again.
                continue
            }
        }
    }

    struct Remote {
        let vocabulary: SyncVocabulary
        let version: String
    }

    func fetch() async throws -> Remote? {
        let (data, response) = try await send(authorized(groupURL))
        switch response.statusCode {
        case 200:
            guard let version = response.value(forHTTPHeaderField: "ETag") else { throw SyncError.badData }
            return Remote(vocabulary: try keys.open(data), version: version)
        case 404:
            return nil
        default:
            throw Self.error(for: response.statusCode)
        }
    }

    func store(_ vocabulary: SyncVocabulary, replacing version: String?) async throws {
        let blob = try keys.seal(vocabulary)
        guard blob.count <= Self.maxBlobBytes else { throw SyncError.tooLarge }
        var request = authorized(groupURL)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let version {
            request.setValue(version, forHTTPHeaderField: "If-Match")
        } else {
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
        }
        request.httpBody = blob
        let (_, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(for: response.statusCode) }
    }

    private func authorized(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer \(keys.authToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SyncError.offline }
            return (data, http)
        } catch let error as SyncError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SyncError.offline
        }
    }

    static func error(for status: Int) -> SyncError {
        switch status {
        case 401, 403: return .unauthorized
        case 413: return .tooLarge
        default: return .server(status)
        }
    }
}
