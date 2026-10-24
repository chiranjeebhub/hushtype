import AppKit
import HushtypeCore
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, microphone, inputMonitoring, accessibility, engine, tryIt

    var permission: Permission? {
        switch self {
        case .microphone: return .microphone
        case .inputMonitoring: return .inputMonitoring
        case .accessibility: return .accessibility
        default: return nil
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
            let host = NSHostingController(rootView: OnboardingView(settings: settings, controller: controller) { [weak self] in
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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
    @State private var needsRelaunch = false

    var body: some View {
        VStack(spacing: 0) {
            StepDots(current: step)
                .padding(.top, 22)

            Group {
                switch step {
                case .welcome: welcome
                case .microphone, .inputMonitoring, .accessibility: permissionStep(step.permission!)
                case .engine: engineStep
                case .tryIt: TryItStep(settings: settings, controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            step = resumeStep()
            permissions.start()
        }
        .onDisappear { permissions.stop() }
        .onChange(of: permissions.granted) { permissionsChanged() }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to Hushtype").font(.largeTitle.bold())
            Text("Hold a key, speak, let go. Polished text appears wherever you're typing.\nSetup takes about a minute.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func permissionStep(_ permission: Permission) -> some View {
        let granted = permissions.isGranted(permission)
        return VStack(spacing: 18) {
            ZStack {
                Circle().fill(granted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: granted ? "checkmark" : permission.symbol)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(granted ? Color.green : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(granted ? "\(permission.title) allowed" : "Allow \(permission.title)")
                .font(.title.bold())
            Text(permission.purpose)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if permission == .inputMonitoring && needsRelaunch {
                VStack(spacing: 10) {
                    Text("Allowed. macOS needs Hushtype to restart before the key works. Setup picks up right where you left off.")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                    Button("Restart Hushtype") {
                        settings.onboardingStep = OnboardingStep.accessibility.rawValue
                        Permissions.relaunch()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else if !granted {
                Button("Allow \(permission.title)…") { permission.request() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                if let hint = permission.settingsHint {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open System Settings") { permission.openSettingsPane() }
                        .buttonStyle(.link)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: granted)
    }

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 6) {
                Text("Choose how Hushtype listens").font(.title.bold())
                Text("Cloud engines are fastest. Local keeps your voice on this Mac.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Picker("", selection: $settings.engine) {
                Text("Groq").tag(TranscriptionEngine.groq)
                Text("Deepgram").tag(TranscriptionEngine.deepgram)
                Text("Local").tag(TranscriptionEngine.localWhisper)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch settings.engine {
            case .groq:
                APIKeyField(service: .groq, settings: settings, label: "Groq API key")
            case .deepgram:
                APIKeyField(service: .deepgram, settings: settings, label: "Deepgram API key")
            case .localWhisper:
                LocalWhisperStatus(settings: settings)
            }

            Divider()
            Toggle("Polish text with Claude: remove filler words, fix punctuation, apply corrections",
                   isOn: $settings.cleanupEnabled)
            if settings.cleanupEnabled {
                APIKeyField(service: .anthropic, settings: settings, label: "Anthropic API key")
            }
        }
    }

    // MARK: - Footer and navigation

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(to: OnboardingStep(rawValue: step.rawValue - 1)!) }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if step == .engine && !settings.engineConfigured {
                Button("Skip for now") { go(to: .tryIt) }
            }
            Button(primaryTitle) { advance() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
        }
        .controlSize(.large)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .tryIt: return "Finish"
        default: return "Continue"
        }
    }

    private var canAdvance: Bool {
        if let permission = step.permission { return permissions.isGranted(permission) && !needsRelaunch }
        if step == .engine { return settings.engineConfigured }
        return true
    }

    private func advance() {
        if step == .tryIt {
            settings.hasCompletedOnboarding = true
            settings.onboardingStep = 0
            close()
            return
        }
        go(to: nextIncomplete(after: step))
    }

    private func go(to target: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.3)) { step = target }
        settings.onboardingStep = target.rawValue
    }

    /// Skips permission steps that are already granted.
    private func nextIncomplete(after current: OnboardingStep) -> OnboardingStep {
        var next = OnboardingStep(rawValue: current.rawValue + 1) ?? .tryIt
        while let permission = next.permission, permissions.isGranted(permission) {
            next = OnboardingStep(rawValue: next.rawValue + 1)!
        }
        return next
    }

    private func resumeStep() -> OnboardingStep {
        let saved = OnboardingStep(rawValue: settings.onboardingStep) ?? .welcome
        // Anything still missing comes first, so a revoked permission is never skipped.
        if settings.hasCompletedOnboarding || saved != .welcome {
            if let missing = OnboardingStep.allCases.first(where: { $0.permission.map { !permissions.isGranted($0) } ?? false }) {
                return missing
            }
            return saved == .welcome ? .engine : saved
        }
        return .welcome
    }

    /// Moves on by itself once the permission on screen is granted.
    private func permissionsChanged() {
        guard let permission = step.permission, permissions.isGranted(permission) else { return }
        if permission == .inputMonitoring {
            controller.restartHotkey()
            if !controller.hotkeyActive {
                needsRelaunch = true
                return
            }
        }
        let current = step
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if step == current { go(to: nextIncomplete(after: current)) }
        }
    }
}

private struct StepDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: step == current ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
    }
}

struct LocalWhisperStatus: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(settings.localWhisperReady ? "whisper.cpp and the model are ready." : "whisper.cpp isn't set up yet.",
                  systemImage: settings.localWhisperReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(settings.localWhisperReady ? .green : .orange)
            if !settings.localWhisperReady {
                Text("Run `brew install whisper-cpp`, then download **ggml-large-v3-turbo-q5_0.bin** into ~/Library/Application Support/Hushtype/models. You can change both paths in Settings › Engines.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The last step: a practice field to dictate into, which celebrates the first successful dictation.
private struct TryItStep: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    @State private var practice = ""
    @State private var baseline = 0
    @FocusState private var focused: Bool

    private var succeeded: Bool { controller.history.count > baseline }

    var body: some View {
        VStack(spacing: 14) {
            Text(succeeded ? "You're all set" : "Try it").font(.title.bold())
            HStack(spacing: 6) {
                Text("Hold")
                Text(settings.triggerKey.displayName)
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.5)))
                Text("and say “Hushtype makes typing feel effortless”, then let go.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            TextEditor(text: $practice)
                .font(.title3)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(succeeded ? Color.green : Color.secondary.opacity(0.3), lineWidth: succeeded ? 2 : 1))
                .frame(height: 120)

            Group {
                switch controller.phase {
                case .recording: Label("Listening…", systemImage: "waveform").foregroundStyle(.red)
                case .transcribing, .cleaning: Label("Working on it…", systemImage: "ellipsis")
                case .error(let message): Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                case .idle:
                    if succeeded {
                        Label("That's it. Use it in any app.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text(" ")
                    }
                }
            }
            .font(.callout)

            Picker("Dictation key", selection: $settings.triggerKey) {
                ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
            }
            .frame(maxWidth: 300)
            .onChange(of: settings.triggerKey) { controller.restartHotkey() }
        }
        .onAppear {
            baseline = controller.history.count
            focused = true
        }
    }
}
