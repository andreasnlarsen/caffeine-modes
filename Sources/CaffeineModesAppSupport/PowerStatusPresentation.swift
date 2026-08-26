import CaffeineModesCore
import Foundation

public struct ModeSafetyRecoveryPresentation: Equatable, Sendable {
    public let detail: String
    public let retryTitle: String
    public let turnOffTitle: String

    public init(detail: String, retryTitle: String, turnOffTitle: String) {
        self.detail = detail
        self.retryTitle = retryTitle
        self.turnOffTitle = turnOffTitle
    }

    public static func make(
        mode: OperatingMode,
        safety: ModeSafety,
        report: PowerAssertionReport?
    ) -> ModeSafetyRecoveryPresentation? {
        switch mode {
        case .night where safety != .ready:
            let process = report?.displaySleepBlockingProcesses.sorted().first
            let detail: String
            switch safety {
            case .nightUnlocked:
                detail = "Anyone at your Mac can use it."
            case .nightLockStateUnavailable:
                detail = "Your Mac may be unlocked."
            default:
                detail = process.map { "Display stay-awake request: \($0)." }
                    ?? "Your screen may still be visible."
            }
            return ModeSafetyRecoveryPresentation(
                detail: detail,
                retryTitle: "Retry Display Sleep",
                turnOffTitle: "Turn Off Night"
            )
        case .travel where safety != .ready:
            return ModeSafetyRecoveryPresentation(
                detail: safety == .travelUnlocked
                    ? "Anyone at your Mac can use it."
                    : "Your Mac may be unlocked.",
                retryTitle: "Try Lock Again",
                turnOffTitle: "Turn Off Travel"
            )
        default:
            return nil
        }
    }
}

public struct PowerStatusPresentation: Equatable, Sendable {
    public let statusLine: String
    public let toolTip: String
    public let accessibilityDescription: String
    public let hasModeSafetyWarning: Bool
    public let hasInspectionError: Bool

    public init(
        statusLine: String,
        toolTip: String,
        accessibilityDescription: String,
        hasModeSafetyWarning: Bool,
        hasInspectionError: Bool
    ) {
        self.statusLine = statusLine
        self.toolTip = toolTip
        self.accessibilityDescription = accessibilityDescription
        self.hasModeSafetyWarning = hasModeSafetyWarning
        self.hasInspectionError = hasInspectionError
    }

    public static func make(
        mode: OperatingMode,
        safety: ModeSafety = .ready,
        report: PowerAssertionReport?,
        travelSecondsRemaining: Int? = nil
    ) -> PowerStatusPresentation {
        let displayBlockers = report?.displaySleepBlockingProcesses ?? []
        let systemBlockers = report?.systemSleepBlockingProcesses ?? []
        let diskBlockers = report?.diskIdleBlockingProcesses ?? []

        let statusLine: String
        switch mode {
        case .off:
            if report == nil {
                statusLine = "Off · Power status unavailable"
            } else {
                var facts = ["Off"]
                if !displayBlockers.isEmpty {
                    facts.append("Display kept on by \(formattedNames(displayBlockers))")
                }
                if !systemBlockers.isEmpty {
                    facts.append("Automatic sleep blocked by \(formattedNames(systemBlockers))")
                }
                if facts.count == 1 {
                    facts.append("Follows macOS")
                }
                statusLine = facts.joined(separator: " · ")
            }
        case .work:
            statusLine = "Work · Mac and displays stay awake"
        case .night:
            switch safety {
            case .ready:
                statusLine = "Night · Displays off · Mac working while locked"
            case .nightDisplaysVisible:
                statusLine = "Night · Displays still on · Mac working while locked"
            case .nightDisplayStateUnavailable:
                statusLine = "Night · Displays not checked · Mac working while locked"
            case .nightUnlocked:
                statusLine = "Night · Mac did not lock"
            case .nightLockStateUnavailable:
                statusLine = "Night · Lock not checked"
            case .travelUnlocked, .travelLockStateUnavailable:
                statusLine = "Night · Safety status unavailable"
            }
        case .travel:
            let countdown = TravelCountdownFormatter.string(seconds: max(0, travelSecondsRemaining ?? 0))
            switch safety {
            case .ready:
                statusLine = "Travel · \(countdown) left · Mac working while locked"
            case .travelUnlocked:
                statusLine = "Travel · \(countdown) left · Mac did not lock"
            case .travelLockStateUnavailable:
                statusLine = "Travel · \(countdown) left · Lock not checked"
            case .nightDisplaysVisible, .nightDisplayStateUnavailable,
                 .nightUnlocked, .nightLockStateUnavailable:
                statusLine = "Travel · \(countdown) left · Safety status unavailable"
            }
        case .custom:
            statusLine = "Custom Amphetamine session"
        }

        let displayDetail = displayAssertionDetail(
            processes: displayBlockers,
            empty: mode == .work ? "Work keeps displays awake" : "no external stay-awake request detected",
            travelContinues: mode.travelDurationMinutes != nil
        )
        let systemDetail = blockerDetail(
            label: "Automatic sleep",
            processes: systemBlockers,
            empty: modeKeepsSystemAwake(mode)
                ? "kept awake by the selected mode"
                : "no external process blocker detected"
        )
        let diskDetail = blockerDetail(
            label: "Disk idle sleep",
            processes: diskBlockers,
            empty: "no external process blocker detected"
        )
        let inspectionDetail = report == nil
            ? "Power assertion details are unavailable."
            : [displayDetail, systemDetail, diskDetail].joined(separator: "\n")
        let lidDetail: String
        switch mode {
        case .night, .travel:
            lidDetail = "Lid: closed-display mode is enabled."
        default:
            lidDetail = "Lid: normal macOS behavior."
        }
        let modeSafetyDetails: [String]
        switch mode {
        case .night:
            modeSafetyDetails = [
                "Lock: \(lockDetail(for: safety)).",
                "Displays: \(nightDisplayDetail(for: safety))."
            ]
        case .travel:
            modeSafetyDetails = ["Lock: \(lockDetail(for: safety))."]
        case .off, .work, .custom:
            modeSafetyDetails = []
        }
        let safetyDetail = modeSafetyDetails.isEmpty
            ? ""
            : "\n" + modeSafetyDetails.joined(separator: "\n")

        return PowerStatusPresentation(
            statusLine: statusLine,
            toolTip: "Caffeine Modes — \(statusLine)\n\(inspectionDetail)\n\(lidDetail)\(safetyDetail)",
            accessibilityDescription: accessibilityDescription(
                mode: mode,
                safety: safety,
                statusLine: statusLine,
                travelSecondsRemaining: travelSecondsRemaining
            ),
            hasModeSafetyWarning: safety != .ready,
            hasInspectionError: report == nil && mode == .off
        )
    }

    private static func accessibilityDescription(
        mode: OperatingMode,
        safety: ModeSafety,
        statusLine: String,
        travelSecondsRemaining: Int?
    ) -> String {
        switch mode {
        case .night:
            switch safety {
            case .nightDisplaysVisible, .nightDisplayStateUnavailable:
                return "Night needs attention. Your Mac is locked and working, but its displays are not confirmed off."
            case .nightUnlocked, .nightLockStateUnavailable:
                return "Night needs attention. The lock is not confirmed."
            case .ready, .travelUnlocked, .travelLockStateUnavailable:
                return statusLine
            }
        case .travel:
            switch safety {
            case .travelUnlocked, .travelLockStateUnavailable:
                let countdown = TravelCountdownFormatter.string(
                    seconds: max(0, travelSecondsRemaining ?? 0)
                )
                return "Travel needs attention. The lock is not confirmed. \(countdown) left."
            case .ready, .nightDisplaysVisible, .nightDisplayStateUnavailable,
                 .nightUnlocked, .nightLockStateUnavailable:
                return statusLine
            }
        case .off, .work, .custom:
            return statusLine
        }
    }

    private static func displayAssertionDetail(
        processes: [String],
        empty: String,
        travelContinues: Bool
    ) -> String {
        guard !processes.isEmpty else { return "Display sleep: \(empty)." }
        let continuation = travelContinues ? " This does not stop Travel." : ""
        return "Display sleep: \(formattedNames(processes)) asked to keep a display on.\(continuation)"
    }

    private static func lockDetail(for safety: ModeSafety) -> String {
        switch safety {
        case .ready, .nightDisplaysVisible, .nightDisplayStateUnavailable:
            "checked"
        case .nightUnlocked, .travelUnlocked:
            "not locked"
        case .nightLockStateUnavailable, .travelLockStateUnavailable:
            "not checked"
        }
    }

    private static func nightDisplayDetail(for safety: ModeSafety) -> String {
        switch safety {
        case .ready: "all off"
        case .nightDisplaysVisible: "still on"
        case .nightDisplayStateUnavailable: "not checked"
        case .nightUnlocked, .nightLockStateUnavailable,
             .travelUnlocked, .travelLockStateUnavailable: "not checked"
        }
    }

    private static func blockerDetail(label: String, processes: [String], empty: String) -> String {
        guard !processes.isEmpty else { return "\(label): \(empty)." }
        return "\(label): blocked by \(formattedNames(processes))."
    }

    private static func formattedNames(_ names: [String]) -> String {
        let unique = Array(Set(names)).sorted()
        switch unique.count {
        case 0: return ""
        case 1: return unique[0]
        case 2: return "\(unique[0]) and \(unique[1])"
        default:
            return unique.dropLast().joined(separator: ", ") + ", and " + unique.last!
        }
    }

    private static func modeKeepsSystemAwake(_ mode: OperatingMode) -> Bool {
        switch mode {
        case .work, .night, .travel: true
        case .off, .custom: false
        }
    }
}
