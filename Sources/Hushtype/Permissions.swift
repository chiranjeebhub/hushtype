import AppKit
import ApplicationServices
import AVFoundation

/// The three macOS permissions Hushtype needs.
enum Permissions {
    /// Microphone: record your voice.
    static var microphone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Input Monitoring: notice the push-to-talk key while other apps are focused.
    static var inputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    /// Accessibility: send ⌘V to the focused app to insert text.
    static var accessibility: Bool {
        AXIsProcessTrusted()
    }

    static var allGranted: Bool { microphone && inputMonitoring && accessibility }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func requestInputMonitoring() {
        if !CGRequestListenEventAccess() { openPrivacyPane("Privacy_ListenEvent") }
    }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { openPrivacyPane("Privacy_Accessibility") }
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
