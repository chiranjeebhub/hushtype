import AppKit
import HushtypeCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let controller: DictationController
    private var window: NSWindow?

    init(settings: SettingsStore, controller: DictationController) {
        self.settings = settings
        self.controller = controller
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(settings: settings, controller: controller)))
            window.title = "Hushtype Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController

    var body: some View {
        TabView {
            PermissionsTab(settings: settings, controller: controller)
                .tabItem { Label("Setup", systemImage: "checkmark.shield") }
            GeneralTab(settings: settings, controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
            EnginesTab(settings: settings)
                .tabItem { Label("Engines", systemImage: "key") }
            DictionaryTab(settings: settings)
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}

// MARK: - Setup

private struct PermissionsTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController
    @State private var tick = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hushtype needs three permissions. Grant each one, then hold your hotkey and talk.")
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(title: "Microphone", detail: "Record your voice while the hotkey is held.",
                          granted: Permissions.microphone) {
                Task { _ = await Permissions.requestMicrophone(); tick += 1 }
            }
            PermissionRow(title: "Input Monitoring", detail: "Notice the push-to-talk key in any app.",
                          granted: Permissions.inputMonitoring) {
                Permissions.requestInputMonitoring()
            }
            PermissionRow(title: "Accessibility", detail: "Paste the text into the app you're using.",
                          granted: Permissions.accessibility) {
                Permissions.requestAccessibility()
            }

            Text("macOS may ask you to relaunch Hushtype after granting Input Monitoring.")
                .font(.footnote).foregroundStyle(.secondary)

            Spacer()
            HStack {
                Spacer()
                Button("Done") { settings.hasCompletedOnboarding = true; NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .id(tick)
        .onReceive(timer) { _ in
            tick += 1
            // Pick up a newly granted Input Monitoring permission without a relaunch when possible.
            if !controller.hotkeyActive && Permissions.inputMonitoring { controller.restartHotkey() }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant…", action: request) }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var controller: DictationController

    private struct Language: Identifiable {
        let id: String
        let name: String
    }

    private let languages = [Language(id: "en", name: "English"), Language(id: "auto", name: "Detect automatically"),
                             Language(id: "es", name: "Spanish"), Language(id: "fr", name: "French"),
                             Language(id: "de", name: "German"), Language(id: "hi", name: "Hindi"),
                             Language(id: "pt", name: "Portuguese"), Language(id: "ja", name: "Japanese"),
                             Language(id: "zh", name: "Chinese")]

    var body: some View {
        Form {
            Picker("Push-to-talk key", selection: $settings.triggerKey) {
                ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
            }
            .onChange(of: settings.triggerKey) { controller.restartHotkey() }
            if settings.triggerKey == .fn {
                Text("Set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing” so macOS doesn't also react to Fn.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Picker("Language", selection: $settings.language) {
                ForEach(languages) { Text($0.name).tag($0.id) }
            }

            Toggle("Polish text with Claude (remove fillers, fix punctuation)", isOn: $settings.cleanupEnabled)
            if settings.cleanupEnabled && settings.apiKey(.anthropic).isEmpty {
                Text("Add an Anthropic API key in Engines to enable polishing. Until then, raw transcripts are inserted.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Engines

private struct EnginesTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Picker("Speech-to-text", selection: $settings.engine) {
                ForEach(TranscriptionEngine.allCases) { Text($0.displayName).tag($0) }
            }

            Section("API keys (stored in your Keychain)") {
                APIKeyField(service: .groq, settings: settings)
                APIKeyField(service: .deepgram, settings: settings)
                APIKeyField(service: .anthropic, settings: settings)
            }

            if settings.engine == .localWhisper {
                Section("Local whisper.cpp") {
                    TextField("whisper-cli path", text: $settings.whisperExecutablePath)
                    TextField("Model file", text: $settings.whisperModelPath)
                    Text("Install with `brew install whisper-cpp` and download a model such as ggml-large-v3-turbo-q5_0.bin from huggingface.co/ggerganov/whisper.cpp.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct APIKeyField: View {
    let service: APIService
    @ObservedObject var settings: SettingsStore
    @State private var value = ""

    var body: some View {
        SecureField(service.displayName, text: $value, prompt: Text("Paste key"))
            .onAppear { value = settings.apiKey(service) }
            .onChange(of: value) { settings.setAPIKey(value, for: service) }
    }
}

// MARK: - Dictionary

private struct DictionaryTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Names, products, and jargon you say often, one per line. Hushtype passes them to the speech engine and to Claude so they're spelled right.")
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $settings.dictionaryText)
                .font(.body.monospaced())
                .border(Color.secondary.opacity(0.3))
            Text("\(settings.vocabulary.count) terms").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
