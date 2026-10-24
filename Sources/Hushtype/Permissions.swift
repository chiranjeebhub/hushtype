import AppKit
import ApplicationServices
import AVFoundation

/// The three macOS permissions Hushtype needs, and the smoothest way to ask for each.
enum Permission: String, CaseIterable, Identifiable {
    case microphone
    case inputMonitoring
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        }
    }

    var purpose: String {
        switch self {
        case .microphone: return "Hear you while you hold the dictation key. Nothing is kept or sent otherwise."
        case .inputMonitoring: return "Notice when you hold the dictation key, whichever app you're in."
        case .accessibility: return "Type the finished text into the app you're using."
        }
    }

    var symbol: String {
        switch self {
        case .microphone: return "mic.fill"
        case .inputMonitoring: return "keyboard.fill"
        case .accessibility: return "text.cursor"
        }
    }

    /// What the user does in System Settings, for the two permissions macOS won't grant from a dialog.
    var settingsHint: String? {
        switch self {
        case .microphone: return nil
        case .inputMonitoring, .accessibility:
            return "In System Settings, switch on Hushtype in the \(title) list. This window notices as soon as you do."
        }
    }

    var isGranted: Bool {
        switch self {
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .inputMonitoring: return CGPreflightListenEventAccess()
        case .accessibility: return AXIsProcessTrusted()
        }
    }

    /// Shows the system prompt the first time, and goes straight to the right System Settings pane after that,
    /// since macOS only ever prompts once.
    @MainActor
    func request() {
        switch self {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    // The prompt belongs to a system process, and a menu-bar app isn't made active again
                    // when it closes, so bring Hushtype's window back ourselves.
                    DispatchQueue.main.async { Permissions.bringWindowsForward() }
                }
            case .authorized:
                break
            default:
                openSettingsPane()
            }
        case .inputMonitoring:
            if promptedBefore {
                openSettingsPane()
            } else {
                markPrompted()
                if !CGRequestListenEventAccess() { openSettingsPane() }
            }
        case .accessibility:
            if promptedBefore {
                openSettingsPane()
            } else {
                markPrompted()
                // Prompting also adds Hushtype to the Accessibility list, so the user only flips a switch.
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
        }
    }

    func openSettingsPane() {
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private var promptedKey: String { "prompted.\(rawValue)" }
    private var promptedBefore: Bool { UserDefaults.standard.bool(forKey: promptedKey) }
    private func markPrompted() { UserDefaults.standard.set(true, forKey: promptedKey) }
}

enum Permissions {
    static var allGranted: Bool { Permission.allCases.allSatisfy(\.isGranted) }

    /// Makes Hushtype active and brings its open windows to the front. As a menu-bar app it has no Dock
    /// icon, so after a permission prompt or a trip to System Settings its window would stay buried.
    @MainActor
    static func bringWindowsForward() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Quits and reopens Hushtype. macOS only applies a new Input Monitoring grant to a fresh process.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Publishes permission changes while a setup screen is open, so checkmarks flip the moment the user
/// grants something in System Settings.
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published private(set) var granted: Set<Permission> = []
    private var timer: Timer?

    init() { refresh() }

    func start(every interval: TimeInterval = 0.5) {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let now = Set(Permission.allCases.filter(\.isGranted))
        if now != granted { granted = now }
    }

    func isGranted(_ permission: Permission) -> Bool { granted.contains(permission) }
}
