import AppKit
import HushtypeCore
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, speechModel, claude, tryIt

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .permissions: return "Permissions"
        case .speechModel: return "Voice model"
        case .claude: return "Connect Claude"
        case .tryIt: return "Try it"
        }
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let controller: DictationController
    private var window: NSWindow?

    init(settings: SettingsStore, controller: DictationController) {
        self.settings = settings
        self.controller = controller
    }

    func show() {
        if window == nil {
            let view = OnboardingView(settings: settings, controller: controller) { [weak self] in
                self?.window?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        // Center every time it's shown, so it never turns up off to the side or on another screen.
        window?.centerOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    let close: () -> Void

    @StateObject private var permissions = PermissionMonitor()
    @State private var step: OnboardingStep = .welcome
    @State private var practice = ""
    @State private var dictationsAtStart = 0
    @State private var modelStatus: AppleSpeechModel.Status?
    @State private var modelProgress = 0.0
    @State private var modelError: String?
    @FocusState private var practiceFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 36)
                    .padding(.top, 40)
                    .id(step)
                    .transition(.opacity.combined(with: .offset(x: 12)))
                footer
                    .padding(.horizontal, 36)
                    .padding(.bottom, 24)
            }
        }
        .frame(width: 760, height: 480)
        .onAppear {
            step = resumeStep()
            dictationsAtStart = controller.history.count
            permissions.start()
            // Know the model's state up front so the sidebar ticks it even if that step is skipped over.
            Task { modelStatus = await AppleSpeechModel.status(language: settings.transcriptionOptions.language) }
        }
        .onDisappear { permissions.stop() }
        .onChange(of: permissions.granted) { old, new in
            // Come back from System Settings as soon as the switch is flipped there.
            if !new.isSubset(of: old) { Permissions.bringWindowsForward() }
            permissionsChanged()
        }
        .onChange(of: step) {
            // Don't let a text box on the new step grab focus by itself; the user clicks in when ready.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                Text("Hushtype").font(.title3.weight(.semibold))
            }
            .padding(.top, 48)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    sidebarRow(item)
                }
            }
            Spacer()
            Text("About a minute to set up.\nYou can change anything later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 18)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        // A full-height sidebar like System Settings: the material runs under the transparent
        // title bar, and its edge against the content does the dividing, so no line is needed.
        .background(SidebarMaterial().ignoresSafeArea())
    }

    private func sidebarRow(_ item: OnboardingStep) -> some View {
        let isCurrent = item == step
        let isDone = isComplete(item) && item.rawValue < step.rawValue
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : (isCurrent ? Color.accentColor : Color.primary.opacity(0.08)))
                    .frame(width: 22, height: 22)
                if isDone {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(item.rawValue + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }
            Text(item.title)
                .font(.callout.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
            Spacer()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isCurrent ? Color.accentColor.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            // Jump back to any earlier step; forward only through Continue.
            if item.rawValue < step.rawValue { go(to: item) }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .permissions: permissionsStep
        case .speechModel: speechModelStep
        case .claude: claudeStep
        case .tryIt: tryItStep
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 26, weight: .bold))
            Text(subtitle).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 22)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Talk instead of type", "Hold a key, speak naturally, and let go. Hushtype writes it out, cleaned up, in whatever app you're using.")
            VStack(alignment: .leading, spacing: 14) {
                feature("keyboard", .blue, "Works everywhere", "Slack, Mail, Notion, your code editor. Anywhere you can type.")
                feature("sparkles", .pink, "Reads like you wrote it", "Filler words gone, punctuation fixed, corrections applied.")
                feature("lock.fill", .teal, "Your keys, your data", "Speech is transcribed on this Mac. Only text goes to Claude, with your own key.")
            }
        }
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol, color: color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var nextPermission: Permission? {
        Permission.allCases.first { !permissions.isGranted($0) }
    }

    private var hotkeyNeedsRestart: Bool {
        permissions.isGranted(.accessibility) && !controller.hotkeyActive
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Give Hushtype access", "macOS asks for these once. Each one ticks itself off as soon as you allow it.")
            Card {
                VStack(spacing: 14) {
                    ForEach(Permission.allCases) { permission in
                        PermissionRow(permission: permission,
                                      granted: permissions.isGranted(permission),
                                      emphasized: permission == nextPermission,
                                      needsRestart: permission == .accessibility && hotkeyNeedsRestart)
                        if permission != Permission.allCases.last { Divider() }
                    }
                }
            }
            if hotkeyNeedsRestart {
                Text("Setup will pick up right here after the restart.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private var speechModelStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Download the voice model", "Hushtype turns speech into text right on this Mac with Apple's speech model. It downloads once and works offline after that.")
            Card {
                HStack(alignment: modelStatus == .installed ? .center : .top, spacing: 14) {
                    IconTile(symbol: modelStatus == .installed ? "checkmark" : "waveform",
                             color: modelStatus == .installed ? .green : .purple, size: 34)
                    VStack(alignment: .leading, spacing: 8) {
                        switch modelStatus {
                        case .installed:
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Voice model ready").font(.body.weight(.semibold))
                                Text("\(languageName) · runs on this Mac, works offline")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        case .unsupported:
                            Text("This language isn't supported on-device yet. Pick another one in Settings › General.")
                                .foregroundStyle(.orange)
                        default:
                            Text(modelError ?? "Downloading…").font(.body.weight(.semibold))
                            ProgressView(value: modelProgress)
                            if modelError != nil {
                                Button("Try again") { installSpeechModel() }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { installSpeechModel() }
    }

    private func installSpeechModel() {
        let language = settings.transcriptionOptions.language
        modelError = nil
        Task {
            modelStatus = await AppleSpeechModel.status(language: language)
            let downloading = modelStatus == .notInstalled
            if downloading {
                do {
                    try await AppleSpeechModel.install(language: language) { value in
                        Task { @MainActor in modelProgress = value }
                    }
                    modelStatus = await AppleSpeechModel.status(language: language)
                } catch {
                    modelError = error.localizedDescription
                    return
                }
            }
            // Nothing to decide on this step, so move on by itself once a download finishes.
            // (Coming back to it with Back shouldn't bounce you forward again.)
            if downloading && modelStatus == .installed && step == .speechModel {
                try? await Task.sleep(for: .seconds(1.2))
                if step == .speechModel { go(to: .claude) }
            }
        }
    }

    private var languageName: String {
        let code = settings.transcriptionOptions.language ?? Locale.current.language.languageCode?.identifier ?? "en"
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    private var claudeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Connect Claude", "Your speech is transcribed on this Mac, then Claude turns it into clean, punctuated text. One key is all it takes.")
            PolishCard(settings: settings)
        }
    }

    private var dictated: Bool { controller.history.count > dictationsAtStart }

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(dictated ? "You're all set" : "Try your first dictation",
                   dictated ? "Hushtype is ready in every app. It lives in your menu bar." : "Click into the box, then use your dictation key.")

            HStack(spacing: 6) {
                Text("Hold").foregroundStyle(.secondary)
                Keycap(label: settings.triggerKey.displayName)
                Text("and say “Hushtype makes typing feel effortless”, then let go.").foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.bottom, 12)

            TextEditor(text: $practice)
                .font(.title3)
                .focused($practiceFocused)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .frame(height: 130)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(dictated ? Color.green : Color.primary.opacity(0.12), lineWidth: dictated ? 2 : 1))

            HStack {
                practiceStatus.font(.callout)
                Spacer()
                Picker("Key", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
                }
                .fixedSize()
                .onChange(of: settings.triggerKey) { controller.restartHotkey() }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder private var practiceStatus: some View {
        switch controller.phase {
        case .recording: Label("Listening…", systemImage: "waveform").foregroundStyle(.red)
        case .transcribing, .cleaning: Label("Writing…", systemImage: "ellipsis")
        case .error(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .idle, .notice:
            if dictated {
                Label("It works.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("Waiting for your voice…").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer and navigation

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(to: OnboardingStep(rawValue: step.rawValue - 1)!) }
                    .controlSize(.large)
            }
            Spacer()
            if let skip = skipTitle {
                Button(skip) { skipCurrent() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
            }
            Button(primaryTitle) { advance() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isComplete(step))
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .tryIt: return dictated ? "Done" : "Finish"
        default: return "Continue"
        }
    }

    private var skipTitle: String? {
        switch step {
        case .claude where !isComplete(.claude): return "Skip, use raw transcripts"
        default: return nil
        }
    }

    private func isComplete(_ item: OnboardingStep) -> Bool {
        switch item {
        case .permissions: return Permissions.allGranted && controller.hotkeyActive
        case .speechModel: return modelStatus == .installed
        case .claude: return !settings.cleanupEnabled || !settings.apiKey(.anthropic).isEmpty
        default: return true
        }
    }

    private func skipCurrent() {
        if step == .claude { settings.cleanupEnabled = false }
        go(to: OnboardingStep(rawValue: step.rawValue + 1)!)
    }

    private func advance() {
        guard step != .tryIt else {
            settings.hasCompletedOnboarding = true
            settings.onboardingStep = 0
            close()
            return
        }
        go(to: OnboardingStep(rawValue: step.rawValue + 1)!)
    }

    private func go(to target: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.25)) { step = target }
        settings.onboardingStep = target.rawValue
    }

    private func resumeStep() -> OnboardingStep {
        if !isComplete(.permissions) && (settings.hasCompletedOnboarding || settings.onboardingStep > 0) {
            return .permissions
        }
        return OnboardingStep(rawValue: settings.onboardingStep) ?? .welcome
    }

    private func permissionsChanged() {
        if permissions.isGranted(.accessibility) && !controller.hotkeyActive {
            controller.restartHotkey()
            // If the tap still can't start, the row offers a restart; resume here afterwards.
            if !controller.hotkeyActive { settings.onboardingStep = OnboardingStep.permissions.rawValue }
        }
        if step == .permissions && isComplete(.permissions) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if step == .permissions && isComplete(.permissions) { go(to: .speechModel) }
            }
        }
    }
}

/// The translucent sidebar material macOS uses in System Settings and Finder.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
