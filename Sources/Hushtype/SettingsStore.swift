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
    /// Save recent dictations on disk so they're there after a restart.
    @Published var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: "keepHistory") } }
    /// Double-tap the dictation key to keep listening without holding it.
    @Published var handsFree: Bool { didSet { defaults.set(handsFree, forKey: "handsFree") } }
    /// Mirror the dictionary, snippets and style settings to iCloud. Kept per Mac.
    @Published var iCloudSync: Bool { didSet { defaults.set(iCloudSync, forKey: "iCloudSync") } }
    /// Keep the Anthropic key in iCloud Keychain. Change it with `setKeySyncing(_:)`.
    @Published private(set) var syncAPIKey: Bool { didSet { defaults.set(syncAPIKey, forKey: "syncAPIKey") } }
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
        keepHistory = defaults.object(forKey: "keepHistory") as? Bool ?? true
        handsFree = defaults.object(forKey: "handsFree") as? Bool ?? true
        iCloudSync = defaults.bool(forKey: "iCloudSync")
        syncAPIKey = defaults.bool(forKey: "syncAPIKey")
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

    /// Whether API keys go to iCloud Keychain right now.
    private var keysSynced: Bool { iCloudSync && syncAPIKey }

    func apiKey(_ service: APIService) -> String {
        Keychain.read(account: service.rawValue, synced: keysSynced) ?? ""
    }

    func setAPIKey(_ value: String, for service: APIService) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(account: service.rawValue, synced: keysSynced)
        } else if !Keychain.write(trimmed, account: service.rawValue, synced: keysSynced) {
            Keychain.write(trimmed, account: service.rawValue)
        }
        objectWillChange.send()
    }

    /// Moves the saved keys into or out of iCloud Keychain. Returns false, leaving everything as it
    /// was, when iCloud Keychain isn't available to this build.
    @discardableResult
    func setKeySyncing(_ on: Bool) -> Bool {
        let wasSynced = keysSynced
        for service in APIService.allCases {
            let key = Keychain.read(account: service.rawValue, synced: wasSynced) ?? ""
            guard !key.isEmpty else { continue }
            if !Keychain.write(key, account: service.rawValue, synced: on && iCloudSync) { return false }
        }
        syncAPIKey = on
        return true
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
