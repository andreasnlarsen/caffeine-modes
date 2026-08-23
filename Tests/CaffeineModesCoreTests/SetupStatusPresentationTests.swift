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
        powerProtect: PowerProtectStatus = .init(isRequired: true, isInstalled: true),
        developerDiagnosticPassed: Bool = false,
        developerDiagnosticIsActive: Bool = false,
        amphetamineSessionIsActive: Bool? = false
    ) -> SetupReport {
        SetupReport(
            amphetamineInstalled: amphetamineInstalled,
            supportedVersion: supportedVersion,
            detectedVersion: detectedVersion,
            automation: automation,
            triggers: triggers,
            screenLock: screenLock,
            powerProtect: powerProtect,
            developerDiagnosticPassed: developerDiagnosticPassed,
            developerDiagnosticIsActive: developerDiagnosticIsActive,
            amphetamineSessionIsActive: amphetamineSessionIsActive
        )
    }

    func testCompleteSetupHidesEveryActionAndReportsCompletion() {
        let presentation = SetupStatusPresentation.make(report: makeReport())

        XCTAssertTrue(presentation.isComplete)
        XCTAssertEqual(presentation.summary, "Ready")
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
                amphetamineSessionIsActive: nil
            )
        )

        XCTAssertEqual(presentation.amphetamine.indicator, .needsAction)
        XCTAssertEqual(presentation.amphetamine.action, .getAmphetamine)
        XCTAssertTrue(presentation.amphetamine.detail.contains("Install"))
        XCTAssertEqual(presentation.automation.indicator, .notChecked)
    }

    func testUnsupportedVersionOffersUpdateAndNamesTheVersion() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                supportedVersion: false,
                detectedVersion: "5.3.1",
                automation: .unchecked(reason: nil),
                triggers: .unchecked(reason: nil)
            )
        )

        XCTAssertEqual(presentation.amphetamine.action, .updateAmphetamine)
        XCTAssertTrue(presentation.amphetamine.detail.contains("5.3.1"))
    }

    func testDeniedAutomationOffersItsMatchingAction() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                automation: .needsAction,
                triggers: .unchecked(reason: nil)
            )
        )

        XCTAssertEqual(presentation.automation.indicator, .needsAction)
        XCTAssertEqual(presentation.automation.action, .openAutomationSettings)
        XCTAssertEqual(presentation.triggers.indicator, .notChecked)
    }

    func testEnabledTriggersOfferDisable() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(triggers: .needsAction)
        )

        XCTAssertEqual(presentation.triggers.action, .disableTriggers)
        XCTAssertTrue(presentation.triggers.actionIsEnabled)
    }

    func testNonImmediateLockOffersSettingsAndUnknownLockDoesNot() {
        let needsAction = SetupStatusPresentation.make(
            report: makeReport(screenLock: .needsAction)
        )
        XCTAssertEqual(needsAction.screenLock.action, .openLockScreenSettings)
        XCTAssertTrue(needsAction.screenLock.detail.contains("Immediately"))

        let unknown = SetupStatusPresentation.make(
            report: makeReport(screenLock: .unchecked(reason: "Unknown policy"))
        )
        XCTAssertNil(unknown.screenLock.action)
        XCTAssertTrue(unknown.screenLock.detail.contains("Unknown policy"))
    }

    func testMissingRequiredPowerProtectOffersOfficialInstaller() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                powerProtect: .init(isRequired: true, isInstalled: false)
            )
        )

        XCTAssertEqual(presentation.powerProtect.indicator, .needsAction)
        XCTAssertEqual(presentation.powerProtect.action, .getPowerProtect)
        XCTAssertTrue(presentation.powerProtect.detail.contains("disconnect"))
        XCTAssertFalse(presentation.isComplete)
    }

    func testPowerProtectIsCompleteWhenThisMacDoesNotNeedIt() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                powerProtect: .init(isRequired: false, isInstalled: false)
            )
        )

        XCTAssertEqual(presentation.powerProtect.indicator, .complete)
        XCTAssertTrue(presentation.powerProtect.detail.contains("not needed"))
        XCTAssertTrue(presentation.isComplete)
    }

    func testDeveloperDiagnosticNeverBlocksSetup() {
        let failedOrUnused = SetupStatusPresentation.make(
            report: makeReport(developerDiagnosticPassed: false)
        )
        let passed = SetupStatusPresentation.make(
            report: makeReport(developerDiagnosticPassed: true)
        )

        XCTAssertTrue(failedOrUnused.isComplete)
        XCTAssertTrue(passed.isComplete)
        XCTAssertEqual(failedOrUnused.rows, passed.rows)
    }

    func testDeveloperDiagnosticRequiresVerifiedOff() {
        XCTAssertEqual(
            DeveloperDiagnosticAvailability.make(report: nil),
            DeveloperDiagnosticAvailability(
                isEnabled: false,
                blockedStatus: "Check Amphetamine first"
            )
        )
        XCTAssertEqual(
            DeveloperDiagnosticAvailability.make(
                report: makeReport(amphetamineSessionIsActive: true)
            ),
            DeveloperDiagnosticAvailability(isEnabled: false, blockedStatus: "Turn Off first")
        )
        XCTAssertEqual(
            DeveloperDiagnosticAvailability.make(report: makeReport()),
            DeveloperDiagnosticAvailability(isEnabled: true, blockedStatus: nil)
        )
    }

    func testDeveloperDiagnosticRequiresKnownSetupPrerequisites() {
        XCTAssertEqual(
            DeveloperDiagnosticAvailability.make(
                report: makeReport(triggers: .needsAction)
            ),
            DeveloperDiagnosticAvailability(
                isEnabled: false,
                blockedStatus: "Complete Setup first"
            )
        )
        XCTAssertEqual(
            DeveloperDiagnosticAvailability.make(
                report: makeReport(
                    powerProtect: .init(isRequired: true, isInstalled: false)
                )
            ),
            DeveloperDiagnosticAvailability(
                isEnabled: false,
                blockedStatus: "Complete Setup first"
            )
        )
        XCTAssertEqual(
            DeveloperDiagnosticAvailability.make(
                report: makeReport(
                    powerProtect: .init(isRequired: false, isInstalled: false)
                )
            ),
            DeveloperDiagnosticAvailability(isEnabled: true, blockedStatus: nil)
        )
    }

    func testActiveDeveloperDiagnosticKeepsItsProgressStatus() {
        XCTAssertEqual(
            DeveloperDiagnosticAvailability.make(
                report: makeReport(
                    developerDiagnosticPassed: true,
                    developerDiagnosticIsActive: true,
                    amphetamineSessionIsActive: true
                )
            ),
            DeveloperDiagnosticAvailability(isEnabled: false, blockedStatus: nil)
        )
    }

    func testEverySetupProblemKeepsItsActionOnTheSameRow() {
        let presentation = SetupStatusPresentation.make(
            report: makeReport(
                amphetamineInstalled: false,
                supportedVersion: false,
                detectedVersion: nil,
                automation: .needsAction,
                triggers: .needsAction,
                screenLock: .needsAction,
                powerProtect: .init(isRequired: true, isInstalled: false)
            )
        )

        XCTAssertEqual(presentation.amphetamine.action, .getAmphetamine)
        XCTAssertEqual(presentation.automation.action, .openAutomationSettings)
        XCTAssertEqual(presentation.triggers.action, .disableTriggers)
        XCTAssertEqual(presentation.screenLock.action, .openLockScreenSettings)
        XCTAssertEqual(presentation.powerProtect.action, .getPowerProtect)
    }
}
