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
    @Published var engine: TranscriptionEngine { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var cleanupEnabled: Bool { didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled") } }
    @Published var dictionaryText: String { didSet { defaults.set(dictionaryText, forKey: "dictionary") } }
    @Published var whisperExecutablePath: String { didSet { defaults.set(whisperExecutablePath, forKey: "whisperExecutablePath") } }
    @Published var whisperModelPath: String { didSet { defaults.set(whisperModelPath, forKey: "whisperModelPath") } }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    /// Where setup resumes after Hushtype relaunches itself mid-onboarding.
    @Published var onboardingStep: Int { didSet { defaults.set(onboardingStep, forKey: "onboardingStep") } }

    init() {
        triggerKey = TriggerKey(rawValue: defaults.string(forKey: "triggerKey") ?? "") ?? .rightOption
        engine = TranscriptionEngine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .groq
        language = defaults.string(forKey: "language") ?? "en"
        cleanupEnabled = defaults.object(forKey: "cleanupEnabled") as? Bool ?? true
        dictionaryText = defaults.string(forKey: "dictionary") ?? ""
        whisperExecutablePath = defaults.string(forKey: "whisperExecutablePath") ?? "/opt/homebrew/bin/whisper-cli"
        whisperModelPath = defaults.string(forKey: "whisperModelPath")
            ?? NSString(string: "~/Library/Application Support/Hushtype/models/ggml-large-v3-turbo-q5_0.bin").expandingTildeInPath
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        onboardingStep = defaults.integer(forKey: "onboardingStep")
    }

    var vocabulary: [String] { DictationPipeline.vocabulary(from: dictionaryText) }

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

    func makeTranscriber() -> Transcriber {
        switch engine {
        case .groq: return GroqTranscriber(apiKey: apiKey(.groq))
        case .deepgram: return DeepgramTranscriber(apiKey: apiKey(.deepgram))
        case .localWhisper: return LocalWhisperTranscriber(executablePath: whisperExecutablePath, modelPath: whisperModelPath)
        }
    }

    func makeCleaner() -> TranscriptCleaner? {
        let key = apiKey(.anthropic)
        guard cleanupEnabled, !key.isEmpty else { return nil }
        return TranscriptCleaner(apiKey: key)
    }
}
