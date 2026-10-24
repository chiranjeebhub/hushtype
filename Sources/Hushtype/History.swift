import AppKit
import Carbon.HIToolbox
import HushtypeCore

/// Recent dictations, saved as JSON in Application Support so they survive a restart.
/// Only text and timings are kept, never audio.
enum HistoryStore {
    static let limit = 200

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("Hushtype", isDirectory: true).appendingPathComponent("history.json")
    }

    static func load() -> [DictationResult] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DictationResult].self, from: data)) ?? []
    }

    static func save(_ items: [DictationResult]) {
        guard let url = fileURL else { return }
        let items = Array(items.prefix(limit))
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(items) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    static func erase() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// A system-wide keyboard shortcut through Carbon's hot key API, which needs no extra permission
/// and keeps the keystroke from reaching the frontmost app.
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: a virtual key code such as `kVK_ANSI_V`.
    ///   - modifiers: Carbon modifier flags such as `controlKey | cmdKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            if let userData { Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue().action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x4854_5950), id: 1) // "HTYP"
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0,
                                  &hotKey) == noErr else { return nil }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
