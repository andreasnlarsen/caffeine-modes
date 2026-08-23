import CaffeineModesCore
import Foundation

public enum AwayModeWakeAction: Equatable, Sendable {
    case none
    case checkLockState
    case finishAfterUnlock
    case resleepDisplay
}

public struct AwayModeWakeStateMachine: Sendable {
    public private(set) var resleepDeadline: TimeInterval?

    private var awayModeIsActive = false
    private let resleepDelay: TimeInterval

    public init(resleepDelay: TimeInterval = 30) {
        self.resleepDelay = resleepDelay
    }

    public mutating func modeDidChange(
        to mode: OperatingMode,
        restoredSession: Bool = false,
        now: TimeInterval? = nil
    ) -> AwayModeWakeAction {
        let shouldCheckRestoredAwayMode = restoredSession && mode.isAwayMode
        awayModeIsActive = mode.isAwayMode
        if !awayModeIsActive {
            resleepDeadline = nil
        } else if shouldCheckRestoredAwayMode, let now {
            resleepDeadline = now + resleepDelay
        }
        return shouldCheckRestoredAwayMode ? .checkLockState : .none
    }

    public mutating func screensDidWake(now: TimeInterval) -> AwayModeWakeAction {
        displayMayBeVisible(now: now)
    }

    public mutating func displayConfigurationDidChange(
        now: TimeInterval
    ) -> AwayModeWakeAction {
        displayMayBeVisible(now: now)
    }

    private mutating func displayMayBeVisible(now: TimeInterval) -> AwayModeWakeAction {
        guard awayModeIsActive else {
            resleepDeadline = nil
            return .none
        }
        resleepDeadline = now + resleepDelay
        return .checkLockState
    }

    public mutating func lockStateObserved(
        isLocked: Bool,
        now: TimeInterval
    ) -> AwayModeWakeAction {
        guard awayModeIsActive, resleepDeadline != nil else { return .none }
        if !isLocked {
            resleepDeadline = nil
            return .finishAfterUnlock
        }
        return timerFired(now: now)
    }

    public mutating func timerFired(now: TimeInterval) -> AwayModeWakeAction {
        guard awayModeIsActive,
              let deadline = resleepDeadline,
              now >= deadline
        else { return .none }
        resleepDeadline = nil
        return .resleepDisplay
    }

    public mutating func screensDidSleep() {
        resleepDeadline = nil
    }

    public mutating func verifiedUnlockObserved() {
        resleepDeadline = nil
    }
}
