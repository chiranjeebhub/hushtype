import Foundation

/// The dictionary and snippets as they travel between devices (Mac, iPhone, Android). Every item
/// carries its own timestamps and a removal is kept as a tombstone, so two devices can merge their
/// copies item by item and a word removed on one stays removed on the others.
///
/// The JSON shape is shared with the Android app; see sync-server/README.md before changing a field name.
public struct SyncVocabulary: Codable, Equatable, Sendable {
    public struct Term: Codable, Equatable, Sendable {
        public var text: String
        /// Epoch milliseconds.
        public var createdAt: Int64
        public var updatedAt: Int64
        public var deleted: Bool
        /// Added by learning from a correction, not typed in by hand.
        public var learned: Bool

        public init(text: String, createdAt: Int64, updatedAt: Int64, deleted: Bool = false, learned: Bool = false) {
            self.text = text
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deleted = deleted
            self.learned = learned
        }

        /// Two devices that add the same word agree on this.
        public var key: String { Self.key(text) }
        public static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }

    public struct SyncSnippet: Codable, Equatable, Sendable {
        /// A UUID string. Upper or lower case both match.
        public var id: String
        public var trigger: String
        public var expansion: String
        public var createdAt: Int64
        public var updatedAt: Int64
        public var deleted: Bool

        public init(id: String, trigger: String, expansion: String, createdAt: Int64, updatedAt: Int64,
                    deleted: Bool = false) {
            self.id = id
            self.trigger = trigger
            self.expansion = expansion
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deleted = deleted
        }

        public var key: String { id.lowercased() }
    }

    public var terms: [Term]
    public var snippets: [SyncSnippet]

    public init(terms: [Term] = [], snippets: [SyncSnippet] = []) {
        self.terms = terms
        self.snippets = snippets
    }

    /// Tombstones older than this are dropped. A device offline for longer may bring a removed
    /// word back, which beats keeping every removal forever.
    public static let tombstoneLifetime: Int64 = 30 * 24 * 60 * 60 * 1000

    public static func now() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

    public var liveTerms: [Term] { terms.filter { !$0.deleted } }
    public var liveSnippets: [SyncSnippet] { snippets.filter { !$0.deleted } }

    // MARK: Merge

    /// Combines two copies item by item: the newer `updatedAt` wins, and on a tie `local` wins.
    /// Items keep the order they have in `local`, with items only `remote` has after them.
    public static func merge(local: SyncVocabulary, remote: SyncVocabulary) -> SyncVocabulary {
        SyncVocabulary(terms: mergeItems(local.terms, remote.terms, key: \.key, updated: \.updatedAt),
                       snippets: mergeItems(local.snippets, remote.snippets, key: \.key, updated: \.updatedAt))
    }

    private static func mergeItems<Item>(_ local: [Item], _ remote: [Item], key: (Item) -> String,
                                         updated: (Item) -> Int64) -> [Item] {
        var remoteByKey: [String: Item] = [:]
        for item in remote {
            let k = key(item)
            if let existing = remoteByKey[k], updated(existing) >= updated(item) { continue }
            remoteByKey[k] = item
        }
        var result: [Item] = []
        var seen = Set<String>()
        for item in local {
            let k = key(item)
            guard seen.insert(k).inserted else { continue }
            if let theirs = remoteByKey[k], updated(theirs) > updated(item) {
                result.append(theirs)
            } else {
                result.append(item)
            }
        }
        for item in remote {
            let k = key(item)
            guard seen.insert(k).inserted, let best = remoteByKey[k] else { continue }
            result.append(best)
        }
        return result
    }

    /// Drops tombstones older than `tombstoneLifetime`.
    public func compacted(now: Int64 = SyncVocabulary.now()) -> SyncVocabulary {
        let cutoff = now - Self.tombstoneLifetime
        return SyncVocabulary(terms: terms.filter { !$0.deleted || $0.updatedAt >= cutoff },
                              snippets: snippets.filter { !$0.deleted || $0.updatedAt >= cutoff })
    }

    // MARK: Following local edits

    /// Brings this record up to date with the device's current dictionary and snippets: new items
    /// are added, changed ones get a new `updatedAt`, and items that are gone become tombstones.
    /// Call it before every merge, so edits made while sync was off still count.
    public func reconciled(terms current: [String], snippets currentSnippets: [Snippet],
                           learned: Set<String> = [], now: Int64 = SyncVocabulary.now()) -> SyncVocabulary {
        var result = self

        var index: [String: Int] = [:]
        for (i, term) in result.terms.enumerated() where index[term.key] == nil { index[term.key] = i }
        var present = Set<String>()
        for text in current {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Term.key(clean)
            guard !key.isEmpty, present.insert(key).inserted else { continue }
            if let i = index[key] {
                if result.terms[i].deleted || result.terms[i].text != clean {
                    result.terms[i].text = clean
                    result.terms[i].deleted = false
                    result.terms[i].updatedAt = max(now, result.terms[i].updatedAt + 1)
                }
            } else {
                index[key] = result.terms.count
                result.terms.append(Term(text: clean, createdAt: now, updatedAt: now, learned: learned.contains(key)))
            }
        }
        for i in result.terms.indices where !result.terms[i].deleted && !present.contains(result.terms[i].key) {
            result.terms[i].deleted = true
            result.terms[i].updatedAt = max(now, result.terms[i].updatedAt + 1)
        }

        var snippetIndex: [String: Int] = [:]
        for (i, snippet) in result.snippets.enumerated() where snippetIndex[snippet.key] == nil {
            snippetIndex[snippet.key] = i
        }
        var presentSnippets = Set<String>()
        for snippet in currentSnippets {
            let key = snippet.id.uuidString.lowercased()
            guard presentSnippets.insert(key).inserted else { continue }
            if let i = snippetIndex[key] {
                let old = result.snippets[i]
                if old.deleted || old.trigger != snippet.trigger || old.expansion != snippet.expansion {
                    result.snippets[i].trigger = snippet.trigger
                    result.snippets[i].expansion = snippet.expansion
                    result.snippets[i].deleted = false
                    result.snippets[i].updatedAt = max(now, old.updatedAt + 1)
                }
            } else {
                snippetIndex[key] = result.snippets.count
                result.snippets.append(SyncSnippet(id: key, trigger: snippet.trigger, expansion: snippet.expansion,
                                                   createdAt: now, updatedAt: now))
            }
        }
        for i in result.snippets.indices
        where !result.snippets[i].deleted && !presentSnippets.contains(result.snippets[i].key) {
            result.snippets[i].deleted = true
            result.snippets[i].updatedAt = max(now, result.snippets[i].updatedAt + 1)
        }
        return result
    }

    /// The device's dictionary after a merge: the words it already had, in their order, minus
    /// removed ones, then new words. Spelling follows the merged copy.
    public func dictionary(keepingOrderOf current: [String]) -> [String] {
        var live: [String: String] = [:]
        for term in liveTerms where live[term.key] == nil { live[term.key] = term.text }
        var result: [String] = []
        var used = Set<String>()
        for text in current {
            let key = Term.key(text)
            guard let spelled = live[key], used.insert(key).inserted else { continue }
            result.append(spelled)
        }
        for term in liveTerms where used.insert(term.key).inserted { result.append(term.text) }
        return result
    }

    /// The device's snippets after a merge, in the same spirit as `dictionary(keepingOrderOf:)`.
    /// Snippets whose id isn't a UUID (never written by Hushtype) are skipped.
    public func snippetList(keepingOrderOf current: [Snippet]) -> [Snippet] {
        var live: [String: SyncSnippet] = [:]
        for snippet in liveSnippets where live[snippet.key] == nil { live[snippet.key] = snippet }
        var result: [Snippet] = []
        var used = Set<String>()
        for snippet in current {
            let key = snippet.id.uuidString.lowercased()
            guard let synced = live[key], used.insert(key).inserted else { continue }
            result.append(Snippet(id: snippet.id, trigger: synced.trigger, expansion: synced.expansion))
        }
        for synced in liveSnippets where used.insert(synced.key).inserted {
            guard let id = UUID(uuidString: synced.id) else { continue }
            result.append(Snippet(id: id, trigger: synced.trigger, expansion: synced.expansion))
        }
        return result
    }
}
