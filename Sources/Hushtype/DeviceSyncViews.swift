import AppKit
import CoreImage.CIFilterBuiltins
import HushtypeCore
import SwiftUI

/// The "Your devices" section in Settings › General: turn sync on, show the pairing code to the
/// iPhone or Android app, or join with a code from another device.
struct DeviceSyncSection: View {
    @ObservedObject var sync: DeviceSync
    @State private var showingCode = false
    @State private var joining = false

    var body: some View {
        SectionLabel("Your devices")
        SettingsCard {
            if sync.isOn {
                SettingsRow(title: "Dictionary and snippets sync",
                            subtitle: statusText,
                            symbol: "arrow.clockwise",
                            info: Self.privacyNote) {
                    if case .syncing = sync.status {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Sync Now") { sync.syncNow() }
                    }
                }
                SettingsRow(title: "Add a device",
                            subtitle: "Scan the code with Hushtype on your iPhone or Android, or type it on another Mac.",
                            symbol: "plus") {
                    Button("Show Pairing Code…") { showingCode = true }
                        .buttonStyle(.borderedProminent)
                }
                SettingsRow(title: "Stop syncing on this Mac",
                            subtitle: "Your words stay here. Your other devices keep syncing with each other.",
                            symbol: "power") {
                    Button("Turn Off") { sync.turnOff() }
                }
            } else {
                SettingsRow(title: "Sync with your iPhone and Android",
                            subtitle: "Your dictionary and snippets, end-to-end encrypted. No account needed.",
                            symbol: "arrow.clockwise",
                            info: Self.privacyNote) {
                    HStack(spacing: 8) {
                        Button("Enter Code…") { joining = true }
                        Button("Turn On") {
                            sync.turnOn()
                            showingCode = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCode) {
            if let keys = sync.keys { PairingCodeSheet(keys: keys) }
        }
        .sheet(isPresented: $joining) {
            JoinSheet(sync: sync)
        }
    }

    static let privacyNote = """
        Words are encrypted on your device with a key only your paired devices have, then stored on \
        Hushtype's sync server, which can't read them. Pairing hands that key over through the QR \
        code, so keep the code private. Your dictation key, history and Claude key never leave this Mac.
        """

    private var statusText: String {
        switch sync.status {
        case .off: return "Off"
        case .syncing: return "Syncing…"
        case .upToDate(let date):
            if Date().timeIntervalSince(date) < 60 { return "Up to date" }
            return "Up to date · synced \(date.formatted(.relative(presentation: .named)))"
        case .failed(let message): return message
        }
    }
}

/// The QR code and the typed code for adding another device.
private struct PairingCodeSheet: View {
    let keys: SyncKeys
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Add a device").font(.title2.weight(.semibold))
                Text("In Hushtype on your iPhone or Android, open Settings › Sync and scan this code.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let image = QRCode.image(for: keys.pairingCode) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.hushViolet.opacity(0.5), lineWidth: 1))
                    .shadow(color: Color.hushViolet.opacity(0.2), radius: 12, y: 4)
                    .accessibilityLabel("Pairing QR code")
            }
            VStack(spacing: 6) {
                Text("On another Mac, type this code instead")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(keys.pairingCode)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(width: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(copied ? "Copied" : "Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(keys.pairingCode, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            Text("Anyone with this code can read and change your dictionary. Only share it with your own devices.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 420)
        .tint(.hushViolet)
    }
}

/// Typing a code from another Mac (or reading it off a phone).
private struct JoinSheet: View {
    @ObservedObject var sync: DeviceSync
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Join your other devices").font(.title2.weight(.semibold))
            Text("On a device that already syncs, open Hushtype's sync settings, choose to show the pairing code, and type or paste it here. Your words here are merged with theirs.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("HT1-XXXX-XXXX-…", text: $code, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)
                .onSubmit(join)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: join) {
                    if working { ProgressView().controlSize(.small) } else { Text("Join") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(working || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .tint(.hushViolet)
    }

    private func join() {
        guard !working else { return }
        working = true
        error = nil
        Task {
            do {
                try await sync.join(code: code)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

enum QRCode {
    /// A crisp black-on-white QR code, one point per module (scale it up with `.interpolation(.none)`).
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: output.extent.size)
    }
}
