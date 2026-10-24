import AppKit
import SwiftUI

@main
struct HushtypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller,
                        openSettings: appDelegate.showSettings,
                        openSetup: appDelegate.showOnboarding)
        } label: {
            MenuBarIcon(controller: appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    lazy var controller = DictationController(settings: settings)
    private lazy var onboardingWindow = OnboardingWindowController(settings: settings, controller: controller)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, controller: controller) { [weak self] in
        self?.showOnboarding()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        // `open Hushtype.app --args -HushtypeOpenSettings Claude` jumps straight to a Settings tab.
        if let tab = UserDefaults.standard.string(forKey: "HushtypeOpenSettings") {
            settingsWindow.show(tab: tab)
        } else if !settings.hasCompletedOnboarding || !Permissions.allGranted {
            showOnboarding()
        }
    }

    func showSettings() {
        settingsWindow.show()
    }

    func showOnboarding() {
        onboardingWindow.show()
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Image(systemName: controller.phase.menuBarSymbol)
    }
}

private struct MenuContent: View {
    @ObservedObject var controller: DictationController
    let openSettings: @MainActor () -> Void
    let openSetup: @MainActor () -> Void

    var body: some View {
        Text(controller.statusLine)
        if !controller.hotkeyActive || !Permissions.allGranted {
            Button("Finish Setting Up Hushtype…") { openSetup() }
        }

        if let last = controller.history.first {
            Text("Last one took \(last.duration.seconds)")
        }

        if !controller.history.isEmpty {
            Divider()
            Text("Recent (click to copy)")
            ForEach(controller.history.prefix(5)) { item in
                Button(item.text.truncated(to: 48)) { controller.copyToClipboard(item.text) }
            }
        }

        Divider()
        Button("Settings…") { openSettings() }
            .keyboardShortcut(",")
        Button("Quit Hushtype") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension TimeInterval {
    /// "0.62 s"
    var seconds: String { String(format: "%.2f s", self) }
}

extension String {
    func truncated(to length: Int) -> String {
        count > length ? String(prefix(length - 1)) + "…" : self
    }
}
