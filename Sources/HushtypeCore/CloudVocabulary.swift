import Foundation

/// The dictionary and snippets in iCloud key-value storage, so a Mac and an iPhone on the same
/// Apple ID sync with no pairing. It holds the same `SyncVocabulary` as the sync server and merges
/// the same way, item by item, so iCloud and the server can both be on without fighting: each
/// device merges whatever it finds in both places.
///
/// The Mac app and the iPhone app share one store: both apps' entitlements set
/// `com.apple.developer.ubiquity-kvstore-identifier` to `<team>.app.hushtype.Hushtype`.
public enum CloudVocabulary {
    static let key = "vocabulary.v1"
    /// What Hushtype 0.3.7 and earlier wrote on the Mac: the whole dictionary as text, and the
    /// snippets as JSON. Read once and merged in, never written any more.
    static let legacyDictionaryKey = "dictionary"
    static let legacySnippetsKey = "snippets"

    public static func read(from store: NSUbiquitousKeyValueStore = .default) -> SyncVocabulary? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(SyncVocabulary.self, from: $0) }
    }

    /// Writes only when something changed, since iCloud rate-limits writes.
    public static func write(_ vocabulary: SyncVocabulary, to store: NSUbiquitousKeyValueStore = .default) {
        guard read(from: store) != vocabulary, let data = try? JSONEncoder().encode(vocabulary) else { return }
        store.set(data, forKey: key)
        store.synchronize()
    }

    /// The words and snippets an older Mac left in iCloud, for a one-time merge.
    public static func legacy(from store: NSUbiquitousKeyValueStore = .default) -> (terms: [String], snippets: [Snippet]) {
        let terms = store.string(forKey: legacyDictionaryKey).map(DictationPipeline.vocabulary(from:)) ?? []
        let snippets = store.data(forKey: legacySnippetsKey)
            .flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } ?? []
        return (terms, snippets)
    }

    /// True when this device is signed in to iCloud. Doesn't say whether this build has the
    /// iCloud entitlement; without it, reads come back empty and writes go nowhere.
    public static var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }
}
