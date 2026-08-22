import CaffeineModesAppSupport
import CaffeineModesCore
import XCTest

final class SetupStatusPresentationTests: XCTestCase {
    private func makeReport(
        amphetamineInstalled: Bool = true,
        supportedVersion: Bool = true,
        detectedVersion: String? = "5.3.2",
        automation: SetupCheckState = .passed,
        triggers: SetupCheckState = .passed,
        screenLock: SetupCheckState = .passed,
        closedDisplayReady: Bool = true,
        amphetamineSessionIsActive: Bool? = false
    ) -> SetupReport {
        SetupReport(
            amphetamineInstalled: amphetamineInstalled,
            supportedVersion: supportedVersion,
            detectedVersion: detectedVersion,
            automation: automation,
            triggers: triggers,
            screenLock: screenLock,
            closedDisplayReady: closedDisplayReady,
            amphetamineSessionIsActive: amphetamineSessionIsActive
        )
    }

    func testCompleteSetupHidesEveryActionAndReportsCompletion() {
        let presentation = SetupStatusPresentation.make(report: makeReport())

        XCTAssertTrue(presentation.isComplete)
        XCTAssertEqual(presentation.summary, "Setup complete. Work, Night, and Travel are ready.")
        for row in presentation.rows {
            XCTAssertEqual(row.indicator, .complete)
            XCTAssertNil(row.action)
        }
    }

    func testMissingAmphetamineOffersGetAndNamesTheProblem() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                amphetamineInstalled: false,
                supportedVersion: false,
                detectedVersion: nil,
                automation: .unchecked(reason: nil),
                triggers: .unchecked(reason: nil),
                closedDisplayReady: false,
                amphetamineSessionIsActive: nil
            )
        )

        XCTAssertEqual(presentation.amphetamine.indicator, .needsAction)
        XCTAssertEqual(presentation.amphetamine.action, .getAmphetamine)
        XCTAssertTrue(presentation.amphetamine.detail.contains("not installed"))
        XCTAssertEqual(presentation.automation.indicator, .notChecked)
        XCTAssertNil(presentation.automation.action)
    }

    func testUnsupportedVersionOffersUpdateAndNamesTheVersion() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                supportedVersion: false,
                detectedVersion: "5.3.1",
                automation: .unchecked(reason: nil),
                triggers: .unchecked(reason: nil),
                closedDisplayReady: false,
                amphetamineSessionIsActive: nil
            )
        )

        XCTAssertEqual(presentation.amphetamine.indicator, .needsAction)
        XCTAssertEqual(presentation.amphetamine.action, .updateAmphetamine)
        XCTAssertTrue(presentation.amphetamine.detail.contains("5.3.1"))
        XCTAssertTrue(presentation.amphetamine.detail.contains("5.3.2 or later"))
    }

    func testDeniedAutomationOffersSettingsAndBlockedTriggersStayUnchecked() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                automation: .needsAction,
                triggers: .unchecked(reason: nil),
                closedDisplayReady: false,
                amphetamineSessionIsActive: nil
            )
        )

        XCTAssertEqual(presentation.automation.indicator, .needsAction)
        XCTAssertEqual(presentation.automation.action, .openAutomationSettings)
        XCTAssertEqual(presentation.triggers.indicator, .notChecked)
        XCTAssertNil(presentation.triggers.action)
    }

    func testFailedAutomationReadPreservesTheReasonWithoutAWarning() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                automation: .unchecked(reason: "The operation did not finish before its safety deadline."),
                triggers: .unchecked(reason: nil),
                closedDisplayReady: false,
                amphetamineSessionIsActive: nil
            )
        )

        XCTAssertEqual(presentation.automation.indicator, .notChecked)
        XCTAssertNil(presentation.automation.action)
        XCTAssertTrue(
            presentation.automation.detail.contains("The operation did not finish before its safety deadline.")
        )
    }

    func testEnabledTriggersOfferDisableWithOwnershipExplanation() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(triggers: .needsAction, closedDisplayReady: false)
        )

        XCTAssertEqual(presentation.triggers.indicator, .needsAction)
        XCTAssertEqual(presentation.triggers.action, .disableTriggers)
        XCTAssertTrue(presentation.triggers.actionIsEnabled)
        XCTAssertTrue(presentation.triggers.detail.contains("only session owner"))
    }

    func testFailedDisableTriggersKeepsTheExactFailureAndTheRetryAction() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(triggers: .needsAction, closedDisplayReady: false),
            triggersActionFailure: "Injected triggers failure"
        )

        XCTAssertEqual(presentation.triggers.detail, "Injected triggers failure")
        XCTAssertEqual(presentation.triggers.action, .disableTriggers)
    }

    func testFailedDisableTriggersKeepsTheExactFailureWhenTheFollowUpReadFails() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                automation: .unchecked(reason: "Automation status could not be read."),
                triggers: .unchecked(reason: "Trigger status could not be read."),
                closedDisplayReady: false,
                amphetamineSessionIsActive: nil
            ),
            triggersActionFailure: "Amphetamine did not disable Triggers."
        )

        XCTAssertEqual(presentation.triggers.indicator, .needsAction)
        XCTAssertEqual(presentation.triggers.detail, "Amphetamine did not disable Triggers.")
        XCTAssertEqual(presentation.triggers.action, .disableTriggers)
        XCTAssertFalse(presentation.triggers.actionIsEnabled)
    }

    func testNonImmediateLockOffersSettingsAndUnknownLockDoesNot() {
        let nonImmediate = SetupStatusPresentation.make(
            report: makeReport(screenLock: .needsAction, closedDisplayReady: false)
        )
        XCTAssertEqual(nonImmediate.screenLock.indicator, .needsAction)
        XCTAssertEqual(nonImmediate.screenLock.action, .openLockScreenSettings)
        XCTAssertTrue(nonImmediate.screenLock.detail.contains("Immediately"))

        let unknown = SetupStatusPresentation.make(
            report: makeReport(
                screenLock: .unchecked(reason: "macOS returned an unknown screen-lock status."),
                closedDisplayReady: false
            )
        )
        XCTAssertEqual(unknown.screenLock.indicator, .notChecked)
        XCTAssertNil(unknown.screenLock.action)
        XCTAssertTrue(unknown.screenLock.detail.contains("macOS returned an unknown screen-lock status."))
        XCTAssertNotEqual(unknown.screenLock.detail, nonImmediate.screenLock.detail)
    }

    func testClosedLidCheckIsRunnableWhenPrerequisitesPassAndNoSessionIsActive() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(closedDisplayReady: false)
        )

        XCTAssertEqual(presentation.closedLid.indicator, .notChecked)
        XCTAssertEqual(presentation.closedLid.action, .runClosedLidCheck)
        XCTAssertTrue(presentation.closedLid.actionIsEnabled)
        XCTAssertTrue(presentation.closedLid.detail.contains("one-minute"))
        XCTAssertTrue(presentation.closedLid.detail.contains("do not need to close the lid"))
    }

    func testActiveSessionShowsTheOffPreconditionInsteadOfARunnableCheck() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(closedDisplayReady: false, amphetamineSessionIsActive: true)
        )

        XCTAssertEqual(presentation.closedLid.indicator, .notChecked)
        XCTAssertFalse(presentation.closedLid.actionIsEnabled)
        XCTAssertTrue(presentation.closedLid.detail.contains("Off"))
    }

    func testClosedLidCheckStaysDisabledUntilEarlierChecksPass() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                automation: .needsAction,
                triggers: .unchecked(reason: nil),
                closedDisplayReady: false,
                amphetamineSessionIsActive: nil
            )
        )

        XCTAssertEqual(presentation.closedLid.indicator, .notChecked)
        XCTAssertFalse(presentation.closedLid.actionIsEnabled)
        XCTAssertTrue(presentation.closedLid.detail.contains("checks above"))
    }

    func testFailedClosedLidCheckPreservesTheExactFailure() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(closedDisplayReady: false),
            closedLidActionFailure: "Amphetamine did not confirm closed-display mode."
        )

        XCTAssertEqual(presentation.closedLid.indicator, .needsAction)
        XCTAssertEqual(presentation.closedLid.detail, "Amphetamine did not confirm closed-display mode.")
        XCTAssertTrue(presentation.closedLid.actionIsEnabled)
    }

    func testFailedClosedLidCheckWithLeftoverSessionKeepsFailureAndDisablesRetry() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(closedDisplayReady: false, amphetamineSessionIsActive: true),
            closedLidActionFailure: "Amphetamine did not confirm closed-display mode."
        )

        XCTAssertEqual(presentation.closedLid.indicator, .needsAction)
        XCTAssertTrue(
            presentation.closedLid.detail.contains("Amphetamine did not confirm closed-display mode.")
        )
        XCTAssertFalse(presentation.closedLid.actionIsEnabled)
    }

    func testFailedClosedLidCheckKeepsTheExactFailureWhenPrerequisitesBecomeUnavailable() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                automation: .unchecked(reason: "Automation status could not be read."),
                triggers: .unchecked(reason: nil),
                closedDisplayReady: false,
                amphetamineSessionIsActive: nil
            ),
            closedLidActionFailure: "Amphetamine did not confirm closed-display mode."
        )

        XCTAssertEqual(presentation.closedLid.indicator, .needsAction)
        XCTAssertTrue(
            presentation.closedLid.detail.hasPrefix(
                "Amphetamine did not confirm closed-display mode."
            )
        )
        XCTAssertEqual(presentation.closedLid.action, .runClosedLidCheck)
        XCTAssertFalse(presentation.closedLid.actionIsEnabled)
    }

    func testSummaryCountsCompleteChecks() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                automation: .needsAction,
                triggers: .unchecked(reason: nil),
                closedDisplayReady: false,
                amphetamineSessionIsActive: nil
            )
        )

        XCTAssertFalse(presentation.isComplete)
        XCTAssertEqual(presentation.summary, "2 of 5 checks complete.")
    }
}
