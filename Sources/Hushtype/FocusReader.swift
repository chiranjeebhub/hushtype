import AppKit
import ApplicationServices
import HushtypeCore

/// The focused text field in the frontmost app, read through the Accessibility API.
struct FocusedField: @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t

    /// The whole field's text. Can be large in documents, so prefer `text(in:)`.
    var value: String? { string(kAXValueAttribute) }

    var selectedText: String? { string(kAXSelectedTextAttribute) }

    var selectedRange: NSRange? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    var characterCount: Int? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &raw) == .success
        else { return nil }
        return (raw as? NSNumber)?.intValue
    }

    var isSecure: Bool {
        string(kAXSubroleAttribute) == kAXSecureTextFieldSubrole as String
    }

    /// Text in a UTF-16 range, clamped to the field. Falls back to slicing the whole value for apps
    /// that don't answer the range query.
    func text(in range: NSRange) -> String? {
        guard range.length > 0 else { return "" }
        var cfRange = CFRange(location: range.location, length: range.length)
        if let param = AXValueCreate(.cfRange, &cfRange) {
            var raw: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                          param, &raw) == .success, let text = raw as? String {
                return text
            }
        }
        guard let value else { return nil }
        let full = value as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: full.length))
        return clamped.length > 0 ? full.substring(with: clamped) : ""
    }

    private func string(_ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }
}

/// Reads the app and text around the cursor. AX calls can block on a busy app, so every call has a
/// short timeout and the capture runs off the main thread.
enum FocusReader {
    /// Chromium and Electron apps only build their accessibility tree once someone asks for it.
    private static let manualAccessibility = "AXManualAccessibility" as CFString
    nonisolated(unsafe) private static var enabledPIDs = Set<pid_t>()
    private static let lock = NSLock()

    @MainActor
    static func frontmostApp() -> (name: String?, bundleID: String?, pid: pid_t?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier, app?.processIdentifier)
    }

    static func focusedField(pid: pid_t) -> FocusedField? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let firstTime = lock.withLock { enabledPIDs.insert(pid).inserted }
        if firstTime { AXUIElementSetAttributeValue(app, manualAccessibility, kCFBooleanTrue) }

        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        return FocusedField(element: element, pid: pid)
    }

    /// Builds the context for a dictation. With `includeText` off, only the app is recorded.
    static func capture(appName: String?, bundleID: String?, pid: pid_t?,
                        includeText: Bool) -> (context: DictationContext, field: FocusedField?) {
        var context = DictationContext(appName: appName, bundleID: bundleID)
        guard let pid, let field = focusedField(pid: pid) else { return (context, nil) }
        // Never read password fields.
        guard !field.isSecure else { return (context, nil) }

        let selection = field.selectedRange
        let selected = field.selectedText ?? ""
        guard includeText else {
            context.selectedText = selected
            context.selectionLocation = selection?.location
            return (context, field)
        }

        var before = "", after = ""
        if let selection {
            let start = max(0, selection.location - DictationContext.beforeLimit)
            before = field.text(in: NSRange(location: start, length: selection.location - start)) ?? ""
            let end = selection.location + selection.length
            var afterLength = DictationContext.afterLimit
            if let count = field.characterCount { afterLength = min(afterLength, max(0, count - end)) }
            after = field.text(in: NSRange(location: end, length: afterLength)) ?? ""
        }
        context = DictationContext(appName: appName, bundleID: bundleID, textBefore: before, textAfter: after,
                                   selectedText: selected, selectionLocation: selection?.location)
        return (context, field)
    }
}
