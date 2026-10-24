import AppKit
import SwiftUI

@main
struct HushtypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller, openSettings: appDelegate.showSettings)
        } label: {
            MenuBarIcon(controller: appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    lazy var controller = DictationController(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, controller: controller)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        if !Permissions.allGranted || !settings.hasCompletedOnboarding {
            showSettings()
        }
    }

    func showSettings() {
        settingsWindow.show()
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

    var body: some View {
        Text(controller.statusLine)

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

extension String {
    func truncated(to length: Int) -> String {
        count > length ? String(prefix(length - 1)) + "…" : self
    }
}
