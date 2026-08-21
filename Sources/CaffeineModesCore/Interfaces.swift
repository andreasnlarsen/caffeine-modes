import Foundation

public protocol AmphetamineControlling: AnyObject {
    var isInstalled: Bool { get }
    var installedVersion: String? { get }

    func readState() throws -> AmphetamineState
    func startInfiniteSession(displaySleepAllowed: Bool) throws
    func startTimedSession(minutes: Int, displaySleepAllowed: Bool) throws
    func endSession() throws
    func setClosedDisplayMode(enabled: Bool) throws
    func setTriggers(enabled: Bool) throws
}

public protocol PowerAssertionInspecting: AnyObject {
    func displaySleepBlockingProcesses() throws -> [String]
}

public protocol ScreenLockPolicyChecking: AnyObject {
    func hasImmediateScreenLock() throws -> Bool
}

public protocol DisplaySleeping: AnyObject {
    func sleepDisplay() throws
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

public final class SystemTimeProvider: TimeProviding {
    public init() {}
    public var now: Date { Date() }
}

public protocol ModeControlling: AnyObject {
    func reconcile() -> ModeSnapshot
    func transition(to mode: OperatingMode, replacingUnownedSession: Bool) throws -> ModeSnapshot
    func setupReport() -> SetupReport
    func disableTriggers() throws
    func runClosedDisplayReadinessTest() throws
    func prepareToQuit() throws
}
