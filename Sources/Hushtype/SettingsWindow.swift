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
    static let paneSize = CGSize(width: 600, height: 500)

    private let settings: SettingsStore
    private let controller: DictationController
    private let updater: Updater
    private let runSetup: () -> Void
    private var window: NSWindow?

    init(settings: SettingsStore, controller: DictationController, updater: Updater, runSetup: @escaping () -> Void) {
        self.settings = settings
        self.controller = controller
        self.updater = updater
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
                                     GeneralPane(settings: settings, controller: controller, updater: updater, runSetup: runSetup)))
            tabs.addTabViewItem(item("Claude", "sparkles", ClaudePane(settings: settings, controller: controller)))
            tabs.addTabViewItem(item("Dictionary", "character.book.closed", DictionaryPane(settings: settings)))
            tabs.addTabViewItem(item("Snippets", "text.badge.plus", SnippetsPane(settings: settings)))
            tabs.addTabViewItem(item("History", "clock.arrow.circlepath",
                                     HistoryPane(settings: settings, controller: controller)))
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
        // NSTabViewController titles the window after the selected child's `title`, which a hosting
        // controller leaves nil ("Untitled"), sometimes after our own didSelect has run.
        host.title = label
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
    @ObservedObject var updater: Updater
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
                Toggle("Double-tap for hands-free dictation", isOn: $settings.handsFree)
                    .onChange(of: settings.handsFree) { controller.restartHotkey() }
                Picker("Language", selection: $settings.language) {
                    ForEach(languages) { Text($0.name).tag($0.id) }
                }
                .onChange(of: settings.language) { controller.prepareSpeechModel() }
                Toggle("Play a sound when listening starts and stops", isOn: $settings.soundsEnabled)
            } header: {
                Text("Dictation")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Footnote(settings.triggerKey == .fn
                             ? "Set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing” so macOS doesn't also react to Fn."
                             : "Hold the key to talk and let go to insert. Press any other key while holding to cancel.")
                    if settings.handsFree {
                        Footnote("Hands-free: double-tap the key and talk as long as you like. Tap it again to insert, or press Esc to cancel.")
                    }
                    Footnote("Command mode: select some text, hold the key, press Control too, and say what to do with it, like “make this shorter” or “translate to Hindi”. With nothing selected, Claude writes what you ask for at the cursor.")
                }
            }

            Section {
                Toggle("Always-ready microphone", isOn: $settings.alwaysReadyMic)
                    .onChange(of: settings.alwaysReadyMic) { controller.applyMicMode() }
            } header: {
                Text("Microphone")
            } footer: {
                Footnote(settings.alwaysReadyMic
                         ? "The mic stays open, so dictation starts the instant you press and catches a word you began a beat early. macOS shows its orange mic dot the whole time. Nothing is kept or sent until you press."
                         : "The mic stays open for 30 seconds after you dictate, so the next one starts instantly. Turn this on to keep it ready all the time.")
            }

            Section("System") {
                Toggle("Open Hushtype at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LaunchAtLogin.set(launchAtLogin) }
                LabeledContent("Setup") {
                    Button("Run Setup Again…", action: runSetup)
                }
            }

            Section {
                if updater.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                }
                LabeledContent("Version \(Updater.version)") {
                    if updater.isAvailable {
                        Button("Check Now") { updater.checkForUpdates() }
                    } else {
                        Text("Development build").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Claude

private struct ClaudePane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PolishCard(settings: settings)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.useContext) {
                            privacyRow("macwindow.and.cursorarrow", .indigo, "Match the app you're in",
                                       "Sends the app's name and the text around your cursor with the transcript, so Claude matches the tone (casual in Slack, careful in Mail) and spells names already on screen. Password fields are never read.")
                        }
                        .toggleStyle(.switch)
                        Divider()
                        privacyRow("lock.laptopcomputer", .teal, "Speech stays on this Mac",
                                   "Your voice is transcribed on-device by macOS. Audio is never uploaded.")
                        Divider()
                        privacyRow("text.bubble", .pink, "Only text goes to Claude",
                                   "The transcript is sent with your own key for polishing, then inserted.")
                    }
                }
                SpeedCard(controller: controller)
            }
            .padding(20)
        }
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

/// Release-to-paste time over recent dictations, so slow polishing is visible.
private struct SpeedCard: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: "bolt.fill", color: .orange, size: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speed").font(.callout.weight(.semibold))
                    if let stats = controller.latency, let last = controller.history.first(where: { $0.kind == .dictation }) {
                        Text("Typically \(stats.median.seconds) from letting go to text, \(stats.p90.seconds) or less 9 times in 10 (last \(stats.count)).")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(breakdown(last.timings))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text("Dictate a few times to see how fast text arrives.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func breakdown(_ t: DictationTimings) -> String {
        var parts = ["Last: transcribe \(t.transcribe.seconds)"]
        if let first = t.polishFirstToken, let polish = t.polish {
            parts.append("Claude first word \(first.seconds), done \(polish.seconds)")
        } else {
            parts.append("Claude skipped")
        }
        parts.append("total \(t.total.seconds)")
        return parts.joined(separator: " · ")
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

            Section {
                Toggle("Learn from my corrections", isOn: $settings.learnFromCorrections)
            } footer: {
                Footnote("When you fix the spelling of a name or term right after dictating it, Hushtype adds your spelling here. This happens on your Mac; nothing extra is sent.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Snippets

private struct SnippetsPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: Snippet.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Say a trigger phrase and Hushtype types the saved text instead, exactly as written. Works on its own (“my calendar link”) or inside a sentence (“book a time at my calendar link”).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(settings.snippets) { snippet in
                            Text(snippet.trigger.isEmpty ? "New snippet" : snippet.trigger)
                                .foregroundStyle(snippet.trigger.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .tag(snippet.id)
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: false))
                    HStack(spacing: 0) {
                        Button { add() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                        Button { remove() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                            .disabled(selection == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
                .frame(width: 170)

                if let index = settings.snippets.firstIndex(where: { $0.id == selection }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When I say").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("my calendar link", text: $settings.snippets[index].trigger)
                            .textFieldStyle(.roundedBorder)
                        Text("Type").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextEditor(text: $settings.snippets[index].expansion)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "text.badge.plus").font(.largeTitle).foregroundStyle(.tertiary)
                        Text(settings.snippets.isEmpty ? "Add your first snippet with +." : "Select a snippet to edit it.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(20)
    }

    private func add() {
        let snippet = Snippet(trigger: "", expansion: "")
        settings.snippets.append(snippet)
        selection = snippet.id
    }

    private func remove() {
        guard let selection else { return }
        settings.snippets.removeAll { $0.id == selection }
        self.selection = nil
    }
}

// MARK: - History

private struct HistoryPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    @State private var search = ""
    @State private var confirmClear = false

    private var items: [DictationResult] {
        guard !search.isEmpty else { return controller.history }
        return controller.history.filter {
            $0.text.localizedCaseInsensitiveContains(search) || ($0.appName ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                Button("Clear…") { confirmClear = true }.disabled(controller.history.isEmpty)
            }
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(controller.history.isEmpty ? "Your dictations show up here." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HistoryRow(item: item) { controller.copyToClipboard(item.text) }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }
            Toggle("Keep history after quitting", isOn: $settings.keepHistory)
                .onChange(of: settings.keepHistory) { controller.applyHistorySetting() }
            Text("Saved only on this Mac. Press ⌃⌘V anywhere to paste your last dictation again.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .confirmationDialog("Clear all dictation history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { controller.clearHistory() }
        }
    }
}

private struct HistoryRow: View {
    let item: DictationResult
    let copy: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind == .command ? "wand.and.stars" : "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text).lineLimit(3).textSelection(.enabled)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy") {
                copy()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private var caption: String {
        var parts = [item.date.formatted(.relative(presentation: .named))]
        if let app = item.appName { parts.append(app) }
        parts.append(item.duration.seconds)
        return parts.joined(separator: " · ")
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
