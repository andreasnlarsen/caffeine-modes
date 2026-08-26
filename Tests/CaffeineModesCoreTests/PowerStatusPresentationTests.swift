import CaffeineModesAppSupport
import CaffeineModesCore
import Foundation
import XCTest

final class PowerStatusPresentationTests: XCTestCase {
    func testProcessFilterKeepsUserFacingAppleAppsAndHidesSystemServices() {
        XCTAssertFalse(
            PowerAssertionProcessFilter.hidesFromSystemAndDiskSummary(
                bundleIdentifier: "com.apple.Music",
                executablePath: "/System/Applications/Music.app/Contents/MacOS/Music",
                isUserFacingApplication: true
            )
        )
        XCTAssertTrue(
            PowerAssertionProcessFilter.hidesFromSystemAndDiskSummary(
                bundleIdentifier: "com.apple.powerd",
                executablePath: "/System/Library/CoreServices/powerd",
                isUserFacingApplication: false
            )
        )
        XCTAssertFalse(
            PowerAssertionProcessFilter.hidesFromSystemAndDiskSummary(
                bundleIdentifier: "com.openai.chat",
                executablePath: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT",
                isUserFacingApplication: true
            )
        )
    }

    func testClassifierSeparatesDisplaySystemAndDiskAssertions() {
        XCTAssertEqual(PowerAssertionClassifier.category(forType: "PreventUserIdleDisplaySleep"), .displaySleep)
        XCTAssertEqual(PowerAssertionClassifier.category(forType: "NoDisplaySleepAssertion"), .displaySleep)
        XCTAssertEqual(PowerAssertionClassifier.category(forType: "PreventUserIdleSystemSleep"), .systemSleep)
        XCTAssertEqual(PowerAssertionClassifier.category(forType: "NoIdleSleepAssertion"), .systemSleep)
        XCTAssertEqual(PowerAssertionClassifier.category(forType: "PreventSystemSleep"), .systemSleep)
        XCTAssertEqual(PowerAssertionClassifier.category(forType: "NetworkClientActive"), .systemSleep)
        XCTAssertEqual(PowerAssertionClassifier.category(forType: "PreventDiskIdle"), .diskIdle)
        XCTAssertNil(PowerAssertionClassifier.category(forType: "UserIsActive"))
    }

    func testTooltipUsesTheDocumentedDisplaySleepFactLabel() {
        let presentation = PowerStatusPresentation.make(
            mode: .off,
            safety: .ready,
            report: .empty
        )

        XCTAssertTrue(presentation.toolTip.contains("\nDisplay sleep:"))
        XCTAssertFalse(presentation.toolTip.contains("\nDisplay:"))
    }

    func testOffDistinguishesDisplayAndAutomaticSleepBlockers() {
        let presentation = PowerStatusPresentation.make(
            mode: .off,
            report: PowerAssertionReport(
                displaySleepBlockingProcesses: ["Raycast"],
                systemSleepBlockingProcesses: ["Claude", "ChatGPT"],
                diskIdleBlockingProcesses: ["backupd"]
            )
        )

        XCTAssertEqual(
            presentation.statusLine,
            "Off · Display kept on by Raycast · Automatic sleep blocked by ChatGPT and Claude"
        )
        XCTAssertTrue(presentation.toolTip.contains("Disk idle sleep: blocked by backupd."))
        XCTAssertFalse(presentation.hasModeSafetyWarning)
    }

    func testDiskBlockerDoesNotClaimThatAutomaticSleepIsBlocked() {
        let presentation = PowerStatusPresentation.make(
            mode: .off,
            report: PowerAssertionReport(diskIdleBlockingProcesses: ["backupd"])
        )

        XCTAssertEqual(
            presentation.statusLine,
            "Off · Follows macOS"
        )
        XCTAssertTrue(presentation.toolTip.contains("Disk idle sleep: blocked by backupd."))
    }

    func testModeStatusUsesShortUserFacingOutcomes() {
        XCTAssertEqual(
            PowerStatusPresentation.make(mode: .work, report: .empty).statusLine,
            "Work · Mac and displays stay awake"
        )
        XCTAssertEqual(
            PowerStatusPresentation.make(mode: .night, safety: .ready, report: .empty).statusLine,
            "Night · Displays off · Mac working while locked"
        )
    }

    func testNightUsesActualDisplayStateAndKeepsAssertionInTooltip() {
        let presentation = PowerStatusPresentation.make(
            mode: .night,
            safety: .ready,
            report: PowerAssertionReport(displaySleepBlockingProcesses: ["Raycast"])
        )

        XCTAssertEqual(presentation.statusLine, "Night · Displays off · Mac working while locked")
        XCTAssertTrue(presentation.toolTip.contains("Raycast asked to keep a display on"))
        XCTAssertFalse(presentation.hasModeSafetyWarning)
    }

    func testNightVisibleDisplayShowsRecoveryState() {
        let presentation = PowerStatusPresentation.make(
            mode: .night,
            safety: .nightDisplaysVisible,
            report: .empty
        )

        XCTAssertEqual(presentation.statusLine, "Night · Displays still on · Mac working while locked")
        XCTAssertEqual(
            presentation.accessibilityDescription,
            "Night needs attention. Your Mac is locked and working, but its displays are not confirmed off."
        )
        XCTAssertTrue(presentation.hasModeSafetyWarning)
    }

    func testTravelKeepsCountdownAndLidPolicyVisible() {
        let presentation = PowerStatusPresentation.make(
            mode: .travel(durationMinutes: 90, expiresAt: Date()),
            report: .empty,
            travelSecondsRemaining: 5_400
        )

        XCTAssertEqual(
            presentation.statusLine,
            "Travel · 1h 30m left · Mac working while locked"
        )
        XCTAssertFalse(presentation.hasModeSafetyWarning)
    }

    func testTravelKeepsLidPolicyVisibleWhenDisplayIsBlocked() {
        let presentation = PowerStatusPresentation.make(
            mode: .travel(durationMinutes: 90, expiresAt: Date()),
            safety: .ready,
            report: PowerAssertionReport(displaySleepBlockingProcesses: ["Raycast"]),
            travelSecondsRemaining: 5_400
        )

        XCTAssertEqual(
            presentation.statusLine,
            "Travel · 1h 30m left · Mac working while locked"
        )
        XCTAssertTrue(presentation.toolTip.contains("Raycast asked to keep a display on"))
        XCTAssertFalse(presentation.hasModeSafetyWarning)
    }

    func testTravelKeepsLidPolicyVisibleWhenInspectionIsUnavailable() {
        let presentation = PowerStatusPresentation.make(
            mode: .travel(durationMinutes: 90, expiresAt: Date()),
            safety: .ready,
            report: nil,
            travelSecondsRemaining: 5_400
        )

        XCTAssertEqual(
            presentation.statusLine,
            "Travel · 1h 30m left · Mac working while locked"
        )
        XCTAssertFalse(presentation.hasInspectionError)
    }

    func testTravelLockFailureKeepsTimerAndShowsRecoveryState() {
        let presentation = PowerStatusPresentation.make(
            mode: .travel(durationMinutes: 90, expiresAt: Date()),
            safety: .travelUnlocked,
            report: .empty,
            travelSecondsRemaining: 5_400
        )

        XCTAssertEqual(presentation.statusLine, "Travel · 1h 30m left · Mac did not lock")
        XCTAssertEqual(
            presentation.accessibilityDescription,
            "Travel needs attention. The lock is not confirmed. 1h 30m left."
        )
        XCTAssertTrue(presentation.hasModeSafetyWarning)
    }

    func testNightLockFailureUsesAccurateAccessibilityDescription() {
        let presentation = PowerStatusPresentation.make(
            mode: .night,
            safety: .nightUnlocked,
            report: .empty
        )

        XCTAssertEqual(
            presentation.accessibilityDescription,
            "Night needs attention. The lock is not confirmed."
        )
    }

    func testRecoveryPresentationUsesModeSpecificActionsAndShortCause() {
        XCTAssertEqual(
            ModeSafetyRecoveryPresentation.make(
                mode: .night,
                safety: .nightDisplaysVisible,
                report: PowerAssertionReport(displaySleepBlockingProcesses: ["Polytopia"])
            ),
            ModeSafetyRecoveryPresentation(
                detail: "Display stay-awake request: Polytopia.",
                retryTitle: "Retry Display Sleep",
                turnOffTitle: "Turn Off Night"
            )
        )
        XCTAssertEqual(
            ModeSafetyRecoveryPresentation.make(
                mode: .travel(durationMinutes: 90, expiresAt: .distantFuture),
                safety: .travelUnlocked,
                report: .empty
            ),
            ModeSafetyRecoveryPresentation(
                detail: "Anyone at your Mac can use it.",
                retryTitle: "Try Lock Again",
                turnOffTitle: "Turn Off Travel"
            )
        )
    }

    func testMissingInspectionDoesNotClaimThatSleepIsUnblocked() {
        let presentation = PowerStatusPresentation.make(mode: .off, report: nil)

        XCTAssertEqual(presentation.statusLine, "Off · Power status unavailable")
        XCTAssertTrue(presentation.hasInspectionError)
        XCTAssertTrue(presentation.toolTip.contains("Power assertion details are unavailable."))
    }
}
