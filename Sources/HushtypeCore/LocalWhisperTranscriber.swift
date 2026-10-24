import Foundation

/// Runs whisper.cpp's `whisper-cli` on-device (install with `brew install whisper-cpp`).
/// Audio never leaves the Mac.
public struct LocalWhisperTranscriber: Transcriber {
    public let name = "whisper.cpp"
    let executablePath: String
    let modelPath: String

    public init(executablePath: String, modelPath: String) {
        self.executablePath = executablePath
        self.modelPath = modelPath
    }

    public func transcribe(wav: Data, options: TranscriptionOptions) async throws -> String {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: executablePath) else {
            throw HushtypeError.localEngine("whisper-cli not found at \(executablePath). Install it with `brew install whisper-cpp`.")
        }
        guard fm.fileExists(atPath: modelPath) else {
            throw HushtypeError.localEngine("Model file not found at \(modelPath).")
        }

        let audioURL = fm.temporaryDirectory.appendingPathComponent("hushtype-\(UUID().uuidString).wav")
        try wav.write(to: audioURL)
        defer { try? fm.removeItem(at: audioURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments(audioPath: audioURL.path, options: options)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: Self.parse(String(decoding: out, as: UTF8.self)))
                } else {
                    let message = String(decoding: err, as: UTF8.self).suffix(300)
                    continuation.resume(throwing: HushtypeError.localEngine("exit \(proc.terminationStatus): \(message)"))
                }
            }
            do { try process.run() } catch {
                continuation.resume(throwing: HushtypeError.localEngine(error.localizedDescription))
            }
        }
    }

    func arguments(audioPath: String, options: TranscriptionOptions) -> [String] {
        var args = ["-m", modelPath, "-f", audioPath, "-nt", "-np", "-l", options.language ?? "auto"]
        if !options.vocabulary.isEmpty {
            args += ["--prompt", options.vocabulary.joined(separator: ", ")]
        }
        return args
    }

    /// whisper-cli prints one segment per line; join them into a single passage.
    static func parse(_ output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
