import Foundation

/// Turns presses of the dictation key into dictation actions:
/// - hold, talk, release: push-to-talk;
/// - double-tap: hands-free, keeps listening until the key is tapped again (Esc cancels);
/// - a single short tap: ignored.
///
/// Pure state, fed timestamps, so the timing rules are testable.
public struct HotkeyGesture: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        /// Start recording.
        case start
        /// Stop recording and insert.
        case finish
        /// Stop recording and throw it away.
        case cancel
        /// The double-tap landed: keep recording without the key held.
        case lock
        /// Call `timeout(at:)` after this many seconds.
        case waitForSecondTap(TimeInterval)
    }

    /// A press shorter than this is a tap, not push-to-talk.
    public static let tapMaximum: TimeInterval = 0.3
    /// How long after a tap a second press still counts as a double-tap.
    public static let doubleTapWindow: TimeInterval = 0.35

    enum State: Equatable {
        case idle
        case holding(since: TimeInterval)
        case tapped(at: TimeInterval)
        /// Second press of the double-tap is still down.
        case lockedHeld
        case locked
        /// The finishing tap is still down; its release does nothing.
        case awaitingRelease
    }

    public var handsFreeEnabled: Bool
    private(set) var state: State = .idle

    public init(handsFreeEnabled: Bool = true) {
        self.handsFreeEnabled = handsFreeEnabled
    }

    /// True from the first press until the dictation finishes or is cancelled.
    public var isActive: Bool {
        switch state {
        case .idle, .awaitingRelease: return false
        default: return true
        }
    }

    public var isLocked: Bool { state == .locked || state == .lockedHeld }

    public mutating func keyDown(at time: TimeInterval) -> Action {
        switch state {
        case .idle, .awaitingRelease:
            state = .holding(since: time)
            return .start
        case .tapped(let at):
            guard time - at <= Self.doubleTapWindow else {
                // Too late for a double-tap: drop the stray tap and start fresh.
                state = .holding(since: time)
                return .start
            }
            state = .lockedHeld
            return .lock
        case .locked:
            state = .awaitingRelease
            return .finish
        case .holding, .lockedHeld:
            return .none
        }
    }

    public mutating func keyUp(at time: TimeInterval) -> Action {
        switch state {
        case .holding(let since):
            if time - since >= Self.tapMaximum {
                state = .idle
                return .finish
            }
            guard handsFreeEnabled else {
                state = .idle
                return .cancel
            }
            state = .tapped(at: time)
            return .waitForSecondTap(Self.doubleTapWindow)
        case .lockedHeld:
            state = .locked
            return .none
        case .awaitingRelease:
            state = .idle
            return .none
        case .idle, .tapped, .locked:
            return .none
        }
    }

    /// The double-tap window after a tap has passed.
    public mutating func timeout(at time: TimeInterval) -> Action {
        guard case .tapped(let at) = state, time - at >= Self.doubleTapWindow - 0.01 else { return .none }
        state = .idle
        return .cancel
    }

    /// Any other key. While holding it cancels, so shortcuts like ⌥← still work; hands-free only
    /// listens for Esc.
    public mutating func otherKey(isEscape: Bool) -> Action {
        switch state {
        case .holding, .tapped:
            state = .idle
            return .cancel
        case .locked:
            guard isEscape else { return .none }
            state = .idle
            return .cancel
        case .lockedHeld:
            guard isEscape else { return .none }
            state = .awaitingRelease
            return .cancel
        case .idle, .awaitingRelease:
            return .none
        }
    }

    /// Forget any gesture in progress, e.g. when the listener restarts.
    public mutating func reset() {
        state = .idle
    }
}
