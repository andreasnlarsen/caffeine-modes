import Foundation

public enum OperatingMode: Equatable, Codable, Sendable {
    case off
    case work
    case night
    case travel(durationMinutes: Int, expiresAt: Date)
    case custom

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .work: "Work"
        case .night: "Night"
        case .travel: "Travel"
        case .custom: "Custom"
        }
    }

    public var travelDurationMinutes: Int? {
        guard case let .travel(durationMinutes, _) = self else { return nil }
        return durationMinutes
    }

    public static let allowedTravelDurations = [30, 60, 90, 120]

    public var isAwayMode: Bool {
        switch self {
        case .night, .travel: true
        case .off, .work, .custom: false
        }
    }
}

public enum PostUnlockMode: String, Equatable, Codable, Sendable {
    case off
    case work
}

public enum LidState: Equatable, Sendable {
    case open
    case closed
    case unavailable
}

public enum ControlHealth: String, Equatable, Codable, Sendable {
    case ready
    case amphetamineMissing
    case unsupportedVersion
    case automationDenied
    case setupIncomplete
    case conflicted
    case backendMismatch
}

public struct AmphetamineState: Equatable, Codable, Sendable {
    public var sessionIsActive: Bool
    public var displaySleepAllowed: Bool
    public var closedDisplayModeEnabled: Bool
    public var triggersEnabled: Bool
    public var sessionTimeRemainingSeconds: Int

    public init(
        sessionIsActive: Bool,
        displaySleepAllowed: Bool,
        closedDisplayModeEnabled: Bool,
        triggersEnabled: Bool,
        sessionTimeRemainingSeconds: Int = 0
    ) {
        self.sessionIsActive = sessionIsActive
        self.displaySleepAllowed = displaySleepAllowed
        self.closedDisplayModeEnabled = closedDisplayModeEnabled
        self.triggersEnabled = triggersEnabled
        self.sessionTimeRemainingSeconds = sessionTimeRemainingSeconds
    }

    public static let inactive = AmphetamineState(
        sessionIsActive: false,
        displaySleepAllowed: true,
        closedDisplayModeEnabled: false,
        triggersEnabled: false,
        sessionTimeRemainingSeconds: -3
    )
}

public enum OwnedSessionPurpose: String, Equatable, Codable, Sendable {
    case activeMode
    case pendingCleanup
    case readinessTest
}

public struct OwnedSessionSignature: Equatable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case mode
        case startedAt
        case purpose
        case expectedState
        case schemaVersion
    }

    private static let currentSchemaVersion = 2

    public var id: UUID
    public var mode: OperatingMode
    public var startedAt: Date
    public var purpose: OwnedSessionPurpose
    public var expectedState: AmphetamineState?
    public private(set) var schemaVersion: Int

    public var usesLegacyProjectionFormat: Bool {
        schemaVersion < Self.currentSchemaVersion
    }

    public init(
        id: UUID = UUID(),
        mode: OperatingMode,
        startedAt: Date,
        purpose: OwnedSessionPurpose = .activeMode,
        expectedState: AmphetamineState? = nil
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.purpose = purpose
        self.expectedState = expectedState
        schemaVersion = Self.currentSchemaVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mode = try container.decode(OperatingMode.self, forKey: .mode)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        purpose = try container.decodeIfPresent(OwnedSessionPurpose.self, forKey: .purpose)
            ?? .activeMode
        expectedState = try container.decodeIfPresent(AmphetamineState.self, forKey: .expectedState)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

public struct ModeSnapshot: Equatable, Sendable {
    public var requestedMode: OperatingMode
    public var observedState: AmphetamineState?
    public var ownershipMarker: OwnedSessionSignature?
    public var health: ControlHealth
    public var blockingProcesses: [String]
    public var detail: String?
    public var requiresPostUnlockChoice: Bool

    public init(
        requestedMode: OperatingMode,
        observedState: AmphetamineState?,
        ownershipMarker: OwnedSessionSignature?,
        health: ControlHealth,
        blockingProcesses: [String] = [],
        detail: String? = nil,
        requiresPostUnlockChoice: Bool = false
    ) {
        self.requestedMode = requestedMode
        self.observedState = observedState
        self.ownershipMarker = ownershipMarker
        self.health = health
        self.blockingProcesses = blockingProcesses
        self.detail = detail
        self.requiresPostUnlockChoice = requiresPostUnlockChoice
    }
}

public struct PowerAssertionReport: Equatable, Sendable {
    public var displaySleepBlockingProcesses: [String]
    public var systemSleepBlockingProcesses: [String]
    public var diskIdleBlockingProcesses: [String]

    public init(
        displaySleepBlockingProcesses: [String] = [],
        systemSleepBlockingProcesses: [String] = [],
        diskIdleBlockingProcesses: [String] = []
    ) {
        self.displaySleepBlockingProcesses = displaySleepBlockingProcesses
        self.systemSleepBlockingProcesses = systemSleepBlockingProcesses
        self.diskIdleBlockingProcesses = diskIdleBlockingProcesses
    }

    public static let empty = PowerAssertionReport()
}

public enum PowerAssertionCategory: Equatable, Sendable {
    case displaySleep
    case systemSleep
    case diskIdle
}

public enum PowerAssertionClassifier {
    public static func category(forType type: String) -> PowerAssertionCategory? {
        switch type {
        case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion":
            .displaySleep
        case "PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventSystemSleep",
             "NetworkClientActive":
            .systemSleep
        case "PreventDiskIdle":
            .diskIdle
        default:
            nil
        }
    }
}

public enum SetupCheckState: Equatable, Sendable {
    case passed
    case needsAction
    case unchecked(reason: String?)
}

public struct PowerProtectStatus: Equatable, Sendable {
    public var isRequired: Bool
    public var isInstalled: Bool

    public init(isRequired: Bool, isInstalled: Bool) {
        self.isRequired = isRequired
        self.isInstalled = isInstalled
    }

    public var isReady: Bool {
        !isRequired || isInstalled
    }
}

public struct SetupReport: Equatable, Sendable {
    public var amphetamineInstalled: Bool
    public var supportedVersion: Bool
    public var detectedVersion: String?
    public var automation: SetupCheckState
    public var triggers: SetupCheckState
    public var screenLock: SetupCheckState
    public var powerProtect: PowerProtectStatus
    public var developerDiagnosticPassed: Bool
    public var developerDiagnosticIsActive: Bool
    public var amphetamineSessionIsActive: Bool?

    public init(
        amphetamineInstalled: Bool,
        supportedVersion: Bool,
        detectedVersion: String? = nil,
        automation: SetupCheckState,
        triggers: SetupCheckState,
        screenLock: SetupCheckState,
        powerProtect: PowerProtectStatus,
        developerDiagnosticPassed: Bool,
        developerDiagnosticIsActive: Bool = false,
        amphetamineSessionIsActive: Bool? = nil
    ) {
        self.amphetamineInstalled = amphetamineInstalled
        self.supportedVersion = supportedVersion
        self.detectedVersion = detectedVersion
        self.automation = automation
        self.triggers = triggers
        self.screenLock = screenLock
        self.powerProtect = powerProtect
        self.developerDiagnosticPassed = developerDiagnosticPassed
        self.developerDiagnosticIsActive = developerDiagnosticIsActive
        self.amphetamineSessionIsActive = amphetamineSessionIsActive
    }

    public var isReady: Bool {
        amphetamineInstalled
            && supportedVersion
            && automation == .passed
            && triggers == .passed
            && screenLock == .passed
            && powerProtect.isReady
    }
}

public enum ModeControlError: Error, Equatable, LocalizedError, Sendable {
    case amphetamineMissing
    case unsupportedVersion(found: String?)
    case automationDenied
    case triggersEnabled
    case screenLockNotImmediate
    case powerProtectMissing
    case openLidToStartWork
    case screenLockStateUnavailable(String)
    case displaySleepBlocked([String])
    case activeSessionRequiresConfirmation
    case sessionStartRequiresConfirmation
    case invalidTravelDuration(Int)
    case operationTimedOut
    case verificationFailed(String)
    case backend(String)

    public var errorDescription: String? {
        switch self {
        case .amphetamineMissing:
            "Amphetamine 5.3.2 or later is required."
        case let .unsupportedVersion(found):
            "Amphetamine 5.3.2 or later is required. Found \(found ?? "an unknown version")."
        case .automationDenied:
            "Automation access to Amphetamine is not available."
        case .triggersEnabled:
            "Disable Amphetamine Triggers before Caffeine Modes takes control."
        case .screenLockNotImmediate:
            "Set Require password after screen saver begins or display is turned off to Immediately."
        case .powerProtectMissing:
            "Install Amphetamine Power Protect before you use Night or Travel."
        case .openLidToStartWork:
            "Open the Mac lid once, then start Work again."
        case let .screenLockStateUnavailable(message):
            message
        case let .displaySleepBlocked(processes):
            "Display sleep is blocked by: \(processes.joined(separator: ", "))."
        case .activeSessionRequiresConfirmation:
            "Amphetamine has an active session. Confirm before Caffeine Modes ends or replaces it."
        case .sessionStartRequiresConfirmation:
            "Confirm before Caffeine Modes starts a new Amphetamine session."
        case let .invalidTravelDuration(minutes):
            "Travel supports only 30, 60, 90, or 120 minutes. Received \(minutes)."
        case .operationTimedOut:
            "The operation did not finish before its safety deadline."
        case let .verificationFailed(message), let .backend(message):
            message
        }
    }
}
