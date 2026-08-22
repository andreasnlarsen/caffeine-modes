import Foundation

public protocol AmphetamineControlling: AnyObject {
    var isInstalled: Bool { get }
    var installedVersion: String? { get }

    func readState(timeout: TimeInterval) throws -> AmphetamineState
    func startInfiniteSession(displaySleepAllowed: Bool, timeout: TimeInterval) throws
    func startTimedSession(minutes: Int, displaySleepAllowed: Bool, timeout: TimeInterval) throws
    func endSession(timeout: TimeInterval) throws
    func setClosedDisplayMode(enabled: Bool, timeout: TimeInterval) throws
    func setTriggers(enabled: Bool, timeout: TimeInterval) throws
}

public protocol PowerAssertionInspecting: AnyObject {
    func inspect(timeout: TimeInterval) throws -> PowerAssertionReport
}

public protocol ScreenLockPolicyChecking: AnyObject {
    func hasImmediateScreenLock(timeout: TimeInterval) throws -> Bool
}

public protocol DisplaySleeping: AnyObject {
    func sleepDisplay(timeout: TimeInterval) throws
}

public protocol ModeStateStoring: AnyObject {
    var lastRequestedMode: OperatingMode { get set }
    var ownedSessionSignature: OwnedSessionSignature? { get set }
    var closedDisplayReadinessPassed: Bool { get set }
    var launchAtLoginPromptWasShown: Bool { get set }
}

public protocol TimeProviding: AnyObject {
    var now: Date { get }
}

public protocol MonotonicTimeProviding: AnyObject {
    var now: TimeInterval { get }
}

public final class SystemMonotonicTimeProvider: MonotonicTimeProviding {
    public init() {}
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

public final class SystemTimeProvider: TimeProviding {
    public init() {}
    public var now: Date { Date() }
}

public protocol ModeControlling: AnyObject {
    func reconcile() -> ModeSnapshot
    func transition(to mode: OperatingMode, replacingActiveSession: Bool) throws -> ModeSnapshot
    func setupReport() -> SetupReport
    func disableTriggers() throws
    func runClosedDisplayReadinessTest(authorizingSessionReplacement: Bool) throws
    func hasActiveSessionForQuit() throws -> Bool
    func endActiveSessionForQuit() throws
}
