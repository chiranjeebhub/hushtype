import AppKit
import CoreGraphics
import HushtypeCore

/// Watches a modifier key system-wide with a listen-only CGEventTap, which is the only way to
/// see the Fn key. `HotkeyGesture` turns its presses into actions: hold to talk, double-tap for
/// hands-free. Pressing any other key while holding cancels, so normal shortcuts like ⌥← still
/// work. Adding Control while recording switches to command mode.
final class HotkeyMonitor {
    var triggerKey: TriggerKey = .rightOption
    var handsFreeEnabled = true {
        didSet { gesture.handsFreeEnabled = handsFreeEnabled }
    }
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onCancel: () -> Void = {}
    /// A double-tap turned the recording hands-free.
    var onLock: () -> Void = {}
    /// Control went down while recording.
    var onCommand: () -> Void = {}

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gesture = HotkeyGesture()

    /// Returns false when macOS won't let Hushtype watch the keyboard yet.
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
        gesture.reset()
    }

    var isRunning: Bool { tap != nil }

    /// Tells the gesture that the dictation ended on its own (an error, the Mac going to sleep).
    func reset() {
        gesture.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            perform(gesture.otherKey(isEscape: keyCode == 53)) // kVK_Escape
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if gesture.isActive, keyCode == 59 || keyCode == 62, event.flags.contains(.maskControl) { // kVK_(Right)Control
                onCommand()
                return
            }
            guard keyCode == triggerKey.keyCode else { return }
            let now = ProcessInfo.processInfo.systemUptime
            perform(event.flags.contains(triggerKey.flag) ? gesture.keyDown(at: now) : gesture.keyUp(at: now))
        default:
            break
        }
    }

    private func perform(_ action: HotkeyGesture.Action) {
        switch action {
        case .none: break
        case .start: onPress()
        case .finish: onRelease()
        case .cancel: onCancel()
        case .lock: onLock()
        case .waitForSecondTap(let seconds):
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { return }
                self.perform(self.gesture.timeout(at: ProcessInfo.processInfo.systemUptime))
            }
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
