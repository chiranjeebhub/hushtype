import HushtypeCore
import ServiceManagement
import SwiftUI

/// One permission with its live status and a button that does the right thing to grant it.
struct PermissionRow: View {
    let permission: Permission
    let granted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(granted ? Color.green : Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.body.weight(.medium))
                Text(permission.purpose).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            } else {
                Button("Allow…") { permission.request() }
            }
        }
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.2), value: granted)
    }
}

/// A secure key field that saves to the Keychain and verifies the key against the service as you type.
struct APIKeyField: View {
    let service: APIService
    @ObservedObject var settings: SettingsStore
    var label: String? = nil

    @State private var value = ""
    @State private var status: Status = .empty
    @State private var check: Task<Void, Never>?

    enum Status: Equatable {
        case empty, checking, valid, invalid, unverified(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SecureField(label ?? service.displayName, text: $value, prompt: Text(service.keyPlaceholder))
                    .textFieldStyle(.roundedBorder)
                statusBadge.frame(width: 18)
            }
            HStack(spacing: 4) {
                statusText
                Spacer()
                Link("Get a \(service.displayName) key", destination: service.keysURL)
            }
            .font(.caption)
        }
        .onAppear {
            value = settings.apiKey(service)
            if !value.isEmpty { verify(after: 0) }
        }
        .onChange(of: value) {
            guard value.trimmingCharacters(in: .whitespacesAndNewlines) != settings.apiKey(service) else { return }
            settings.setAPIKey(value, for: service)
            verify(after: 0.6)
        }
        .onDisappear { check?.cancel() }
    }

    @ViewBuilder private var statusBadge: some View {
        switch status {
        case .empty: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .valid: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unverified: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var statusText: some View {
        switch status {
        case .empty: Text("Stored securely in your Keychain.").foregroundStyle(.secondary)
        case .checking: Text("Checking…").foregroundStyle(.secondary)
        case .valid: Text("Key works.").foregroundStyle(.green)
        case .invalid: Text("\(service.displayName) rejected this key.").foregroundStyle(.red)
        case .unverified(let reason): Text("Couldn't verify (\(reason)). It's saved anyway.").foregroundStyle(.orange)
        }
    }

    private func verify(after delay: Double) {
        check?.cancel()
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            status = .empty
            return
        }
        status = .checking
        check = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let result = await APIKeyValidator.validate(key, for: service)
            guard !Task.isCancelled else { return }
            switch result {
            case .valid: status = .valid
            case .invalid: status = .invalid
            case .unreachable(let reason): status = .unverified(reason)
            }
        }
    }
}

/// Wraps the macOS login item for the app bundle.
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
