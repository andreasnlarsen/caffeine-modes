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
        batteryProtection: BatteryProtectionStatus = .readyDefault,
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
            batteryProtection: batteryProtection,
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
        XCTAssertEqual(presentation.batteryProtection.indicator, .notChecked)
        XCTAssertEqual(presentation.batteryProtection.detail, "Install Amphetamine first.")
        XCTAssertNil(presentation.batteryProtection.action)
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
        XCTAssertEqual(presentation.batteryProtection.indicator, .notChecked)
        XCTAssertEqual(presentation.batteryProtection.detail, "Update Amphetamine first.")
        XCTAssertNil(presentation.batteryProtection.action)
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

    func testBatteryProtectionReadyMismatchUnavailableAndDisabledStates() {
        let ready = SetupStatusPresentation.make(report: makeReport()).batteryProtection
        XCTAssertEqual(ready.indicator, .complete)
        XCTAssertEqual(ready.detail, "Amphetamine ends sessions at 15%.")
        XCTAssertNil(ready.action)

        let mismatchStatus = BatteryProtectionStatus(
            requirement: .defaultValue,
            configuration: AmphetamineBatteryProtectionConfiguration(
                endsSessionOnLowBattery: true,
                thresholdPercent: 10,
                promptsBeforeEnding: false,
                ignoresLimitOnExternalPower: true
            )
        )
        let mismatch = SetupStatusPresentation.make(
            report: makeReport(batteryProtection: mismatchStatus)
        ).batteryProtection
        XCTAssertEqual(mismatch.indicator, .needsAction)
        XCTAssertEqual(mismatch.action, .openAmphetamine)
        XCTAssertEqual(
            mismatch.detail,
            "In Session Defaults: end at 15%, no prompt, keep ‘Ignore charge’ off."
        )

        let unavailable = SetupStatusPresentation.make(
            report: makeReport(
                batteryProtection: BatteryProtectionStatus(
                    requirement: .defaultValue,
                    configuration: nil
                )
            )
        ).batteryProtection
        XCTAssertEqual(unavailable.indicator, .needsAction)
        XCTAssertEqual(unavailable.action, .openAmphetamine)

        let disabled = SetupStatusPresentation.make(
            report: makeReport(
                batteryProtection: BatteryProtectionStatus(
                    requirement: .init(isRequired: false, thresholdPercent: 25),
                    configuration: nil
                )
            )
        ).batteryProtection
        XCTAssertEqual(disabled.indicator, .notChecked)
        XCTAssertNil(disabled.action)
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
                    powerProtect: .init(isRequired: false, isInstalled: false),
                    batteryProtection: BatteryProtectionStatus(
                        requirement: .init(isRequired: false, thresholdPercent: 15),
                        configuration: nil
                    )
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
                powerProtect: .init(isRequired: true, isInstalled: false),
                batteryProtection: BatteryProtectionStatus(
                    requirement: .defaultValue,
                    configuration: nil
                )
            )
        )

        XCTAssertEqual(presentation.amphetamine.action, .getAmphetamine)
        XCTAssertEqual(presentation.automation.action, .openAutomationSettings)
        XCTAssertEqual(presentation.triggers.action, .disableTriggers)
        XCTAssertEqual(presentation.screenLock.action, .openLockScreenSettings)
        XCTAssertEqual(presentation.powerProtect.action, .getPowerProtect)
        XCTAssertEqual(presentation.batteryProtection.indicator, .notChecked)
        XCTAssertNil(presentation.batteryProtection.action)
    }
}
