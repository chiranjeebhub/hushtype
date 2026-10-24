import AppKit
import HushtypeCore
import SwiftUI

/// Toolbar tabs that title the window after the selected tab, like System Settings, and keep any
/// text field from grabbing focus when a tab opens.
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? "Hushtype Settings"
        DispatchQueue.main.async { [weak self] in self?.view.window?.makeFirstResponder(nil) }
    }
}

/// A standard macOS preferences window: toolbar tabs, one grouped form per tab, all the same size.
@MainActor
final class SettingsWindowController {
    /// Every pane uses this size so the window doesn't jump when switching tabs.
    static let paneSize = CGSize(width: 520, height: 400)

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
            let tabs = SettingsTabViewController()
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
            window.title = tabs.tabViewItems.first?.label ?? "Hushtype Settings"
            window.center()
            self.window = window
        }
        if let tab, let tabs, let index = tabs.tabViewItems.firstIndex(where: { $0.label == tab }) {
            tabs.selectedTabViewItemIndex = index
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }

    private func item<Content: View>(_ label: String, _ symbol: String, _ view: Content) -> NSTabViewItem {
        let host = NSHostingController(rootView: view.frame(width: Self.paneSize.width, height: Self.paneSize.height))
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
                Toggle("Play a sound when listening starts and stops", isOn: $settings.soundsEnabled)
            } header: {
                Text("Dictation")
            } footer: {
                Footnote(settings.triggerKey == .fn
                         ? "Set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing” so macOS doesn't also react to Fn."
                         : "Hold the key to talk and let go to insert. Press any other key while holding to cancel.")
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
    }
}

// MARK: - Claude

private struct ClaudePane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PolishCard(settings: settings)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    privacyRow("lock.laptopcomputer", .teal, "Speech stays on this Mac",
                               "Your voice is transcribed on-device by macOS. Audio is never uploaded.")
                    Divider()
                    privacyRow("text.bubble", .pink, "Only text goes to Claude",
                               "The transcript is sent with your own key for polishing, then inserted.")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func privacyRow(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
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
                    .frame(height: 200)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Words to always get right")
            } footer: {
                Footnote("One name, product or term per line. \(settings.vocabulary.count) terms. Used when transcribing and polishing.")
            }
        }
        .formStyle(.grouped)
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
                    Footnote("Changes in System Settings show up here immediately.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.start() }
        .onDisappear { permissions.stop() }
        .onChange(of: permissions.granted) {
            if permissions.isGranted(.inputMonitoring) && !controller.hotkeyActive { controller.restartHotkey() }
        }
    }
}

/// Section footer text, left-aligned to line up with the rows above it.
private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
