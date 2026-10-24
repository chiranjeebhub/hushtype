import Foundation

/// A spoken shortcut: say the trigger, get the full text.
public struct Snippet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    /// What you say, like "my calendar link".
    public var trigger: String
    /// What gets typed.
    public var expansion: String

    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }

    var isUsable: Bool { !SnippetExpander.normalize(trigger).isEmpty && !expansion.isEmpty }
}

public enum SnippetExpander {
    /// When the whole dictation is a trigger ("insert my calendar link"), its expansion, typed as is.
    public static func wholeMatch(_ transcript: String, in snippets: [Snippet]) -> String? {
        var spoken = normalize(transcript)
        for lead in ["insert ", "paste ", "type "] where spoken.hasPrefix(lead) {
            spoken = String(spoken.dropFirst(lead.count))
        }
        return snippets.first { $0.isUsable && normalize($0.trigger) == spoken }?.expansion
    }

    /// Replaces triggers spoken inside a sentence with their expansions.
    public static func expand(_ text: String, with snippets: [Snippet]) -> String {
        var result = text
        // Longer triggers first, so "my work address" wins over "my address".
        for snippet in snippets.filter(\.isUsable).sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let words = normalize(snippet.trigger).split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "[\\s,]+") + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range,
                                                    withTemplate: NSRegularExpression.escapedTemplate(for: snippet.expansion))
        }
        return result
    }

    /// Lowercased words without punctuation, single-spaced.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .joined(separator: " ")
    }
}
