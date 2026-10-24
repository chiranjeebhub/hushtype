import AppKit
import AVFoundation
import Combine
import HushtypeCore
import SwiftUI

/// The Settings window's sections, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case home, dictation, claude, dictionary, snippets, history, permissions, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictation: return "Dictation"
        case .claude: return "Claude Polish"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .history: return "History"
        case .permissions: return "Permissions"
        case .general: return "General"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "Whether Hushtype is ready, and what you've dictated lately."
        case .dictation: return "Choose the key you hold to talk, and how Hushtype listens."
        case .claude: return "Claude cleans up what you said before it's typed. Only text leaves your Mac."
        case .dictionary: return "Names and terms Hushtype should always spell your way."
        case .snippets: return "Say a phrase, and Hushtype types your saved text exactly as written."
        case .history: return "Your recent dictations, saved only on this Mac."
        case .permissions: return "Hushtype needs these to hear you and type for you."
        case .general: return "Startup, setup and updates."
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .dictation: return "keyboard"
        case .claude: return "sparkles"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .history: return "clock.arrow.circlepath"
        case .permissions: return "lock.shield"
        case .general: return "gearshape"
        }
    }

    /// The sidebar heading this pane sits under.
    var group: String? {
        switch self {
        case .home, .dictation, .claude: return nil
        case .dictionary, .snippets, .history: return "Library"
        case .permissions, .general: return "App"
        }
    }

    /// Words the sidebar search matches besides the title.
    var keywords: [String] {
        switch self {
        case .home: return ["status", "ready", "overview", "recent"]
        case .dictation: return ["key", "hotkey", "fn", "option", "hands-free", "language", "sound", "microphone", "mic", "shortcut", "command"]
        case .claude: return ["polish", "api key", "anthropic", "context", "app", "privacy", "speed", "latency"]
        case .dictionary: return ["words", "vocabulary", "names", "spelling", "learn", "corrections"]
        case .snippets: return ["shortcut", "expand", "text", "phrase"]
        case .history: return ["recent", "copy", "paste last", "search"]
        case .permissions: return ["accessibility", "input monitoring", "microphone", "privacy"]
        case .general: return ["login", "startup", "setup", "updates", "version"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || keywords.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Finds a pane by the names menus and `-HushtypeOpenSettings` use ("Claude", "History").
    static func named(_ name: String) -> SettingsPane? {
        allCases.first {
            $0.rawValue.caseInsensitiveCompare(name) == .orderedSame
                || $0.title.caseInsensitiveCompare(name) == .orderedSame
                || $0.title.split(separator: " ").first?.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .home
}

/// The Settings window: a glass sidebar beside one pane at a time, like System Settings.
@MainActor
final class SettingsWindowController {
    static let defaultSize = CGSize(width: 880, height: 640)
    static let minimumSize = CGSize(width: 780, height: 520)

    private let settings: SettingsStore
    private let controller: DictationController
    private let updater: Updater
    private let runSetup: () -> Void
    private let navigation = SettingsNavigation()
    private var window: NSWindow?
    private var titleSubscription: AnyCancellable?

    init(settings: SettingsStore, controller: DictationController, updater: Updater, runSetup: @escaping () -> Void) {
        self.settings = settings
        self.controller = controller
        self.updater = updater
        self.runSetup = runSetup
    }

    /// Opens the window, optionally on the pane with this name (e.g. "Claude" or "History").
    func show(tab: String? = nil) {
        if window == nil {
            let root = SettingsRoot(navigation: navigation, settings: settings, controller: controller,
                                    updater: updater, runSetup: runSetup)
            let host = NSHostingController(rootView: root)
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.setContentSize(Self.defaultSize)
            window.contentMinSize = Self.minimumSize
            window.setFrameAutosaveName("HushtypeSettings")
            if !window.setFrameUsingName("HushtypeSettings") { window.center() }
            // The title is hidden but still names the window in the Window menu and Mission Control.
            titleSubscription = navigation.$pane.sink { [weak window] in window?.title = $0.title }
            self.window = window
        }
        if let tab, let pane = SettingsPane.named(tab) {
            navigation.pane = pane
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }
}

// MARK: - Window layout

private struct SettingsRoot: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    @ObservedObject var updater: Updater
    let runSetup: () -> Void
    @StateObject private var permissions = PermissionMonitor()

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $navigation.pane, settings: settings, controller: controller,
                            permissions: permissions)
                .frame(width: 228)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                .padding(8)
            detail
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(navigation.pane)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.15), value: navigation.pane)
        .ignoresSafeArea()
        .background(Color.settingsBackground.ignoresSafeArea())
        .tint(.hushViolet)
        .onAppear { permissions.start() }
        .onDisappear { permissions.stop() }
        .onChange(of: permissions.granted) {
            if permissions.isGranted(.inputMonitoring) && !controller.hotkeyActive { controller.restartHotkey() }
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.pane {
        case .home: HomePane(settings: settings, controller: controller, permissions: permissions) { navigation.pane = $0 }
        case .dictation: DictationPane(settings: settings, controller: controller)
        case .claude: ClaudePane(settings: settings, controller: controller)
        case .dictionary: DictionaryPane(settings: settings)
        case .snippets: SnippetsPane(settings: settings)
        case .history: HistoryPane(settings: settings, controller: controller)
        case .permissions: PermissionsPane(controller: controller, permissions: permissions)
        case .general: GeneralPane(updater: updater, runSetup: runSetup)
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    @ObservedObject var permissions: PermissionMonitor
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var results: [SettingsPane] { SettingsPane.allCases.filter { $0.matches(search) } }
    private var allGranted: Bool { Permission.allCases.allSatisfy(permissions.isGranted) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .shadow(color: Color.hushViolet.opacity(0.35), radius: 5, y: 2)
                Text("Hushtype").font(.system(size: 15, weight: .semibold)).tracking(-0.2)
            }
            .padding(.horizontal, 6)
            searchField
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.element) { index, pane in
                    if let group = pane.group, index == 0 || results[index - 1].group != group {
                        Text(group.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                    }
                    row(pane)
                }
                if results.isEmpty {
                    Text("No settings match “\(search)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(9)
                }
            }
            Spacer(minLength: 0)
            StatusCard(settings: settings, controller: controller, allGranted: allGranted) {
                selection = .permissions
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 36)
        .padding(.bottom, 10)
        .background {
            // ⌘F jumps to search, as in System Settings.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.tertiary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { if let first = results.first { selection = first } }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            } else {
                Text("⌘F").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func row(_ pane: SettingsPane) -> some View {
        let selected = selection == pane
        return Button { selection = pane } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.hushViolet : Color.secondary)
                    .frame(width: 20)
                Text(pane.title)
                Spacer(minLength: 4)
                badge(pane)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.09))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func badge(_ pane: SettingsPane) -> some View {
        switch pane {
        case .dictionary: count(settings.vocabulary.count)
        case .snippets: count(settings.snippets.count)
        case .history: count(controller.history.count)
        case .permissions:
            Circle()
                .fill(allGranted ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .shadow(color: (allGranted ? Color.green : Color.orange).opacity(0.6), radius: 4)
        default: EmptyView()
        }
    }

    @ViewBuilder private func count(_ value: Int) -> some View {
        if value > 0 {
            Text("\(value)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
        }
    }
}

/// Whether Hushtype is ready, and the key to hold, at the foot of the sidebar.
private struct StatusCard: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    let allGranted: Bool
    let showPermissions: () -> Void

    private var state: (title: String, color: Color) {
        if !allGranted { return ("Needs permission", .orange) }
        if !controller.hotkeyActive { return ("Restart to finish setup", .orange) }
        switch controller.phase {
        case .recording: return ("Listening…", .hushViolet)
        case .transcribing, .cleaning: return ("Working…", .hushViolet)
        default: return ("Ready", .hushMint)
        }
    }

    var body: some View {
        Button { if !allGranted { showPermissions() } } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title).font(.callout.weight(.semibold))
                    Text("Hold \(settings.triggerKey.shortName) to talk").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state.color)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state.color != .orange)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color.hushViolet.opacity(0.16), Color.hushMint.opacity(0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: state.title)
    }
}

// MARK: - Home

private struct HomePane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    @ObservedObject var permissions: PermissionMonitor
    let open: (SettingsPane) -> Void

    private var today: [DictationResult] {
        controller.history.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var wordsToday: Int {
        today.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    private var ready: Bool { Permission.allCases.allSatisfy(permissions.isGranted) && controller.hotkeyActive }

    var body: some View {
        SettingsPage(pane: .home, showsHeader: false) {
            hero
            HStack(spacing: 10) {
                stat("\(today.count)", unit: nil, "Dictations today")
                if let stats = controller.latency {
                    stat(String(format: "%.1f", stats.median), unit: "s", "Typical wait for text")
                } else {
                    stat("–", unit: nil, "Typical wait for text")
                }
                stat("\(wordsToday.formatted())", unit: nil, "Words today")
            }
            .padding(.top, 12)

            SectionLabel("Recent")
            if controller.history.isEmpty {
                HStack(spacing: 12) {
                    Glyph(symbol: "waveform")
                    Text("Hold \(settings.triggerKey.shortName) in any app and start talking. Your dictations show up here.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            } else {
                SettingsCard {
                    ForEach(controller.history.prefix(3)) { item in
                        HistoryRow(item: item) { controller.copyToClipboard(item.text) }
                    }
                }
                Button("See all history ›") { open(.history) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.hushViolet)
                    .padding(.top, 10)
                    .padding(.leading, 2)
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 68, height: 68)
                .shadow(color: Color.hushViolet.opacity(0.45), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(ready ? "Hold \(settings.triggerKey.shortName) to talk" : "Almost ready")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)
                Text(ready
                     ? "Let go and your words appear wherever you're typing\(settings.cleanupEnabled ? ", polished by Claude" : "")."
                     : "Hushtype still needs a permission before the dictation key works.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if ready {
                        pill { Circle().fill(Color.green).frame(width: 6, height: 6) } label: { Text("Ready") }
                    } else {
                        Button("Open Permissions") { open(.permissions) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    if let microphone = AVCaptureDevice.default(for: .audio)?.localizedName {
                        pill { Image(systemName: "mic") } label: { Text(microphone) }
                    }
                    pill { Image(systemName: "sparkles") } label: { Text(settings.cleanupEnabled ? "Polish on" : "Polish off") }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Color.hushViolet.opacity(0.20), Color.hushMint.opacity(0.08), Color.primary.opacity(0.02)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    private func pill<Icon: View, Content: View>(@ViewBuilder icon: () -> Icon, @ViewBuilder label: () -> Content) -> some View {
        HStack(spacing: 6) {
            icon().font(.system(size: 10))
            label()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.15)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private func stat(_ value: String, unit: String?, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                if let unit { Text(unit).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary) }
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - Dictation

private struct DictationPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController

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
        SettingsPage(pane: .dictation) {
            SectionLabel("Dictation key")
            HStack(spacing: 12) {
                ForEach(TriggerKey.allCases) { key in
                    KeyChoiceTile(key: key, selected: settings.triggerKey == key) { settings.triggerKey = key }
                }
            }
            if settings.triggerKey == .fn {
                Callout(symbol: "exclamationmark.triangle.fill", tint: .yellow, title: "macOS also listens to the Globe key",
                        message: "Set “Press 🌐 key to” to “Do Nothing” so the emoji picker stays out of the way.") {
                    Button("Open Keyboard Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            KeyTester(controller: controller, key: settings.triggerKey)
                .padding(.top, 12)

            SectionLabel("Shortcuts")
            ShortcutsCard(key: settings.triggerKey, handsFree: settings.handsFree)

            SectionLabel("Listening")
            SettingsCard {
                ToggleRow(title: "Hands-free dictation",
                          subtitle: "Double-tap the key to keep listening without holding it. Esc cancels.",
                          symbol: "hand.raised", isOn: $settings.handsFree)
                SettingsRow(title: "Language", symbol: "globe") {
                    Picker("Language", selection: $settings.language) {
                        ForEach(languages) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                ToggleRow(title: "Sounds", subtitle: "A soft chime when listening starts and stops.",
                          symbol: "speaker.wave.2", isOn: $settings.soundsEnabled)
                ToggleRow(title: "Always-ready microphone",
                          subtitle: settings.alwaysReadyMic
                              ? "On: dictation starts instantly. macOS shows its orange mic dot the whole time."
                              : "Off: the mic stays warm for 30 seconds after each dictation.",
                          symbol: "mic",
                          info: "The mic stays open, so dictation starts the instant you press and catches a word you began a beat early. Nothing is kept or sent until you press the key.",
                          isOn: $settings.alwaysReadyMic)
            }
        }
        .animation(.easeOut(duration: 0.2), value: settings.triggerKey)
        .onChange(of: settings.triggerKey) { controller.restartHotkey() }
        .onChange(of: settings.handsFree) { controller.restartHotkey() }
        .onChange(of: settings.language) { controller.prepareSpeechModel() }
        .onChange(of: settings.alwaysReadyMic) { controller.applyMicMode() }
    }
}

/// A strip that comes alive while Hushtype hears you, so the chosen key can be tried on the spot.
private struct KeyTester: View {
    @ObservedObject var controller: DictationController
    let key: TriggerKey

    private static let shape: [CGFloat] = [0.45, 0.7, 1, 0.8, 0.55, 0.9, 0.65, 0.5, 0.75]
    private var listening: Bool { controller.phase == .recording }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2.5) {
                ForEach(Self.shape.indices, id: \.self) { index in
                    Capsule()
                        .fill(listening ? AnyShapeStyle(LinearGradient.hushBrand) : AnyShapeStyle(Color.primary.opacity(0.25)))
                        .frame(width: 4, height: barHeight(index))
                }
            }
            .frame(width: 58, height: 18)
            .animation(.easeOut(duration: 0.08), value: controller.level)
            Group {
                if listening {
                    Text("Hushtype hears you. Let go to insert.")
                } else if !controller.hotkeyActive {
                    Text("The key turns on once Input Monitoring is allowed.")
                } else {
                    Text("Hold **\(key.shortName)** to test it. The bars move when Hushtype hears you.")
                }
            }
            .font(.caption)
            .foregroundStyle(listening ? .primary : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard listening else { return 3 }
        let level = CGFloat(min(max(controller.level, 0), 1))
        return max(3, 18 * Self.shape[index] * (0.25 + 0.75 * level))
    }
}

/// The gestures Hushtype understands, drawn as keycaps instead of written out.
private struct ShortcutsCard: View {
    let key: TriggerKey
    let handsFree: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                item(keys: [KeyChip(label: "Hold \(key.keyGlyph)")], title: "Dictate", detail: "Let go to insert")
                if handsFree {
                    item(keys: [KeyChip(label: key.keyGlyph), KeyChip(label: key.keyGlyph)], title: "Hands-free",
                         detail: "Double-tap, tap again to insert")
                } else {
                    item(keys: [KeyChip(label: "esc")], title: "Cancel", detail: "While you're talking")
                }
            }
            Divider().opacity(0.6).padding(.horizontal, 16)
            HStack(spacing: 0) {
                item(keys: [KeyChip(label: key.keyGlyph), KeyChip(label: "⌃")], title: "Command mode",
                     detail: "Select text, then say “make this shorter”")
                item(keys: [KeyChip(label: "⌃"), KeyChip(label: "⌘"), KeyChip(label: "V")], title: "Paste last",
                     detail: "Anywhere, any time")
            }
        }
        .cardSurface()
    }

    private func item(keys: [KeyChip], title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) { ForEach(keys.indices, id: \.self) { keys[$0] } }
                .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Claude

private struct ClaudePane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController

    var body: some View {
        SettingsPage(pane: .claude) {
            PolishHero(settings: settings)

            SectionLabel("Connection")
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Glyph(symbol: "key")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anthropic API key").fontWeight(.medium)
                            Text("Saved in your Keychain. Command mode uses it too.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    APIKeyField(service: .anthropic, settings: settings)
                }
                .padding(16)
                ToggleRow(title: "Match the app you're in",
                          subtitle: "Casual in Slack, careful in Mail. Spells names already on screen.",
                          symbol: "macwindow",
                          info: "Sends the app's name and the text around your cursor with the transcript, so Claude matches the tone and spells names already on screen. Password fields are never read.",
                          isOn: $settings.useContext)
            }
            HStack(spacing: 10) {
                trust("lock", "Voice stays here", "Speech is transcribed on this Mac. Audio is never uploaded.")
                trust("icloud", "Only text is sent", "Straight to Anthropic, with your own key.")
                trust("lock.shield", "Passwords skipped", "Secure fields are never read for context.")
            }
            .padding(.top, 10)

            SectionLabel(title: "Speed") {
                if let stats = controller.latency { Text("Last \(stats.count)") }
            }
            SpeedCard(controller: controller)
        }
    }

    private func trust(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Color.hushViolet)
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }
}

/// The polish switch, with a before/after that shows what it does.
private struct PolishHero: View {
    @ObservedObject var settings: SettingsStore

    private let said = "um so let's meet at 5, no wait, 6 pm tomorrow"
    private let typed = "Let's meet at 6 pm tomorrow."

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Glyph(symbol: "sparkles", brand: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Polish with Claude").fontWeight(.semibold)
                    Text("Removes filler words, fixes punctuation, applies your corrections.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle("Polish with Claude", isOn: $settings.cleanupEnabled.animation(.easeInOut(duration: 0.2)))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            HStack(alignment: .center, spacing: 10) {
                example("You say", said, lit: false)
                Image(systemName: "arrow.right").foregroundStyle(Color.hushViolet)
                example("Hushtype types", settings.cleanupEnabled ? typed : said, lit: settings.cleanupEnabled)
            }
        }
        .padding(16)
        .background(shape.fill(Color.primary.opacity(0.04)))
        .overlay(shape.strokeBorder(
            settings.cleanupEnabled
                ? AnyShapeStyle(LinearGradient(colors: [.hushViolet.opacity(0.8), .hushMint.opacity(0.5), .primary.opacity(0.08)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(Color.primary.opacity(0.08)),
            lineWidth: settings.cleanupEnabled ? 1 : 0.5))
    }

    private func example(_ label: String, _ text: String, lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(lit ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(lit ? Color.hushViolet.opacity(0.08) : Color.black.opacity(0.12)))
        .overlay(shape.strokeBorder(lit ? Color.hushViolet.opacity(0.35) : .clear, lineWidth: 0.5))
    }
}

/// Release-to-text time over recent dictations, and where the last one spent it.
private struct SpeedCard: View {
    @ObservedObject var controller: DictationController

    private struct Segment: Identifiable {
        let id: String
        let seconds: TimeInterval
        let color: Color
    }

    var body: some View {
        Group {
            if let stats = controller.latency, let last = controller.history.first(where: { $0.kind == .dictation }) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 28) {
                        number(stats.median, "Typical, from letting go to text", primary: true)
                        number(stats.p90, "Or faster, 9 times in 10", primary: false)
                    }
                    let parts = segments(last.timings)
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(parts) { segment in
                                Rectangle()
                                    .fill(segment.color)
                                    .frame(width: max(3, geo.size.width * segment.seconds / max(last.timings.total, 0.01) - 2))
                            }
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())
                    .padding(.top, 16)
                    .padding(.bottom, 9)
                    HStack(spacing: 16) {
                        ForEach(parts) { segment in
                            HStack(spacing: 6) {
                                Circle().fill(segment.color).frame(width: 7, height: 7)
                                Text("\(segment.id) \(segment.seconds.seconds)")
                            }
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Glyph(symbol: "bolt")
                    Text("Dictate a few times to see how fast text arrives.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func number(_ value: TimeInterval, _ caption: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%.1f", value)).font(.system(size: 30, weight: .semibold)).monospacedDigit()
                Text("s").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
            }
            .foregroundStyle(primary ? .primary : .secondary)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func segments(_ t: DictationTimings) -> [Segment] {
        var parts = [Segment(id: "Transcribe", seconds: t.transcribe, color: .blue)]
        if let first = t.polishFirstToken, let polish = t.polish {
            parts.append(Segment(id: "Claude's first word", seconds: first, color: .hushViolet))
            parts.append(Segment(id: "Claude done", seconds: max(0, polish - first), color: .hushMint))
        }
        return parts
    }
}

// MARK: - Dictionary

private struct DictionaryPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var newTerm = ""
    @State private var editingAsText = false

    var body: some View {
        SettingsPage(pane: .dictionary) {
            SettingsCard {
                HStack(spacing: 8) {
                    TextField("Add a name, product or term", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)
                Group {
                    if editingAsText {
                        TextEditor(text: $settings.dictionaryText)
                            .font(.body.monospaced())
                            .scrollContentBackground(.hidden)
                            .frame(height: 220)
                    } else if settings.vocabulary.isEmpty {
                        Text("Nothing here yet. Add names you use often, or fix a spelling right after dictating and Hushtype learns it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(settings.vocabulary, id: \.self) { TermChip(term: $0) { remove($0) } }
                        }
                    }
                }
                .padding(16)
            }
            HStack {
                Text("\(settings.vocabulary.count) terms · Used when transcribing and polishing.")
                Spacer()
                Button(editingAsText ? "Show as Tags" : "Edit as Text") { editingAsText.toggle() }
                    .buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .padding(.top, 8)

            SectionLabel("Learning")
            SettingsCard {
                ToggleRow(title: "Learn from my corrections",
                          subtitle: "Fix a name right after dictating it and Hushtype adds your spelling. This happens on your Mac.",
                          symbol: "wand.and.stars", isOn: $settings.learnFromCorrections)
            }
        }
    }

    private func add() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        settings.addToDictionary([term])
        newTerm = ""
    }

    private func remove(_ term: String) {
        settings.dictionaryText = settings.vocabulary.filter { $0 != term }.joined(separator: "\n")
    }
}

private struct TermChip: View {
    let term: String
    let remove: (String) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(term).font(.callout)
            if hovering {
                Button { remove(term) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove \(term)")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .onHover { hovering = $0 }
    }
}

// MARK: - Snippets

private struct SnippetsPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: Snippet.ID?

    var body: some View {
        SettingsPage(pane: .snippets) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(settings.snippets) { snippet in
                                snippetRow(snippet)
                            }
                        }
                        .padding(6)
                    }
                    Divider().opacity(0.6)
                    HStack(spacing: 2) {
                        Button { add() } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
                        Button { remove() } label: { Image(systemName: "minus").frame(width: 22, height: 20) }
                            .disabled(selection == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                }
                .frame(width: 210)
                .cardSurface()

                Group {
                    if let index = settings.snippets.firstIndex(where: { $0.id == selection }) {
                        VStack(alignment: .leading, spacing: 7) {
                            fieldLabel("When I say")
                            TextField("my calendar link", text: $settings.snippets[index].trigger)
                                .textFieldStyle(.roundedBorder)
                            fieldLabel("Type exactly").padding(.top, 6)
                            TextEditor(text: $settings.snippets[index].expansion)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                            Text("Works on its own or mid-sentence: “book a time at my calendar link”.")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        }
                        .padding(16)
                    } else {
                        VStack(spacing: 10) {
                            Glyph(symbol: "text.badge.plus")
                            Text(settings.snippets.isEmpty ? "Add your first snippet with +." : "Select a snippet to edit it.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .cardSurface()
            }
            .frame(height: 380)
        }
        .onAppear { if selection == nil { selection = settings.snippets.first?.id } }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        let selected = selection == snippet.id
        return Button { selection = snippet.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.trigger.isEmpty ? "New snippet" : "“\(snippet.trigger)”")
                    .foregroundStyle(snippet.trigger.isEmpty ? .secondary : .primary)
                if !snippet.expansion.isEmpty {
                    Text(snippet.expansion.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.hushViolet.opacity(0.16))
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hushViolet.opacity(0.35), lineWidth: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }

    private func add() {
        let snippet = Snippet(trigger: "", expansion: "")
        settings.snippets.append(snippet)
        selection = snippet.id
    }

    private func remove() {
        guard let selection else { return }
        settings.snippets.removeAll { $0.id == selection }
        self.selection = settings.snippets.first?.id
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

    /// History split into Today, Yesterday and older dates, newest first.
    private var days: [(title: String, items: [DictationResult])] {
        let calendar = Calendar.current
        var groups: [(title: String, items: [DictationResult])] = []
        for item in items {
            let title: String
            if calendar.isDateInToday(item.date) {
                title = "Today"
            } else if calendar.isDateInYesterday(item.date) {
                title = "Yesterday"
            } else {
                title = item.date.formatted(.dateTime.weekday(.wide).month().day())
            }
            if groups.last?.title == title {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((title, [item]))
            }
        }
        return groups
    }

    var body: some View {
        SettingsPage(pane: .history) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.tertiary)
                    TextField("Search dictations", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                Button("Clear…") { confirmClear = true }.disabled(controller.history.isEmpty)
            }

            if items.isEmpty {
                VStack(spacing: 10) {
                    Glyph(symbol: "clock")
                    Text(controller.history.isEmpty ? "Your dictations show up here." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                ForEach(days, id: \.title) { day in
                    SectionLabel(day.title)
                    SettingsCard {
                        ForEach(day.items) { item in
                            HistoryRow(item: item) { controller.copyToClipboard(item.text) }
                        }
                    }
                }
            }

            SectionLabel("Keep")
            SettingsCard {
                ToggleRow(title: "Keep history after quitting",
                          subtitle: "Saved only on this Mac. Press ⌃⌘V anywhere to paste your last dictation.",
                          symbol: "externaldrive", isOn: $settings.keepHistory)
            }
        }
        .onChange(of: settings.keepHistory) { controller.applyHistorySetting() }
        .confirmationDialog("Clear all dictation history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { controller.clearHistory() }
        }
    }
}

private struct HistoryRow: View {
    let item: DictationResult
    let copy: () -> Void
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            appBadge
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text).lineLimit(3).textSelection(.enabled)
                Text(caption).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy") {
                copy()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            .controlSize(.small)
            .opacity(hovering || copied ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    /// The app's initial on a colour picked from its name, or a wand for commands.
    private var appBadge: some View {
        let palette: [Color] = [.purple, .blue, .teal, .orange, .pink, .indigo, .green]
        let name = item.appName ?? ""
        let color = name.isEmpty ? Color.gray : palette[abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count]
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.gradient)
            if item.kind == .command {
                Image(systemName: "wand.and.stars").font(.system(size: 12, weight: .semibold))
            } else if let first = name.first {
                Text(String(first)).font(.system(size: 12, weight: .semibold))
            } else {
                Image(systemName: "waveform").font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
    }

    private var caption: String {
        var parts: [String] = []
        if let app = item.appName { parts.append(app) }
        parts.append(item.date.formatted(.relative(presentation: .named)))
        parts.append(item.kind == .command ? "command" : "\(item.timings.total.seconds) to text")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var permissions: PermissionMonitor

    private var missing: Int { Permission.allCases.filter { !permissions.isGranted($0) }.count }

    var body: some View {
        SettingsPage(pane: .permissions) {
            SettingsCard {
                ForEach(Permission.allCases) { permission in
                    SettingsRow(title: permission.title, subtitle: permission.purpose, symbol: permission.symbol) {
                        if permissions.isGranted(permission) {
                            StatusPill(text: "Allowed")
                        } else {
                            Button("Allow") { permission.request() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                if permissions.isGranted(.inputMonitoring) && !controller.hotkeyActive {
                    Text("Restart Hushtype to finish turning on the dictation key.")
                    Spacer()
                    Button("Restart") { Permissions.relaunch() }.buttonStyle(.borderedProminent)
                } else if missing == 0 {
                    StatusPill(text: "All set")
                    Text("Changes in System Settings show up here right away.")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Changes in System Settings show up here right away.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var updater: Updater
    let runSetup: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        SettingsPage(pane: .general) {
            SettingsCard {
                ToggleRow(title: "Open Hushtype at login", symbol: "power", isOn: $launchAtLogin)
                SettingsRow(title: "Setup assistant", subtitle: "Walk through permissions, your key and Claude again.",
                            symbol: "wand.and.stars") {
                    Button("Run Setup Again…", action: runSetup)
                }
            }
            SectionLabel("Updates")
            SettingsCard {
                if updater.isAvailable {
                    ToggleRow(title: "Check for updates automatically", symbol: "arrow.down.circle",
                              isOn: $updater.automaticallyChecks)
                }
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hushtype \(Updater.version)").fontWeight(.medium)
                        Text(updater.isAvailable ? "Updates come signed from Hushtype's releases." : "Development build, updates are off.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if updater.isAvailable {
                        Button("Check Now") { updater.checkForUpdates() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .onChange(of: launchAtLogin) { LaunchAtLogin.set(launchAtLogin) }
    }
}
