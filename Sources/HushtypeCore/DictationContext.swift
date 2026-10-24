import Foundation

/// How the polished text should sound, picked from the app you're dictating into.
public enum WritingStyle: String, Sendable, Equatable {
    /// Chat apps: relaxed punctuation, contractions, no sign-offs.
    case casual
    /// Email and documents: full sentences and proper punctuation.
    case formal
    /// Editors and terminals: keep identifiers, symbols and casing exactly as spoken.
    case technical
    /// Anything else.
    case neutral

    /// Picks a style from the app's bundle identifier.
    public static func forApp(bundleID: String?) -> WritingStyle {
        guard let id = bundleID?.lowercased() else { return .neutral }
        if casualApps.contains(where: id.hasPrefix) { return .casual }
        if formalApps.contains(where: id.hasPrefix) { return .formal }
        if technicalApps.contains(where: id.hasPrefix) { return .technical }
        return .neutral
    }

    static let casualApps = [
        "com.tinyspeck.slackmacgap", "com.apple.mobilesms", "com.apple.ichat", "net.whatsapp", "desktop.whatsapp",
        "com.hnc.discord", "org.telegram", "ru.keepcoder.telegram", "com.facebook.archon", "org.whispersystems.signal",
        "com.microsoft.teams", "us.zoom.xos",
    ]
    static let formalApps = [
        "com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail", "com.superhuman",
        "com.apple.iwork.pages", "com.microsoft.word", "notion.id", "com.linear",
    ]
    static let technicalApps = [
        "com.apple.dt.xcode", "com.microsoft.vscode", "com.todesktop.230313mzl4w4u92", "com.apple.terminal",
        "com.googlecode.iterm2", "dev.warp", "com.mitchellh.ghostty", "com.jetbrains", "dev.zed", "com.sublimetext",
    ]

    /// One line for the polish prompt.
    var guidance: String {
        switch self {
        case .casual: return "a chat app: keep it conversational and light; no greeting or sign-off unless spoken; a trailing period on a one-line message is optional"
        case .formal: return "email or a document: use complete sentences and careful punctuation, but keep the speaker's words"
        case .technical: return "a code editor or terminal: keep identifiers, file names, flags and symbols exactly as spoken; add no prose punctuation to commands"
        case .neutral: return "a general app: use standard written style"
        }
    }
}

/// What Hushtype knows about where the text is going: the app and the text around the cursor.
/// Captured when the dictation key goes down.
public struct DictationContext: Sendable, Equatable {
    public var appName: String?
    public var bundleID: String?
    /// Text just before the cursor (or selection), most recent last.
    public var textBefore: String
    /// Text just after the cursor (or selection).
    public var textAfter: String
    /// The currently selected text, if any.
    public var selectedText: String
    /// Where the cursor or selection starts in the field, in UTF-16 units, when the app reports it.
    public var selectionLocation: Int?

    /// How many characters of surrounding text to keep on each side.
    public static let beforeLimit = 600
    public static let afterLimit = 200

    public init(appName: String? = nil, bundleID: String? = nil, textBefore: String = "", textAfter: String = "",
                selectedText: String = "", selectionLocation: Int? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.textBefore = String(textBefore.suffix(Self.beforeLimit))
        self.textAfter = String(textAfter.prefix(Self.afterLimit))
        self.selectedText = selectedText
        self.selectionLocation = selectionLocation
    }

    public var style: WritingStyle { WritingStyle.forApp(bundleID: bundleID) }

    public var hasSelection: Bool { !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// True when the cursor sits in the middle of a sentence, so the dictation continues it.
    public var continuesSentence: Bool {
        guard let last = textBefore.last(where: { !$0.isWhitespace }) else { return false }
        return !".!?:;\n…\"”)]}".contains(last)
    }

    /// Names and jargon visible near the cursor, to help the transcriber spell them.
    /// Picks capitalized words that don't start a sentence, mixed-case words and words with digits.
    public var nearbyTerms: [String] {
        Self.terms(in: textBefore + " " + selectedText + " " + textAfter)
    }

    static func terms(in text: String, limit: Int = 30) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        var sentenceStart = true
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            let word = raw.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-_.@")))
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            defer { sentenceStart = raw.last.map { ".!?".contains($0) } ?? false }
            guard word.count >= 3, word.count <= 40, word.contains(where: \.isLetter) else { continue }
            let first = word.first!
            let innerCaps = word.dropFirst().contains(where: \.isUppercase) && word.contains(where: \.isLowercase)
            let hasDigit = word.contains(where: \.isNumber)
            let capitalized = first.isUppercase && !sentenceStart && word.dropFirst().contains(where: \.isLowercase)
            guard innerCaps || hasDigit || capitalized else { continue }
            if word == "I'm" || word == "I've" || word == "I'll" || word == "I'd" { continue }
            if seen.insert(word.lowercased()).inserted {
                result.append(word)
                if result.count == limit { break }
            }
        }
        return result
    }

    /// Fits text to the spot it's going into: adds a space after a word and lowercases the first
    /// letter when it continues a sentence. Claude handles this too; this covers the fast path
    /// that skips Claude.
    public func fit(_ text: String) -> String {
        var text = text
        guard !text.isEmpty, !hasSelection else { return text }
        if continuesSentence, let first = text.first, first.isUppercase {
            let firstWord = text.prefix(while: { $0.isLetter || $0 == "'" })
            // Leave "I", acronyms and names that look like names alone.
            let isAcronym = firstWord.count > 1 && firstWord.allSatisfy { !$0.isLowercase }
            let isPronoun = firstWord == "I" || firstWord.hasPrefix("I'")
            let isKnownName = nearbyTerms.contains(String(firstWord))
            if !isAcronym && !isPronoun && !isKnownName {
                text = first.lowercased() + text.dropFirst()
            }
        }
        // Mid-sentence insertions shouldn't end with the period the transcriber adds.
        if let next = textAfter.first(where: { !$0.isWhitespace }), next.isLowercase, text.hasSuffix("."),
           !text.hasSuffix("...") {
            text.removeLast()
        }
        if let last = textBefore.last, !last.isWhitespace, !"([{\"“'/-".contains(last),
           let first = text.first, !first.isWhitespace, !",.;:!?)]}".contains(first) {
            text = " " + text
        }
        if let next = textAfter.first, !next.isWhitespace, !",.;:!?)]}".contains(next),
           let last = text.last, !last.isWhitespace {
            text += " "
        }
        return text
    }
}
