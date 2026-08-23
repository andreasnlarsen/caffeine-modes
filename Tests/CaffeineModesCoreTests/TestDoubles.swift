import CaffeineModesCore
import Foundation

final class FakeAmphetamine: AmphetamineControlling {
    var isInstalled = true
    var installedVersion: String? = "5.3.2"
    var state: AmphetamineState = .inactive {
        didSet {
            if !state.sessionIsActive {
                inactiveClosedDisplayDefaultEnabled = state.closedDisplayModeEnabled
            }
        }
    }
    var inactiveClosedDisplayDefaultEnabled = false
    var commands: [String] = []
    var readError: Error?
    var failureCommand: String?
    var errorAfterMutationCommand: String?
    var timeoutAfterMutationCommand: String?
    var refuseToEnd = false
    var onStartTimedSession: (() -> Void)?
    var forcedTimedSessionRemainingSeconds: Int?
    var readCount = 0
    var onRead: ((Int) -> Void)?
    var receivedTimeouts: [TimeInterval] = []
    var onOperation: ((TimeInterval) -> Void)?

    func readState(timeout: TimeInterval) throws -> AmphetamineState {
        beginOperation(timeout: timeout)
        commands.append("read")
        readCount += 1
        onRead?(readCount)
        if let readError { throw readError }
        return state
    }

    func startInfiniteSession(displaySleepAllowed: Bool, timeout: TimeInterval) throws {
        beginOperation(timeout: timeout)
        try failIfRequested("startInfinite")
        commands.append("startInfinite:\(displaySleepAllowed)")
        state.sessionIsActive = true
        state.displaySleepAllowed = displaySleepAllowed
        state.sessionTimeRemainingSeconds = 0
        try errorAfterMutationIfRequested("startInfinite")
        try timeoutAfterMutationIfRequested("startInfinite")
    }

    func startTimedSession(minutes: Int, displaySleepAllowed: Bool, timeout: TimeInterval) throws {
        beginOperation(timeout: timeout)
        try failIfRequested("startTimed")
        commands.append("startTimed:\(minutes):\(displaySleepAllowed)")
        state.sessionIsActive = true
        state.displaySleepAllowed = displaySleepAllowed
        state.sessionTimeRemainingSeconds = forcedTimedSessionRemainingSeconds ?? minutes * 60
        onStartTimedSession?()
        try errorAfterMutationIfRequested("startTimed")
        try timeoutAfterMutationIfRequested("startTimed")
    }

    func endSession(timeout: TimeInterval) throws {
        beginOperation(timeout: timeout)
        try failIfRequested("end")
        commands.append("end")
        if !refuseToEnd {
            state = AmphetamineState(
                sessionIsActive: false,
                displaySleepAllowed: true,
                closedDisplayModeEnabled: inactiveClosedDisplayDefaultEnabled,
                triggersEnabled: state.triggersEnabled,
                sessionTimeRemainingSeconds: -3
            )
        }
        try errorAfterMutationIfRequested("end")
        try timeoutAfterMutationIfRequested("end")
    }

    func setClosedDisplayMode(enabled: Bool, timeout: TimeInterval) throws {
        beginOperation(timeout: timeout)
        try failIfRequested("closed")
        commands.append("closed:\(enabled)")
        state.closedDisplayModeEnabled = enabled
        try errorAfterMutationIfRequested("closed")
        try timeoutAfterMutationIfRequested("closed")
    }

    func setTriggers(enabled: Bool, timeout: TimeInterval) throws {
        beginOperation(timeout: timeout)
        try failIfRequested("triggers")
        commands.append("triggers:\(enabled)")
        state.triggersEnabled = enabled
        try errorAfterMutationIfRequested("triggers")
        try timeoutAfterMutationIfRequested("triggers")
    }

    private func failIfRequested(_ command: String) throws {
        if failureCommand == command {
            throw ModeControlError.backend("Injected \(command) failure")
        }
    }

    private func timeoutAfterMutationIfRequested(_ command: String) throws {
        if timeoutAfterMutationCommand == command {
            throw ModeControlError.operationTimedOut
        }
    }

    private func errorAfterMutationIfRequested(_ command: String) throws {
        if errorAfterMutationCommand == command {
            throw ModeControlError.backend("Injected post-mutation \(command) failure")
        }
    }

    private func beginOperation(timeout: TimeInterval) {
        receivedTimeouts.append(timeout)
        onOperation?(timeout)
    }
}

final class FakeAssertions: PowerAssertionInspecting {
    var report = PowerAssertionReport.empty
    var blockers: [String] {
        get { report.displaySleepBlockingProcesses }
        set { report.displaySleepBlockingProcesses = newValue }
    }
    var callCount = 0
    var receivedTimeouts: [TimeInterval] = []
    var onOperation: ((TimeInterval) -> Void)?
    var error: Error?

    func inspect(timeout: TimeInterval) throws -> PowerAssertionReport {
        callCount += 1
        receivedTimeouts.append(timeout)
        onOperation?(timeout)
        if let error { throw error }
        return report
    }
}

final class FakeScreenLock: ScreenLockPolicyChecking {
    var immediate = true
    var error: Error?
    var callCount = 0
    var receivedTimeouts: [TimeInterval] = []
    var onOperation: ((TimeInterval) -> Void)?

    func hasImmediateScreenLock(timeout: TimeInterval) throws -> Bool {
        callCount += 1
        receivedTimeouts.append(timeout)
        onOperation?(timeout)
        if let error { throw error }
        return immediate
    }
}

final class FakeScreenLockState: ScreenLockStateInspecting {
    var isLocked = true
    var error: Error?
    var callCount = 0

    func screenIsLocked() throws -> Bool {
        callCount += 1
        if let error { throw error }
        return isLocked
    }
}

final class FakePowerProtect: PowerProtectInspecting {
    var status = PowerProtectStatus(isRequired: true, isInstalled: true)

    func inspect() -> PowerProtectStatus {
        status
    }
}

final class FakeClamshellContext: ClamshellContextInspecting {
    var lidState: LidState = .open
    var externalPowerConnected: Bool?
    var activeExternalDisplayPresent: Bool?
    var queuedContexts: [ClamshellContext] = []
    private(set) var callCount = 0

    func currentContext() -> ClamshellContext {
        callCount += 1
        if !queuedContexts.isEmpty {
            return queuedContexts.removeFirst()
        }
        return ClamshellContext(
            lidState: lidState,
            externalPowerConnected: externalPowerConnected,
            activeExternalDisplayPresent: activeExternalDisplayPresent
        )
    }
}

final class FakeDisplay: DisplaySleeping {
    var sleepCount = 0
    var error: Error?
    var onSleep: (() -> Void)?

    func sleepDisplay(timeout: TimeInterval) throws {
        onSleep?()
        if let error { throw error }
        sleepCount += 1
    }
}

final class MemoryStore: ModeStateStoring {
    var lastRequestedMode: OperatingMode = .off
    var ownedSessionSignature: OwnedSessionSignature?
    var closedDisplayReadinessPassed = true
    var launchAtLoginPromptWasShown = false
    var postUnlockMode: PostUnlockMode = .off
}

final class FixedClock: TimeProviding {
    var now: Date
    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.now = now }
}

final class FixedMonotonicClock: MonotonicTimeProviding {
    var now: TimeInterval = 0
}

struct Fixture {
    let amphetamine = FakeAmphetamine()
    let assertions = FakeAssertions()
    let screenLock = FakeScreenLock()
    let screenLockState = FakeScreenLockState()
    let powerProtect = FakePowerProtect()
    let clamshellContext = FakeClamshellContext()
    let display = FakeDisplay()
    let store = MemoryStore()
    let clock = FixedClock()
    let monotonicClock = FixedMonotonicClock()

    var controller: ModeController {
        ModeController(
            amphetamine: amphetamine,
            assertions: assertions,
            screenLock: screenLock,
            screenLockState: screenLockState,
            powerProtect: powerProtect,
            clamshellContext: clamshellContext,
            display: display,
            store: store,
            clock: clock,
            monotonicClock: monotonicClock
        )
    }
}
