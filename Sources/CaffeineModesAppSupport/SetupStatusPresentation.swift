import CaffeineModesCore

public enum SetupRowIndicator: Equatable, Sendable {
    case complete
    case needsAction
    case notChecked
}

public enum SetupRowAction: Equatable, Sendable {
    case getAmphetamine
    case updateAmphetamine
    case openAutomationSettings
    case disableTriggers
    case openLockScreenSettings
    case getPowerProtect
    case openAmphetamine

    public var title: String {
        switch self {
        case .getAmphetamine: "Get Amphetamine"
        case .updateAmphetamine: "Update Amphetamine"
        case .openAutomationSettings: "Open Settings"
        case .disableTriggers: "Turn Off Triggers"
        case .openLockScreenSettings: "Open Settings"
        case .getPowerProtect: "Get Power Protect"
        case .openAmphetamine: "Open Amphetamine"
        }
    }
}

public struct SetupRowPresentation: Equatable, Sendable {
    public let title: String
    public let indicator: SetupRowIndicator
    public let stateDescription: String
    public let detail: String
    public let action: SetupRowAction?
    public let actionIsEnabled: Bool
}

public struct DeveloperDiagnosticAvailability: Equatable, Sendable {
    public let isEnabled: Bool
    public let blockedStatus: String?

    public init(isEnabled: Bool, blockedStatus: String?) {
        self.isEnabled = isEnabled
        self.blockedStatus = blockedStatus
    }

    public static func make(report: SetupReport?) -> DeveloperDiagnosticAvailability {
        guard let report else {
            return DeveloperDiagnosticAvailability(
                isEnabled: false,
                blockedStatus: "Check Amphetamine first"
            )
        }
        if report.developerDiagnosticIsActive {
            return DeveloperDiagnosticAvailability(isEnabled: false, blockedStatus: nil)
        }
        guard report.amphetamineInstalled,
              report.supportedVersion,
              report.automation == .passed,
              report.triggers == .passed,
              !report.powerProtect.isRequired || report.powerProtect.isInstalled,
              report.batteryProtection.isReady
        else {
            return DeveloperDiagnosticAvailability(
                isEnabled: false,
                blockedStatus: "Complete Setup first"
            )
        }
        switch report.amphetamineSessionIsActive {
        case false:
            return DeveloperDiagnosticAvailability(isEnabled: true, blockedStatus: nil)
        case true:
            return DeveloperDiagnosticAvailability(isEnabled: false, blockedStatus: "Turn Off first")
        case nil:
            return DeveloperDiagnosticAvailability(
                isEnabled: false,
                blockedStatus: "Check Amphetamine first"
            )
        }
    }
}

public struct SetupStatusPresentation: Equatable, Sendable {
    public static let intro = "Complete each item once. Caffeine Modes does not need Accessibility access."
    public static let coreGroupTitle = "For all modes"
    public static let displaySleepGroupTitle = "For Night and Travel"

    public let amphetamine: SetupRowPresentation
    public let automation: SetupRowPresentation
    public let triggers: SetupRowPresentation
    public let screenLock: SetupRowPresentation
    public let powerProtect: SetupRowPresentation
    public let batteryProtection: SetupRowPresentation
    public let summary: String
    public let isComplete: Bool

    public var rows: [SetupRowPresentation] {
        [amphetamine, automation, triggers, screenLock, powerProtect, batteryProtection]
    }

    public static let checking = SetupStatusPresentation(
        amphetamine: row(title: RowTitle.amphetamine, indicator: .notChecked, detail: checkingDetail),
        automation: row(title: RowTitle.automation, indicator: .notChecked, detail: checkingDetail),
        triggers: row(title: RowTitle.triggers, indicator: .notChecked, detail: checkingDetail),
        screenLock: row(title: RowTitle.screenLock, indicator: .notChecked, detail: checkingDetail),
        powerProtect: row(title: RowTitle.powerProtect, indicator: .notChecked, detail: checkingDetail),
        batteryProtection: row(
            title: RowTitle.batteryProtection,
            indicator: .notChecked,
            detail: checkingDetail
        ),
        summary: "Checking…",
        isComplete: false
    )

    public static func make(
        report: SetupReport,
        triggersActionFailure: String? = nil
    ) -> SetupStatusPresentation {
        let rows = [
            amphetamineRow(report: report),
            automationRow(report: report),
            triggersRow(report: report, actionFailure: triggersActionFailure),
            screenLockRow(report: report),
            powerProtectRow(report: report),
            batteryProtectionRow(report: report)
        ]
        return SetupStatusPresentation(
            amphetamine: rows[0],
            automation: rows[1],
            triggers: rows[2],
            screenLock: rows[3],
            powerProtect: rows[4],
            batteryProtection: rows[5],
            summary: report.isReady ? "Ready" : "Setup needs attention",
            isComplete: report.isReady
        )
    }

    private enum RowTitle {
        static let amphetamine = "Amphetamine 5.3.2 or later"
        static let automation = "Automation access"
        static let triggers = "Amphetamine Triggers off"
        static let screenLock = "Lock immediately"
        static let powerProtect = "Amphetamine Power Protect"
        static let batteryProtection = "Amphetamine battery protection"
    }

    private static let checkingDetail = "Checking…"

    private static func amphetamineRow(report: SetupReport) -> SetupRowPresentation {
        guard report.amphetamineInstalled else {
            return row(
                title: RowTitle.amphetamine,
                indicator: .needsAction,
                detail: "Install Amphetamine to use Caffeine Modes.",
                action: .getAmphetamine
            )
        }
        guard report.supportedVersion else {
            return row(
                title: RowTitle.amphetamine,
                indicator: .needsAction,
                detail: "Version \(report.detectedVersion ?? "unknown") is installed. Update to 5.3.2 or later.",
                action: .updateAmphetamine
            )
        }
        return row(
            title: RowTitle.amphetamine,
            indicator: .complete,
            detail: "Version \(report.detectedVersion ?? "5.3.2 or later") is installed."
        )
    }

    private static func automationRow(report: SetupReport) -> SetupRowPresentation {
        switch report.automation {
        case .passed:
            row(
                title: RowTitle.automation,
                indicator: .complete,
                detail: "Caffeine Modes can control Amphetamine."
            )
        case .needsAction:
            row(
                title: RowTitle.automation,
                indicator: .needsAction,
                detail: "Allow Caffeine Modes to control Amphetamine.",
                action: .openAutomationSettings
            )
        case let .unchecked(reason):
            row(
                title: RowTitle.automation,
                indicator: .notChecked,
                detail: reason ?? "Check Amphetamine first."
            )
        }
    }

    private static func triggersRow(
        report: SetupReport,
        actionFailure: String?
    ) -> SetupRowPresentation {
        if let actionFailure {
            return row(
                title: RowTitle.triggers,
                indicator: .needsAction,
                detail: actionFailure,
                action: .disableTriggers,
                actionIsEnabled: report.automation == .passed
            )
        }
        switch report.triggers {
        case .passed:
            return row(
                title: RowTitle.triggers,
                indicator: .complete,
                detail: "Triggers are off."
            )
        case .needsAction:
            return row(
                title: RowTitle.triggers,
                indicator: .needsAction,
                detail: "Turn off Triggers to prevent mode conflicts.",
                action: .disableTriggers,
                actionIsEnabled: report.automation == .passed
            )
        case let .unchecked(reason):
            return row(
                title: RowTitle.triggers,
                indicator: .notChecked,
                detail: reason ?? "Check Automation access first."
            )
        }
    }

    private static func screenLockRow(report: SetupReport) -> SetupRowPresentation {
        switch report.screenLock {
        case .passed:
            return row(
                title: RowTitle.screenLock,
                indicator: .complete,
                detail: "Your Mac locks when displays turn off."
            )
        case .needsAction:
            return row(
                title: RowTitle.screenLock,
                indicator: .needsAction,
                detail: "Set Require password to Immediately.",
                action: .openLockScreenSettings
            )
        case let .unchecked(reason):
            return row(
                title: RowTitle.screenLock,
                indicator: .notChecked,
                detail: reason ?? "The lock setting was not checked."
            )
        }
    }

    private static func powerProtectRow(report: SetupReport) -> SetupRowPresentation {
        if !report.powerProtect.isRequired {
            return row(
                title: RowTitle.powerProtect,
                indicator: .complete,
                detail: "Power Protect is not needed on this Mac."
            )
        }
        guard report.powerProtect.isInstalled else {
            return row(
                title: RowTitle.powerProtect,
                indicator: .needsAction,
                detail: "Install it so Night and Travel survive a power or display disconnect.",
                action: .getPowerProtect
            )
        }
        return row(
            title: RowTitle.powerProtect,
            indicator: .complete,
            detail: "Power Protect is installed."
        )
    }

    private static func batteryProtectionRow(report: SetupReport) -> SetupRowPresentation {
        guard report.amphetamineInstalled else {
            return row(
                title: RowTitle.batteryProtection,
                indicator: .notChecked,
                detail: "Install Amphetamine first."
            )
        }
        guard report.supportedVersion else {
            return row(
                title: RowTitle.batteryProtection,
                indicator: .notChecked,
                detail: "Update Amphetamine first."
            )
        }
        let status = report.batteryProtection
        switch status.observation {
        case .matches:
            return row(
                title: RowTitle.batteryProtection,
                indicator: .complete,
                detail: "Amphetamine ends sessions at \(status.requirement.thresholdPercent)% on battery."
            )
        case .mismatch:
            return row(
                title: RowTitle.batteryProtection,
                indicator: .needsAction,
                detail: "In Session Defaults: end at \(status.requirement.thresholdPercent)%, no prompt, ignore on power.",
                action: .openAmphetamine
            )
        case .unavailable:
            return row(
                title: RowTitle.batteryProtection,
                indicator: .needsAction,
                detail: "Caffeine Modes cannot read Amphetamine’s Session Defaults.",
                action: .openAmphetamine
            )
        case .notRequired:
            return row(
                title: RowTitle.batteryProtection,
                indicator: .notChecked,
                detail: "Not required. Change this in General."
            )
        }
    }

    private static func row(
        title: String,
        indicator: SetupRowIndicator,
        detail: String,
        action: SetupRowAction? = nil,
        actionIsEnabled: Bool = true
    ) -> SetupRowPresentation {
        SetupRowPresentation(
            title: title,
            indicator: indicator,
            stateDescription: stateDescription(indicator),
            detail: detail,
            action: action,
            actionIsEnabled: action == nil ? false : actionIsEnabled
        )
    }

    private static func stateDescription(_ indicator: SetupRowIndicator) -> String {
        switch indicator {
        case .complete: "Complete"
        case .needsAction: "Needs action"
        case .notChecked: "Not checked"
        }
    }
}
