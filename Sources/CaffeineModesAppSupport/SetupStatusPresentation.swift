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
    case runClosedLidCheck

    public var title: String {
        switch self {
        case .getAmphetamine: "Get Amphetamine"
        case .updateAmphetamine: "Update Amphetamine"
        case .openAutomationSettings: "Open Automation Settings"
        case .disableTriggers: "Disable Triggers"
        case .openLockScreenSettings: "Open Lock Screen Settings"
        case .runClosedLidCheck: "Run Check"
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

public struct SetupStatusPresentation: Equatable, Sendable {
    public static let intro = "Work needs Amphetamine, Automation access, and Triggers turned off. Night and Travel also need immediate screen locking and the closed-lid setup check. Caffeine Modes never asks for Accessibility access."
    public static let coreGroupTitle = "Needed for Work, Night, and Travel"
    public static let displaySleepGroupTitle = "Needed for Night and Travel"

    public let amphetamine: SetupRowPresentation
    public let automation: SetupRowPresentation
    public let triggers: SetupRowPresentation
    public let screenLock: SetupRowPresentation
    public let closedLid: SetupRowPresentation
    public let summary: String
    public let isComplete: Bool

    public var rows: [SetupRowPresentation] {
        [amphetamine, automation, triggers, screenLock, closedLid]
    }

    public static let checking = SetupStatusPresentation(
        amphetamine: row(title: RowTitle.amphetamine, indicator: .notChecked, detail: checkingDetail),
        automation: row(title: RowTitle.automation, indicator: .notChecked, detail: checkingDetail),
        triggers: row(title: RowTitle.triggers, indicator: .notChecked, detail: checkingDetail),
        screenLock: row(title: RowTitle.screenLock, indicator: .notChecked, detail: checkingDetail),
        closedLid: row(title: RowTitle.closedLid, indicator: .notChecked, detail: checkingDetail),
        summary: "Checking…",
        isComplete: false
    )

    public static func make(
        report: SetupReport,
        triggersActionFailure: String? = nil,
        closedLidActionFailure: String? = nil
    ) -> SetupStatusPresentation {
        let rows = [
            amphetamineRow(report: report),
            automationRow(report: report),
            triggersRow(report: report, actionFailure: triggersActionFailure),
            screenLockRow(report: report),
            closedLidRow(report: report, actionFailure: closedLidActionFailure)
        ]
        let completeCount = rows.filter { $0.indicator == .complete }.count
        let isComplete = report.isReady
        return SetupStatusPresentation(
            amphetamine: rows[0],
            automation: rows[1],
            triggers: rows[2],
            screenLock: rows[3],
            closedLid: rows[4],
            summary: isComplete
                ? "Setup complete. Work, Night, and Travel are ready."
                : "\(completeCount) of \(rows.count) checks complete.",
            isComplete: isComplete
        )
    }

    private enum RowTitle {
        static let amphetamine = "Amphetamine 5.3.2 or later"
        static let automation = "Automation access"
        static let triggers = "Amphetamine Triggers off"
        static let screenLock = "Immediate screen locking"
        static let closedLid = "Closed-lid setup check"
    }

    private static let checkingDetail = "Checking…"

    private static func amphetamineRow(report: SetupReport) -> SetupRowPresentation {
        guard report.amphetamineInstalled else {
            return row(
                title: RowTitle.amphetamine,
                indicator: .needsAction,
                detail: "Amphetamine is not installed. Caffeine Modes controls sleep through Amphetamine.",
                action: .getAmphetamine
            )
        }
        guard report.supportedVersion else {
            let installed = report.detectedVersion.map { "Version \($0) is installed" }
                ?? "The installed version could not be read"
            return row(
                title: RowTitle.amphetamine,
                indicator: .needsAction,
                detail: "\(installed), and Caffeine Modes needs 5.3.2 or later.",
                action: .updateAmphetamine
            )
        }
        return row(
            title: RowTitle.amphetamine,
            indicator: .complete,
            detail: report.detectedVersion.map { "Version \($0) is installed." } ?? "Installed."
        )
    }

    private static func automationRow(report: SetupReport) -> SetupRowPresentation {
        switch report.automation {
        case .passed:
            row(
                title: RowTitle.automation,
                indicator: .complete,
                detail: "macOS lets Caffeine Modes control Amphetamine."
            )
        case .needsAction:
            row(
                title: RowTitle.automation,
                indicator: .needsAction,
                detail: "macOS is blocking Caffeine Modes from controlling Amphetamine. Allow Caffeine Modes in Automation settings.",
                action: .openAutomationSettings
            )
        case let .unchecked(reason):
            row(
                title: RowTitle.automation,
                indicator: .notChecked,
                detail: reason.map { "\($0) Use Check Again to retry." }
                    ?? "Checked once the Amphetamine check passes."
            )
        }
    }

    private static func triggersRow(
        report: SetupReport,
        actionFailure: String?
    ) -> SetupRowPresentation {
        switch report.triggers {
        case .passed:
            row(
                title: RowTitle.triggers,
                indicator: .complete,
                detail: "Amphetamine will not start sessions on its own."
            )
        case .needsAction:
            row(
                title: RowTitle.triggers,
                indicator: .needsAction,
                detail: actionFailure
                    ?? "Triggers let Amphetamine start sessions on its own, which can conflict with the mode you pick here. Caffeine Modes needs to be the only session owner.",
                action: .disableTriggers
            )
        case .unchecked:
            if let actionFailure {
                row(
                    title: RowTitle.triggers,
                    indicator: .needsAction,
                    detail: actionFailure,
                    action: .disableTriggers,
                    actionIsEnabled: report.automation == .passed
                )
            } else {
                row(
                    title: RowTitle.triggers,
                    indicator: .notChecked,
                    detail: "Checked once Automation access works."
                )
            }
        }
    }

    private static func screenLockRow(report: SetupReport) -> SetupRowPresentation {
        switch report.screenLock {
        case .passed:
            return row(
                title: RowTitle.screenLock,
                indicator: .complete,
                detail: "Your Mac locks as soon as the display turns off."
            )
        case .needsAction:
            return row(
                title: RowTitle.screenLock,
                indicator: .needsAction,
                detail: "Your Mac waits before it requires a password. Set “Require password after screen saver begins or display is turned off” to Immediately.",
                action: .openLockScreenSettings
            )
        case let .unchecked(reason):
            let detail: String
            if let reason {
                detail = "\(reason) Night and Travel stay blocked until macOS reports an immediate lock. Use Check Again to retry."
            } else {
                detail = "The screen-lock policy has not been checked yet."
            }
            return row(title: RowTitle.screenLock, indicator: .notChecked, detail: detail)
        }
    }

    private static func closedLidRow(
        report: SetupReport,
        actionFailure: String?
    ) -> SetupRowPresentation {
        guard !report.closedDisplayReady else {
            return row(
                title: RowTitle.closedLid,
                indicator: .complete,
                detail: "Amphetamine confirmed closed-display mode. Night and Travel can keep the Mac awake with the lid closed."
            )
        }
        let prerequisitesPass = report.amphetamineInstalled
            && report.supportedVersion
            && report.automation == .passed
            && report.triggers == .passed
        let sessionIsActive = report.amphetamineSessionIsActive == true
        if let actionFailure {
            let retryDetail: String
            if sessionIsActive {
                retryDetail = " Wait for the one-minute check session to end, or turn the session Off, then run the check again."
            } else if !prerequisitesPass {
                retryDetail = " Complete the checks above before you retry."
            } else {
                retryDetail = ""
            }
            return row(
                title: RowTitle.closedLid,
                indicator: .needsAction,
                detail: actionFailure + retryDetail,
                action: .runClosedLidCheck,
                actionIsEnabled: prerequisitesPass && !sessionIsActive
            )
        }
        guard prerequisitesPass else {
            return row(
                title: RowTitle.closedLid,
                indicator: .notChecked,
                detail: "Run this once the checks above pass. It verifies that Amphetamine can keep the Mac awake with the lid closed.",
                action: .runClosedLidCheck,
                actionIsEnabled: false
            )
        }
        guard !sessionIsActive else {
            return row(
                title: RowTitle.closedLid,
                indicator: .notChecked,
                detail: "An Amphetamine session is active. Turn the current session Off, then run this check.",
                action: .runClosedLidCheck,
                actionIsEnabled: false
            )
        }
        return row(
            title: RowTitle.closedLid,
            indicator: .notChecked,
            detail: "Starts a one-minute Amphetamine session and verifies closed-display mode. You do not need to close the lid. The session ends on its own.",
            action: .runClosedLidCheck
        )
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
        case .notChecked: "Not checked yet"
        }
    }
}
