import CaffeineModesCore
import XCTest

final class BatteryProtectionStatusTests: XCTestCase {
    private let matchingConfiguration = AmphetamineBatteryProtectionConfiguration(
        endsSessionOnLowBattery: true,
        thresholdPercent: 15,
        promptsBeforeEnding: false,
        ignoresLimitOnExternalPower: false
    )

    func testRequiredProtectionMatchesOnlyTheCompleteSafeConfiguration() {
        let requirement = BatteryProtectionRequirement(isRequired: true, thresholdPercent: 15)

        XCTAssertEqual(
            BatteryProtectionStatus(
                requirement: requirement,
                configuration: matchingConfiguration
            ).observation,
            .matches
        )

        let mismatches = [
            AmphetamineBatteryProtectionConfiguration(
                endsSessionOnLowBattery: false,
                thresholdPercent: 15,
                promptsBeforeEnding: false,
                ignoresLimitOnExternalPower: false
            ),
            AmphetamineBatteryProtectionConfiguration(
                endsSessionOnLowBattery: true,
                thresholdPercent: 10,
                promptsBeforeEnding: false,
                ignoresLimitOnExternalPower: false
            ),
            AmphetamineBatteryProtectionConfiguration(
                endsSessionOnLowBattery: true,
                thresholdPercent: 15,
                promptsBeforeEnding: true,
                ignoresLimitOnExternalPower: false
            )
        ]
        for configuration in mismatches {
            let status = BatteryProtectionStatus(
                requirement: requirement,
                configuration: configuration
            )
            XCTAssertEqual(status.observation, .mismatch)
            XCTAssertFalse(status.isReady)
        }
    }

    func testExternalPowerBypassIsRejectedWhenOtherSettingsMatch() {
        let configuration = AmphetamineBatteryProtectionConfiguration(
            endsSessionOnLowBattery: true,
            thresholdPercent: 15,
            promptsBeforeEnding: false,
            ignoresLimitOnExternalPower: true
        )

        let status = BatteryProtectionStatus(
            requirement: .defaultValue,
            configuration: configuration
        )

        XCTAssertEqual(status.observation, .mismatch)
        XCTAssertFalse(status.isReady)
    }

    func testRequiredProtectionFailsClosedWhenConfigurationIsUnavailable() {
        let status = BatteryProtectionStatus(
            requirement: .defaultValue,
            configuration: nil
        )

        XCTAssertEqual(status.observation, .unavailable)
        XCTAssertFalse(status.isReady)
    }

    func testDisabledRequirementIsReadyWithoutInspectingAConfiguration() {
        let status = BatteryProtectionStatus(
            requirement: .init(isRequired: false, thresholdPercent: 25),
            configuration: nil
        )

        XCTAssertEqual(status.observation, .notRequired)
        XCTAssertTrue(status.isReady)
    }

    func testInvalidRequirementThresholdFallsBackToFifteenPercent() {
        XCTAssertEqual(
            BatteryProtectionRequirement(isRequired: true, thresholdPercent: 99)
                .thresholdPercent,
            15
        )
    }
}
