import Foundation

/// Finds words the user fixed by hand after Hushtype inserted text, so the dictionary can learn them.
public enum CorrectionLearner {
    public struct Correction: Equatable, Sendable {
        /// What Hushtype typed.
        public let from: String
        /// What the user changed it to.
        public let to: String
        /// Only the capitalization changed.
        public let caseOnly: Bool
        /// The word starts a sentence, where capitalization says nothing about names.
        public let atSentenceStart: Bool
    }

    /// Compares what was inserted with the same stretch of the field a little later.
    /// `edited` may include extra words on either side; they're ignored.
    /// Returns one-for-one word swaps that look like spelling fixes, not rewrites.
    public static func corrections(inserted: String, edited: String) -> [Correction] {
        let old = words(inserted)
        let new = words(edited)
        guard !old.isEmpty, !new.isEmpty, old.count <= 400, new.count <= 600 else { return [] }

        var result: [Correction] = []
        for hunk in diff(old.map(\.text), new.map(\.text)) {
            // Only same-length replacements of up to three words: a respelling, not new wording.
            guard hunk.removed.count == hunk.added.count, hunk.removed.count <= 3 else { continue }
            for (offset, index) in hunk.removed.enumerated() {
                let from = old[index].text
                let target = new[hunk.added[offset]]
                guard from != target.text, looksLikeRespelling(from, target.text) else { continue }
                result.append(Correction(from: from, to: target.text,
                                         caseOnly: from.lowercased() == target.text.lowercased(),
                                         atSentenceStart: target.atSentenceStart))
            }
        }
        return result
    }

    /// True when `to` is plausibly the same word spelled differently.
    static func looksLikeRespelling(_ from: String, _ to: String) -> Bool {
        let a = Array(from.lowercased()), b = Array(to.lowercased())
        if a == b { return true }
        let distance = editDistance(a, b)
        return distance <= max(2, Int(Double(max(a.count, b.count)) * 0.5))
    }

    struct Word { let text: String; let atSentenceStart: Bool }

    static func words(_ text: String) -> [Word] {
        var result: [Word] = []
        var sentenceStart = true
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            let word = raw.trimmingCharacters(in: CharacterSet.punctuationCharacters
                .union(.symbols).subtracting(CharacterSet(charactersIn: "-_@'")))
            if !word.isEmpty { result.append(Word(text: word, atSentenceStart: sentenceStart)) }
            sentenceStart = raw.last.map { ".!?\n".contains($0) } ?? false
        }
        return result
    }

    struct Hunk { var removed: [Int] = []; var added: [Int] = [] }

    /// Word-level LCS diff of the inserted words `a` against the field's words `b`, returned as runs
    /// of removed (indexes into `a`) and added (indexes into `b`) words. Words of `b` before and
    /// after the inserted stretch are surrounding text and are left out.
    static func diff(_ a: [String], _ b: [String]) -> [Hunk] {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var hunks: [Hunk] = []
        var current = Hunk()
        var i = 0, j = 0, matchedAny = false
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                if !matchedAny {
                    // Leading run: surrounding text, then possibly a respelled first word.
                    if !current.removed.isEmpty {
                        hunks.append(Hunk(removed: current.removed,
                                          added: Array(current.added.suffix(current.removed.count))))
                    }
                } else if !current.removed.isEmpty || !current.added.isEmpty {
                    hunks.append(current)
                }
                current = Hunk()
                matchedAny = true
                i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                current.added.append(j); j += 1
            } else {
                current.removed.append(i); i += 1
            }
        }
        guard !current.removed.isEmpty else { return hunks }
        if matchedAny {
            // Trailing run: a respelled last word, then surrounding text.
            hunks.append(Hunk(removed: current.removed, added: Array(current.added.prefix(current.removed.count))))
        } else if n == 1, let best = current.added.min(by: {
            editDistance(Array(a[0].lowercased()), Array(b[$0].lowercased()))
                < editDistance(Array(a[0].lowercased()), Array(b[$1].lowercased()))
        }) {
            // A single inserted word with nothing else to anchor on: pick the closest word.
            hunks.append(Hunk(removed: [0], added: [best]))
        }
        return hunks
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
