import AppKit

/// Short, quiet cues for when Hushtype starts and stops listening.
@MainActor
enum Chime {
    // Preloaded so the cue plays the instant it's needed.
    private static let start = sound("Tink", volume: 0.35)
    private static let stop = sound("Pop", volume: 0.3)

    /// Played once the microphone is actually capturing, so it never signals "ready" too early.
    static func playStart() { start?.stop(); start?.play() }

    /// Played after the microphone is closed, so the cue never ends up in the recording.
    static func playStop() { stop?.stop(); stop?.play() }

    private static func sound(_ name: String, volume: Float) -> NSSound? {
        let sound = NSSound(named: NSSound.Name(name))
        sound?.volume = volume
        return sound
    }
}
