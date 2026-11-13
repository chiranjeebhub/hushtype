import CoreGraphics
import Foundation

/// While Hushtype watches a dictation for corrections, reads the field the instant Return goes
/// down. Chat apps send and clear the message on Return, so any later look finds an empty box and
/// misses the word the user just fixed. This is an active tap, so macOS holds the Return until the
/// read is done (a fraction of a second at most, and only while watching). It runs on its own
/// thread so a busy main thread never slows typing, and it's switched off the rest of the time.
final class ReturnKeyTap: @unchecked Sendable {
    typealias Reader = @Sendable () -> String?
    typealias Handler = @Sendable (String?) -> Void

    private let lock = NSLock()
    private var reader: Reader?
    private var handler: Handler?
    private var tap: CFMachPort?
    private var thread: Thread?

    /// Calls `read` on every Return until `stop()`, and passes each result to `onRead` on the
    /// tap's thread.
    func start(read: @escaping Reader, onRead: @escaping Handler) {
        let tap = lock.withLock { () -> CFMachPort? in
            reader = read
            handler = onRead
            return self.tap
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else if thread == nil {
            launch()
        }
    }

    func stop() {
        let tap = lock.withLock { () -> CFMachPort? in
            reader = nil
            handler = nil
            return self.tap
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func launch() {
        let thread = Thread { [self] in run() }
        thread.name = "Hushtype Return key"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    private func run() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<ReturnKeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        let watching = lock.withLock { () -> Bool in
            self.tap = tap
            return reader != nil
        }
        CGEvent.tapEnable(tap: tap, enable: watching)
        CFRunLoopRun()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let (read, onRead, tap) = lock.withLock { (reader, handler, self.tap) }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if read != nil, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // kVK_Return, kVK_ANSI_KeypadEnter
            guard keyCode == 36 || keyCode == 76, let read, let onRead else { return }
            onRead(read())
        default:
            break
        }
    }
}
