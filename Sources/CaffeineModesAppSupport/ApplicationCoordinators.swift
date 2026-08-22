import CaffeineModesCore

public enum ActiveSessionQuitChoice: Equatable, Sendable {
    case endAndQuit
    case leaveRunning
    case cancel
}

public enum UninspectedSessionQuitChoice: Equatable, Sendable {
    case leaveUnchangedAndQuit
    case cancel
}

public enum ApplicationTerminationDecision: Equatable, Sendable {
    case terminateNow
    case terminateCancel
}

public enum ApplicationTerminationRequest: Equatable, Sendable {
    case user
    case system
}

public enum ApplicationTerminationClassifier {
    private static let shutdownReason: UInt32 = 0x7368_7574 // 'shut'
    private static let restartReason: UInt32 = 0x7265_7374 // 'rest'
    private static let logoutReason: UInt32 = 0x726c_676f // 'rlgo'

    public static func request(
        systemWillPowerOff: Bool,
        appleEventQuitReason: UInt32?
    ) -> ApplicationTerminationRequest {
        guard !systemWillPowerOff else { return .system }
        switch appleEventQuitReason {
        case shutdownReason, restartReason, logoutReason:
            return .system
        default:
            return .user
        }
    }
}

public struct ActiveSessionQuitConfirmationPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let endButtonTitle: String
    public let leaveButtonTitle: String
    public let cancelButtonTitle: String

    public init(
        title: String,
        message: String,
        endButtonTitle: String,
        leaveButtonTitle: String,
        cancelButtonTitle: String
    ) {
        self.title = title
        self.message = message
        self.endButtonTitle = endButtonTitle
        self.leaveButtonTitle = leaveButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
    }

    public static let activeSession = ActiveSessionQuitConfirmationPresentation(
        title: "Quit Caffeine Modes?",
        message: "Amphetamine has an active session. Choose Turn Off and Quit to end it, or leave it running.",
        endButtonTitle: "Turn Off and Quit",
        leaveButtonTitle: "Leave Session Running",
        cancelButtonTitle: "Cancel"
    )
}

public struct UninspectedSessionQuitConfirmationPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let leaveButtonTitle: String
    public let cancelButtonTitle: String

    public init(
        title: String,
        message: String,
        leaveButtonTitle: String,
        cancelButtonTitle: String
    ) {
        self.title = title
        self.message = message
        self.leaveButtonTitle = leaveButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
    }

    public static let inspectionFailed = UninspectedSessionQuitConfirmationPresentation(
        title: "Quit Without Checking Amphetamine?",
        message: "Caffeine Modes could not check the Amphetamine session. You can quit without changing Amphetamine, or cancel and keep Caffeine Modes open.",
        leaveButtonTitle: "Leave Amphetamine Unchanged and Quit",
        cancelButtonTitle: "Cancel"
    )
}

public enum ModeSelectionConfirmation: Equatable, Sendable {
    case start(OperatingMode)
    case replaceActiveSession(OperatingMode)

    public var presentation: ModeSelectionConfirmationPresentation {
        switch self {
        case let .start(mode):
            let targetName = mode.confirmationDisplayName
            let effect: String
            switch mode {
            case .night, .travel:
                effect = " After Amphetamine confirms \(targetName), the display will sleep and your Mac will lock."
            default:
                effect = ""
            }
            return ModeSelectionConfirmationPresentation(
                title: "Start \(targetName)?",
                message: "A new Amphetamine session can replace another session that appears before the command finishes. Continue only if you accept that replacement.\(effect)",
                confirmButtonTitle: "Start \(targetName)"
            )
        case .replaceActiveSession(.off):
            return ModeSelectionConfirmationPresentation(
                title: "Turn Off the Current Amphetamine Session?",
                message: "Amphetamine does not provide a stable session identity. Continue only if you want to end the active session.",
                confirmButtonTitle: "Turn Off"
            )
        case let .replaceActiveSession(mode):
            let targetName = mode.confirmationDisplayName
            let effect: String
            switch mode {
            case .night, .travel:
                effect = " After Amphetamine confirms \(targetName), the display will sleep and your Mac will lock."
            default:
                effect = ""
            }
            return ModeSelectionConfirmationPresentation(
                title: "Replace the Current Session and Start \(targetName)?",
                message: "Amphetamine does not provide a stable session identity. Continue only if you want to replace the active session and start \(targetName).\(effect)",
                confirmButtonTitle: "Start \(targetName)"
            )
        }
    }
}

private extension OperatingMode {
    var confirmationDisplayName: String {
        guard case let .travel(durationMinutes, _) = self else { return displayName }
        return "Travel for \(durationMinutes) Minutes"
    }
}

public struct ModeSelectionConfirmationPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let confirmButtonTitle: String

    public init(title: String, message: String, confirmButtonTitle: String) {
        self.title = title
        self.message = message
        self.confirmButtonTitle = confirmButtonTitle
    }
}

@MainActor
public final class ApplicationTerminationCoordinator {
    private let hasActiveSession: () throws -> Bool
    private let endActiveSession: () throws -> Void
    private let choose: () -> ActiveSessionQuitChoice
    private let chooseWhenInspectionFails: () -> UninspectedSessionQuitChoice

    public init(
        hasActiveSession: @escaping () throws -> Bool,
        endActiveSession: @escaping () throws -> Void,
        choose: @escaping () -> ActiveSessionQuitChoice,
        chooseWhenInspectionFails: @escaping () -> UninspectedSessionQuitChoice = { .cancel }
    ) {
        self.hasActiveSession = hasActiveSession
        self.endActiveSession = endActiveSession
        self.choose = choose
        self.chooseWhenInspectionFails = chooseWhenInspectionFails
    }

    public func decision(
        for request: ApplicationTerminationRequest = .user
    ) throws -> ApplicationTerminationDecision {
        guard request == .user else { return .terminateNow }
        let sessionIsActive: Bool
        do {
            sessionIsActive = try hasActiveSession()
        } catch {
            switch chooseWhenInspectionFails() {
            case .leaveUnchangedAndQuit:
                return .terminateNow
            case .cancel:
                return .terminateCancel
            }
        }
        guard sessionIsActive else { return .terminateNow }
        switch choose() {
        case .endAndQuit:
            try endActiveSession()
            return .terminateNow
        case .leaveRunning:
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
    }
}

@MainActor
public final class ApplicationTerminationRouter {
    private let coordinator: ApplicationTerminationCoordinator

    public init(coordinator: ApplicationTerminationCoordinator) {
        self.coordinator = coordinator
    }

    public func decision(
        for request: ApplicationTerminationRequest = .user
    ) throws -> ApplicationTerminationDecision {
        try coordinator.decision(for: request)
    }
}

@MainActor
public final class ModeSelectionCoordinator {
    private let transition: (OperatingMode, Bool) async throws -> ModeSnapshot
    private let confirm: (ModeSelectionConfirmation) -> Bool

    public init(
        transition: @escaping (OperatingMode, Bool) async throws -> ModeSnapshot,
        confirm: @escaping (ModeSelectionConfirmation) -> Bool
    ) {
        self.transition = transition
        self.confirm = confirm
    }

    public func select(_ mode: OperatingMode) async throws -> ModeSnapshot? {
        do {
            return try await transition(mode, false)
        } catch ModeControlError.activeSessionRequiresConfirmation {
            guard confirm(.replaceActiveSession(mode)) else { return nil }
            return try await transition(mode, true)
        } catch ModeControlError.sessionStartRequiresConfirmation {
            guard confirm(.start(mode)) else { return nil }
            return try await transition(mode, true)
        }
    }
}

public struct MenuActivityPolicy: Equatable, Sendable {
    public enum MenuOpenBehavior: Equatable, Sendable {
        case refreshStatus
        case showSetupBusy
        case preserveCurrentStatus
    }

    public let setupIsBusy: Bool
    public let transitionIsInProgress: Bool
    public let refreshIsInProgress: Bool

    public init(
        setupIsBusy: Bool,
        transitionIsInProgress: Bool,
        refreshIsInProgress: Bool
    ) {
        self.setupIsBusy = setupIsBusy
        self.transitionIsInProgress = transitionIsInProgress
        self.refreshIsInProgress = refreshIsInProgress
    }

    public var modesAreEnabled: Bool {
        !setupIsBusy && !transitionIsInProgress
    }

    public var quitIsEnabled: Bool {
        modesAreEnabled && !refreshIsInProgress
    }

    public var hasControllerWorkInProgress: Bool {
        setupIsBusy || transitionIsInProgress || refreshIsInProgress
    }

    public var acceptsRefreshResults: Bool {
        !setupIsBusy && !transitionIsInProgress
    }

    public var menuOpenBehavior: MenuOpenBehavior {
        if setupIsBusy { return .showSetupBusy }
        if transitionIsInProgress { return .preserveCurrentStatus }
        return .refreshStatus
    }
}

public struct RefreshRequestCoordinator: Sendable {
    public private(set) var isInProgress = false
    private var retryIsPending = false

    public init() {}

    public mutating func request(blocked: Bool) -> Bool {
        guard !blocked, !isInProgress else {
            retryIsPending = true
            return false
        }
        retryIsPending = false
        isInProgress = true
        return true
    }

    public mutating func finish() -> Bool {
        isInProgress = false
        let shouldRetry = retryIsPending
        retryIsPending = false
        return shouldRetry
    }
}

public struct SetupCompletionCoordinator: Sendable {
    private var setupIsComplete = false
    private var completionWasDelivered = false
    private var completionIsPendingForRefresh = false

    public init() {}

    public mutating func update(isComplete: Bool) {
        setupIsComplete = isComplete
    }

    public mutating func beginRefresh() {
        setupIsComplete = false
    }

    public mutating func noteCloseDuringRefresh() {
        completionIsPendingForRefresh = true
    }

    public mutating func consumeCompletionAfterRefresh() -> Bool {
        guard completionIsPendingForRefresh else { return false }
        completionIsPendingForRefresh = false
        return consumeCompletionForClose()
    }

    public mutating func consumeCompletionForClose() -> Bool {
        guard setupIsComplete, !completionWasDelivered else { return false }
        completionWasDelivered = true
        return true
    }
}
