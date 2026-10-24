import AppKit
import HushtypeCore
import SwiftUI

/// A standard macOS preferences window: toolbar tabs, one grouped form per tab.
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let controller: DictationController
    private let runSetup: () -> Void
    private var window: NSWindow?

    init(settings: SettingsStore, controller: DictationController, runSetup: @escaping () -> Void) {
        self.settings = settings
        self.controller = controller
        self.runSetup = runSetup
    }

    private var tabs: NSTabViewController?

    /// Opens the window, optionally on the tab with this label (e.g. "Claude").
    func show(tab: String? = nil) {
        if window == nil {
            let tabs = NSTabViewController()
            self.tabs = tabs
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(item("General", "gearshape",
                                     GeneralPane(settings: settings, controller: controller, runSetup: runSetup)))
            tabs.addTabViewItem(item("Claude", "sparkles", ClaudePane(settings: settings)))
            tabs.addTabViewItem(item("Dictionary", "character.book.closed", DictionaryPane(settings: settings)))
            tabs.addTabViewItem(item("Permissions", "lock.shield", PermissionsPane(controller: controller)))

            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let tab, let tabs, let index = tabs.tabViewItems.firstIndex(where: { $0.label == tab }) {
            tabs.selectedTabViewItemIndex = index
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func item<Content: View>(_ label: String, _ symbol: String, _ view: Content) -> NSTabViewItem {
        let host = NSHostingController(rootView: view.frame(width: 520))
        host.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    let runSetup: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private struct Language: Identifiable {
        let id: String
        let name: String
    }

    private let languages = [
        Language(id: "en", name: "English"), Language(id: "auto", name: "System language"),
        Language(id: "es", name: "Spanish"), Language(id: "fr", name: "French"),
        Language(id: "de", name: "German"), Language(id: "hi", name: "Hindi"),
        Language(id: "pt", name: "Portuguese"), Language(id: "ja", name: "Japanese"),
        Language(id: "zh", name: "Chinese"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Dictation key", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: settings.triggerKey) { controller.restartHotkey() }
                Picker("Language", selection: $settings.language) {
                    ForEach(languages) { Text($0.name).tag($0.id) }
                }
                .onChange(of: settings.language) { controller.prepareSpeechModel() }
            } header: {
                Text("Dictation")
            } footer: {
                if settings.triggerKey == .fn {
                    Text("Set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing” so macOS doesn't also react to Fn.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Hold the key to talk and let go to insert. Press any other key while holding to cancel.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("System") {
                Toggle("Open Hushtype at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LaunchAtLogin.set(launchAtLogin) }
                LabeledContent("Setup") {
                    Button("Run Setup Again…", action: runSetup)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

// MARK: - Claude

private struct ClaudePane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PolishCard(settings: settings)
            Text("Speech is transcribed on this Mac. Only the text is sent to Claude for polishing.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(height: 360)
    }
}

// MARK: - Dictionary

private struct DictionaryPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.dictionaryText)
                    .font(.body.monospaced())
                    .frame(height: 220)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Words to always get right")
            } footer: {
                Text("One name, product or term per line. \(settings.vocabulary.count) terms. Used when transcribing and polishing.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @ObservedObject var controller: DictationController
    @StateObject private var permissions = PermissionMonitor()

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    PermissionRow(permission: permission, granted: permissions.isGranted(permission))
                }
            } footer: {
                if permissions.isGranted(.inputMonitoring) && !controller.hotkeyActive {
                    HStack {
                        Text("Restart Hushtype to finish turning on the dictation key.")
                        Spacer()
                        Button("Restart") { Permissions.relaunch() }
                    }
                } else {
                    Text("Changes in System Settings show up here immediately.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 330)
        .onAppear { permissions.start() }
        .onDisappear { permissions.stop() }
        .onChange(of: permissions.granted) {
            if permissions.isGranted(.inputMonitoring) && !controller.hotkeyActive { controller.restartHotkey() }
        }
    }
}
