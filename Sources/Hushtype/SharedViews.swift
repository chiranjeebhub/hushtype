import AppKit
import HushtypeCore
import ServiceManagement
import SwiftUI

// MARK: - Building blocks

/// A rounded, subtly filled container used for grouped content in setup and settings.
struct Card<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: highlighted ? 1.5 : 1))
    }
}

/// A rounded-square symbol tile, like System Settings' row icons.
struct IconTile: View {
    let symbol: String
    var color: Color = .accentColor
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24).fill(color.gradient))
    }
}

/// Renders a key name like a physical keycap.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
    }
}

// MARK: - Permissions

/// One permission with its live status. `emphasized` marks the next one the user should grant.
struct PermissionRow: View {
    let permission: Permission
    let granted: Bool
    var emphasized = false
    var needsRestart = false

    @State private var requested = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(symbol: permission.symbol, color: granted ? .green : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .animation(.easeOut(duration: 0.2), value: granted)
    }

    private var detail: String {
        if needsRestart { return "Allowed. Restart Hushtype to switch the dictation key on." }
        if !granted && requested, let hint = permission.settingsHint { return hint }
        return permission.purpose
    }

    @ViewBuilder private var trailing: some View {
        if needsRestart {
            Button("Restart") { Permissions.relaunch() }
                .buttonStyle(.borderedProminent)
        } else if granted {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        } else if emphasized {
            Button("Allow") { requested = true; permission.request() }
                .buttonStyle(.borderedProminent)
        } else {
            Button("Allow") { requested = true; permission.request() }
        }
    }
}

// MARK: - API keys

/// A compact key control: once a key is saved it collapses to "Connected · gsk_…a1b2" with Change,
/// otherwise it's a field with a Paste button. Keys are saved to the Keychain and verified as you go.
struct APIKeyField: View {
    let service: APIService
    @ObservedObject var settings: SettingsStore

    @State private var draft = ""
    @State private var editing = false
    @State private var status: Status = .idle
    @State private var check: Task<Void, Never>?

    enum Status: Equatable { case idle, checking, valid, invalid, unverified }

    private var savedKey: String { settings.apiKey(service) }

    var body: some View {
        Group {
            if !savedKey.isEmpty && !editing {
                connected
            } else {
                entry
            }
        }
        .onAppear { if !savedKey.isEmpty { verify(savedKey, after: 0) } }
        .onDisappear { check?.cancel() }
    }

    private var connected: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol).foregroundStyle(statusColor)
            Text(statusLabel).font(.callout.weight(.medium)).foregroundStyle(statusColor)
            Text(masked(savedKey)).font(.callout.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Button("Change") {
                draft = ""
                editing = true
            }
            .buttonStyle(.link)
        }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SecureField("", text: $draft, prompt: Text("Paste your \(service.displayName) API key"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
                Button("Paste") {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        draft = clip
                        save()
                    }
                }
                if editing {
                    Button("Cancel") { editing = false }
                }
            }
            HStack(spacing: 4) {
                if status == .invalid {
                    Label("\(service.displayName) didn't accept that key.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else if status == .checking {
                    ProgressView().controlSize(.mini)
                    Text("Checking…").foregroundStyle(.secondary)
                } else {
                    Text("Don't have one?").foregroundStyle(.secondary)
                    Link("Get an \(service.displayName) key ↗", destination: service.keysURL)
                }
            }
            .font(.caption)
        }
        .onChange(of: draft) {
            // Typing and pasting both land here; save once the value looks complete.
            if draft.count >= 20 { save() }
        }
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != savedKey || editing else { return }
        settings.setAPIKey(key, for: service)
        verify(key, after: 0.3)
    }

    private func verify(_ key: String, after delay: Double) {
        check?.cancel()
        status = .checking
        check = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let result = await APIKeyValidator.validate(key, for: service)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                switch result {
                case .valid:
                    status = .valid
                    editing = false
                case .invalid:
                    status = .invalid
                    editing = true
                case .unreachable:
                    status = .unverified
                    editing = false
                }
            }
        }
    }

    private func masked(_ key: String) -> String {
        guard key.count > 10 else { return "••••" }
        return "\(key.prefix(4))…\(key.suffix(4))"
    }

    private var statusSymbol: String {
        switch status {
        case .valid: return "checkmark.circle.fill"
        case .invalid: return "xmark.circle.fill"
        case .unverified: return "exclamationmark.circle.fill"
        case .idle, .checking: return "key.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .valid: return .green
        case .invalid: return .red
        case .unverified: return .orange
        case .idle, .checking: return .secondary
        }
    }

    private var statusLabel: String {
        switch status {
        case .valid: return "Connected"
        case .invalid: return "Key rejected"
        case .unverified: return "Saved, couldn't verify"
        case .idle, .checking: return "Checking"
        }
    }
}

// MARK: - Polishing

/// The Claude polishing switch with a before/after example and its key.
struct PolishCard: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Card(highlighted: settings.cleanupEnabled) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $settings.cleanupEnabled.animation(.easeInOut(duration: 0.2))) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "sparkles", color: .pink, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Polish with Claude").font(.body.weight(.semibold))
                            Text("Removes filler words, fixes punctuation, applies your corrections.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 6) {
                    example("You say", "um so let's meet at 5, no wait, 6 pm tomorrow", muted: true)
                    example("Hushtype types", settings.cleanupEnabled
                            ? "Let's meet at 6 pm tomorrow."
                            : "um so let's meet at 5, no wait, 6 pm tomorrow", muted: false)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

                if settings.cleanupEnabled {
                    APIKeyField(service: .anthropic, settings: settings)
                        .transition(.opacity)
                }
            }
        }
    }

    private func example(_ label: String, _ text: String, muted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(text)
                .font(.callout)
                .foregroundStyle(muted ? .secondary : .primary)
        }
    }
}

// MARK: - Login item

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Hushtype: launch at login change failed: \(error.localizedDescription)")
        }
    }
}
