import CaffeineModesCore
import Foundation

final class FakeAmphetamine: AmphetamineControlling {
    var isInstalled = true
    var installedVersion: String? = "5.3.2"
    var state: AmphetamineState = .inactive
    var commands: [String] = []
    var readError: Error?
    var failureCommand: String?
    var refuseToEnd = false

    func readState() throws -> AmphetamineState {
        commands.append("read")
        if let readError { throw readError }
        return state
    }

    func startInfiniteSession(displaySleepAllowed: Bool) throws {
        try failIfRequested("startInfinite")
        commands.append("startInfinite:\(displaySleepAllowed)")
        state.sessionIsActive = true
        state.displaySleepAllowed = displaySleepAllowed
        state.remainingMinutes = nil
    }

    func startTimedSession(minutes: Int, displaySleepAllowed: Bool) throws {
        try failIfRequested("startTimed")
        commands.append("startTimed:\(minutes):\(displaySleepAllowed)")
        state.sessionIsActive = true
        state.displaySleepAllowed = displaySleepAllowed
        state.remainingMinutes = minutes
    }

    func endSession() throws {
        try failIfRequested("end")
        commands.append("end")
        if !refuseToEnd { state = .inactive }
    }

    func setClosedDisplayMode(enabled: Bool) throws {
        try failIfRequested("closed")
        commands.append("closed:\(enabled)")
        state.closedDisplayModeEnabled = enabled
    }

    func setTriggers(enabled: Bool) throws {
        try failIfRequested("triggers")
        commands.append("triggers:\(enabled)")
        state.triggersEnabled = enabled
    }

    private func failIfRequested(_ command: String) throws {
        if failureCommand == command {
            throw ModeControlError.backend("Injected \(command) failure")
        }
    }
}

final class FakeAssertions: PowerAssertionInspecting {
    var blockers: [String] = []
    var callCount = 0

    func displaySleepBlockingProcesses() throws -> [String] {
        callCount += 1
        return blockers
    }
}

final class FakeScreenLock: ScreenLockPolicyChecking {
    var immediate = true
    var error: Error?

    func hasImmediateScreenLock() throws -> Bool {
        if let error { throw error }
        return immediate
    }
}

final class FakeDisplay: DisplaySleeping {
    var sleepCount = 0
    var error: Error?

    func sleepDisplay() throws {
        if let error { throw error }
        sleepCount += 1
    }
}

final class MemoryStore: ModeStateStoring {
    var lastRequestedMode: OperatingMode = .off
    var ownedSessionSignature: OwnedSessionSignature?
    var closedDisplayReadinessPassed = true
    var launchAtLoginPromptWasShown = false
}

final class FixedClock: TimeProviding {
    var now: Date
    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.now = now }
}

struct Fixture {
    let amphetamine = FakeAmphetamine()
    let assertions = FakeAssertions()
    let screenLock = FakeScreenLock()
    let display = FakeDisplay()
    let store = MemoryStore()
    let clock = FixedClock()

    var controller: ModeController {
        ModeController(
            amphetamine: amphetamine,
            assertions: assertions,
            screenLock: screenLock,
            display: display,
            store: store,
            clock: clock
        )
    }
}
