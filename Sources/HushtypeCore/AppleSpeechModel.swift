import Foundation
import Speech

public struct TranscriptionOptions: Equatable, Sendable {
    /// ISO-639-1 code such as "en", or nil for the system language.
    public var language: String?
    /// Names and jargon from the personal dictionary, used to bias recognition.
    public var vocabulary: [String]

    public init(language: String? = "en", vocabulary: [String] = []) {
        self.language = language
        self.vocabulary = vocabulary
    }
}

/// The on-device speech model macOS downloads once per language.
public enum AppleSpeechModel {
    public enum Status: Equatable, Sendable {
        case unsupported
        case notInstalled
        case installed
    }

    /// The closest language the on-device transcriber supports, or nil when there is none.
    public static func locale(for language: String?) async -> Locale? {
        let requested = language.map { Locale(identifier: $0) } ?? Locale.current
        return await SpeechTranscriber.supportedLocale(equivalentTo: requested)
    }

    public static func status(language: String?) async -> Status {
        guard let locale = await locale(for: language) else { return .unsupported }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) } ? .installed : .notInstalled
    }

    /// Downloads the model for `language` if it isn't installed yet. `progress` gets 0...1.
    public static func install(language: String?, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard let locale = await locale(for: language) else {
            throw HushtypeError.speechUnavailable("On-device dictation doesn't support this language yet.")
        }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
            progress(1)
            return
        }
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { value, _ in
            progress(value.fractionCompleted)
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
        progress(1)
    }
}
