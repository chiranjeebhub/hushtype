import Foundation
import HushtypeCore

enum TriggerKey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn: return "Fn / 🌐"
        case .rightOption: return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        }
    }
}

/// User preferences in UserDefaults; API keys live in the Keychain.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var triggerKey: TriggerKey { didSet { defaults.set(triggerKey.rawValue, forKey: "triggerKey") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var cleanupEnabled: Bool { didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled") } }
    @Published var dictionaryText: String { didSet { defaults.set(dictionaryText, forKey: "dictionary") } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") } }
    /// Keep the mic open all the time so dictation starts instantly and catches the first word.
    @Published var alwaysReadyMic: Bool { didSet { defaults.set(alwaysReadyMic, forKey: "alwaysReadyMic") } }
    /// Send the app name and the text around the cursor to Claude, so it matches tone and spelling.
    @Published var useContext: Bool { didSet { defaults.set(useContext, forKey: "useContext") } }
    /// Add a word to the dictionary when the user respells it after Hushtype typed it.
    @Published var learnFromCorrections: Bool { didSet { defaults.set(learnFromCorrections, forKey: "learnFromCorrections") } }
    /// Spoken shortcuts that expand to saved text.
    @Published var snippets: [Snippet] {
        didSet { defaults.set(try? JSONEncoder().encode(snippets), forKey: "snippets") }
    }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    /// Where setup resumes after Hushtype relaunches itself mid-onboarding.
    @Published var onboardingStep: Int { didSet { defaults.set(onboardingStep, forKey: "onboardingStep") } }

    init() {
        triggerKey = TriggerKey(rawValue: defaults.string(forKey: "triggerKey") ?? "") ?? .rightOption
        language = defaults.string(forKey: "language") ?? "en"
        cleanupEnabled = defaults.object(forKey: "cleanupEnabled") as? Bool ?? true
        dictionaryText = defaults.string(forKey: "dictionary") ?? ""
        soundsEnabled = defaults.object(forKey: "soundsEnabled") as? Bool ?? true
        alwaysReadyMic = defaults.bool(forKey: "alwaysReadyMic")
        useContext = defaults.object(forKey: "useContext") as? Bool ?? true
        learnFromCorrections = defaults.object(forKey: "learnFromCorrections") as? Bool ?? true
        snippets = (defaults.data(forKey: "snippets")).flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } ?? []
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        onboardingStep = defaults.integer(forKey: "onboardingStep")
    }

    var vocabulary: [String] { DictationPipeline.vocabulary(from: dictionaryText) }

    /// Appends terms that aren't in the dictionary yet, one per line.
    func addToDictionary(_ terms: [String]) {
        var known = Set(vocabulary.map { $0.lowercased() })
        var text = dictionaryText
        for term in terms where known.insert(term.lowercased()).inserted {
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += term
        }
        dictionaryText = text
    }

    var transcriptionOptions: TranscriptionOptions {
        TranscriptionOptions(language: language == "auto" ? nil : language, vocabulary: vocabulary)
    }

    func apiKey(_ service: APIService) -> String {
        Keychain.read(account: service.rawValue) ?? ""
    }

    func setAPIKey(_ value: String, for service: APIService) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(account: service.rawValue)
        } else {
            Keychain.write(trimmed, account: service.rawValue)
        }
        objectWillChange.send()
    }

    /// Command mode always needs Claude, even with polishing turned off.
    func makeAssistant() -> TranscriptCleaner? {
        let key = apiKey(.anthropic)
        return key.isEmpty ? nil : TranscriptCleaner(apiKey: key)
    }

    func makeCleaner() -> TranscriptCleaner? {
        let key = apiKey(.anthropic)
        guard cleanupEnabled, !key.isEmpty else { return nil }
        return TranscriptCleaner(apiKey: key)
    }
}
