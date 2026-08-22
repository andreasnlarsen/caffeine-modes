import CaffeineModesCore
import Foundation

public struct PowerStatusPresentation: Equatable, Sendable {
    public let statusLine: String
    public let toolTip: String
    public let hasUnexpectedDisplayBlocker: Bool
    public let hasInspectionError: Bool

    public init(
        statusLine: String,
        toolTip: String,
        hasUnexpectedDisplayBlocker: Bool,
        hasInspectionError: Bool
    ) {
        self.statusLine = statusLine
        self.toolTip = toolTip
        self.hasUnexpectedDisplayBlocker = hasUnexpectedDisplayBlocker
        self.hasInspectionError = hasInspectionError
    }

    public static func make(
        mode: OperatingMode,
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
                    facts.append("Display and automatic sleep follow macOS settings")
                }
                statusLine = facts.joined(separator: " · ")
            }
        case .work:
            statusLine = "Work · Display stays on · Normal lid behavior"
        case .night:
            if report == nil {
                statusLine = "Night · Display status unavailable · Runs with lid closed"
            } else {
                statusLine = displayBlockers.isEmpty
                    ? "Night · Display sleeps · Runs with lid closed"
                    : "Night · Display kept on by \(formattedNames(displayBlockers)) · Runs with lid closed"
            }
        case .travel:
            let countdown = TravelCountdownFormatter.string(seconds: max(0, travelSecondsRemaining ?? 0))
            if report == nil {
                statusLine = "Travel · \(countdown) remaining · Display status unavailable · Runs with lid closed"
            } else {
                statusLine = displayBlockers.isEmpty
                    ? "Travel · \(countdown) remaining · Display sleeps · Runs with lid closed"
                    : "Travel · \(countdown) remaining · Display kept on by \(formattedNames(displayBlockers)) · Runs with lid closed"
            }
        case .custom:
            statusLine = "Custom Amphetamine session"
        }

        let displayDetail = blockerDetail(
            label: "Display sleep",
            processes: displayBlockers,
            empty: mode == .work ? "kept on by Work" : "no external process blocker detected"
        )
        let systemDetail = blockerDetail(
            label: "Automatic system sleep",
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

        return PowerStatusPresentation(
            statusLine: statusLine,
            toolTip: "Caffeine Modes — \(statusLine)\n\(inspectionDetail)\n\(lidDetail)",
            hasUnexpectedDisplayBlocker: !displayBlockers.isEmpty && modeExpectsDisplaySleep(mode),
            hasInspectionError: report == nil && mode != .work && mode != .custom
        )
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

    private static func modeExpectsDisplaySleep(_ mode: OperatingMode) -> Bool {
        switch mode {
        case .night, .travel: true
        case .off, .work, .custom: false
        }
    }
}
