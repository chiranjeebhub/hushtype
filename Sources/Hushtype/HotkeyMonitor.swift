import AppKit
import CoreGraphics

/// Watches a modifier key system-wide with a listen-only CGEventTap, which is the only way to
/// see the Fn key. Holding the key starts dictation; releasing it stops. Pressing any other key
/// while holding cancels, so normal shortcuts like ⌥← still work.
final class HotkeyMonitor {
    var triggerKey: TriggerKey = .rightOption
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onCancel: () -> Void = {}

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHeld = false

    /// Returns false when Input Monitoring has not been granted yet.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isHeld = false
    }

    var isRunning: Bool { tap != nil }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            if isHeld {
                isHeld = false
                onCancel()
            }
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == triggerKey.keyCode else { return }
            let down = event.flags.contains(triggerKey.flag)
            if down && !isHeld {
                isHeld = true
                onPress()
            } else if !down && isHeld {
                isHeld = false
                onRelease()
            }
        default:
            break
        }
    }
}

extension TriggerKey {
    /// Virtual key codes from HIToolbox/Events.h.
    var keyCode: Int64 {
        switch self {
        case .fn: return 63          // kVK_Function
        case .rightOption: return 61 // kVK_RightOption
        case .rightCommand: return 54 // kVK_RightCommand
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        }
    }
}
