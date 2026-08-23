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
        XCTAssertFalse(presentation.hasUnexpectedDisplayBlocker)
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
            PowerStatusPresentation.make(mode: .night, report: .empty).statusLine,
            "Night · Mac working while locked"
        )
    }

    func testNightSurfacesDisplayBlockerThatAppearsAfterTransition() {
        let presentation = PowerStatusPresentation.make(
            mode: .night,
            report: PowerAssertionReport(displaySleepBlockingProcesses: ["Raycast"])
        )

        XCTAssertEqual(
            presentation.statusLine,
            "Night · Display kept on by Raycast"
        )
        XCTAssertTrue(presentation.hasUnexpectedDisplayBlocker)
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
        XCTAssertFalse(presentation.hasUnexpectedDisplayBlocker)
    }

    func testTravelKeepsLidPolicyVisibleWhenDisplayIsBlocked() {
        let presentation = PowerStatusPresentation.make(
            mode: .travel(durationMinutes: 90, expiresAt: Date()),
            report: PowerAssertionReport(displaySleepBlockingProcesses: ["Raycast"]),
            travelSecondsRemaining: 5_400
        )

        XCTAssertEqual(
            presentation.statusLine,
            "Travel · 1h 30m left · Display kept on by Raycast"
        )
        XCTAssertTrue(presentation.hasUnexpectedDisplayBlocker)
    }

    func testTravelKeepsLidPolicyVisibleWhenInspectionIsUnavailable() {
        let presentation = PowerStatusPresentation.make(
            mode: .travel(durationMinutes: 90, expiresAt: Date()),
            report: nil,
            travelSecondsRemaining: 5_400
        )

        XCTAssertEqual(
            presentation.statusLine,
            "Travel · 1h 30m left · Display status unavailable"
        )
        XCTAssertTrue(presentation.hasInspectionError)
    }

    func testMissingInspectionDoesNotClaimThatSleepIsUnblocked() {
        let presentation = PowerStatusPresentation.make(mode: .off, report: nil)

        XCTAssertEqual(presentation.statusLine, "Off · Power status unavailable")
        XCTAssertTrue(presentation.hasInspectionError)
        XCTAssertTrue(presentation.toolTip.contains("Power assertion details are unavailable."))
    }
}
