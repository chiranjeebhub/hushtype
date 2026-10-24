import AppKit
import CoreGraphics

/// Types text into the focused app by pasting it, then puts the user's clipboard back.
enum TextInserter {
    /// Tells clipboard managers to ignore our temporary contents (nspasteboard.org convention).
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    @MainActor
    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transientType)
        let ourChange = pasteboard.changeCount

        postCommandV()

        // Give the target app time to read the pasteboard before restoring it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // If something else wrote to the clipboard meanwhile, leave it alone.
            guard pasteboard.changeCount == ourChange else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
    }

    /// Copies the frontmost app's selection with ⌘C and puts the clipboard back. For apps that
    /// don't report their selection through Accessibility. Returns nil when nothing was copied.
    @MainActor
    static func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount
        postKey(8, flags: .maskCommand) // kVK_ANSI_C
        var copied: String?
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(25))
            if pasteboard.changeCount != before {
                copied = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before {
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return copied
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func postCommandV() {
        postKey(9, flags: .maskCommand) // kVK_ANSI_V
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
