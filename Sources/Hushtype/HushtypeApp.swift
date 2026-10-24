import AppKit
import Combine
import SwiftUI

@main
struct HushtypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller,
                        permissions: appDelegate.permissions,
                        openSettings: appDelegate.showSettings,
                        openSetup: appDelegate.showOnboarding,
                        openHistory: appDelegate.showHistory,
                        updater: appDelegate.updater)
        } label: {
            MenuBarIcon(controller: appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let updater = Updater()
    lazy var controller = DictationController(settings: settings)
    /// Live permission state for the menu, so "Finish Setting Up" disappears once everything is
    /// granted instead of reflecting whatever was true when the menu last redrew.
    let permissions = PermissionMonitor()
    private var permissionWatch: AnyCancellable?
    private lazy var cloudSync = CloudSync(settings: settings, controller: controller)
    private lazy var onboardingWindow = OnboardingWindowController(settings: settings, controller: controller)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, controller: controller,
                                                                updater: updater) { [weak self] in
        self?.showOnboarding()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = cloudSync
        controller.start()
        permissions.start(every: 2)
        // Once Input Monitoring is granted, try the dictation key again without waiting for Settings.
        permissionWatch = permissions.$granted.sink { [weak self] granted in
            MainActor.assumeIsolated {
                guard let self, granted.contains(.inputMonitoring), !self.controller.hotkeyActive else { return }
                self.controller.restartHotkey()
            }
        }
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

    func showHistory() {
        settingsWindow.show(tab: "History")
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
    @ObservedObject var permissions: PermissionMonitor
    let openSettings: @MainActor () -> Void
    let openSetup: @MainActor () -> Void
    let openHistory: @MainActor () -> Void
    let updater: Updater

    var body: some View {
        Text(controller.statusLine)
        if permissions.granted.count < Permission.allCases.count {
            Button("Finish Setting Up Hushtype…", systemImage: "checklist") { openSetup() }
        } else if !controller.hotkeyActive {
            // Everything is granted, but macOS only applies Input Monitoring to a fresh process.
            Button("Restart to Turn On the Dictation Key", systemImage: "arrow.clockwise") { Permissions.relaunch() }
        }

        if let last = controller.history.first {
            Text("Last one took \(last.duration.seconds)")
        }

        if !controller.history.isEmpty {
            Divider()
            Button("Paste Last Dictation", systemImage: "doc.on.clipboard") { controller.pasteLast(delay: 0.2) }
                .keyboardShortcut("v", modifiers: [.control, .command])
            Menu("Recent", systemImage: "clock.arrow.circlepath") {
                Text("Click to copy")
                ForEach(controller.history.prefix(10)) { item in
                    Button(item.text.truncated(to: 60)) { controller.copyToClipboard(item.text) }
                }
                Divider()
                Button("Show All…", systemImage: "list.bullet") { openHistory() }
            }
        }

        Divider()
        Button("Settings…", systemImage: "gearshape") { openSettings() }
            .keyboardShortcut(",")
        if updater.isAvailable {
            Button("Check for Updates…", systemImage: "arrow.down.circle") { updater.checkForUpdates() }
        }
        Button("Quit Hushtype", systemImage: "power") { NSApp.terminate(nil) }
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
