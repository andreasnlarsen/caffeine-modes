import CaffeineModesCore
import XCTest

final class OperatingModePolicyTests: XCTestCase {
    func testModePoliciesKeepDisplayLockTimerAndLidRulesIndependent() {
        XCTAssertEqual(
            OperatingMode.work.policy,
            OperatingModePolicy(
                displayBehavior: .keepAwake,
                usesClosedDisplayMode: false,
                requiresImmediateLockPolicy: false,
                requiresLockVerification: false,
                requiresBatteryProtection: false,
                observesUnlock: false,
                resleepsAfterDisplayWake: false
            )
        )
        XCTAssertEqual(
            OperatingMode.night.policy,
            OperatingModePolicy(
                displayBehavior: .forceSleepAndMaintain,
                usesClosedDisplayMode: true,
                requiresImmediateLockPolicy: true,
                requiresLockVerification: true,
                requiresBatteryProtection: true,
                observesUnlock: true,
                resleepsAfterDisplayWake: true
            )
        )
        XCTAssertEqual(
            OperatingMode.travel(durationMinutes: 90, expiresAt: .distantFuture).policy,
            OperatingModePolicy(
                displayBehavior: .allowSleep,
                usesClosedDisplayMode: true,
                requiresImmediateLockPolicy: true,
                requiresLockVerification: true,
                requiresBatteryProtection: true,
                observesUnlock: true,
                resleepsAfterDisplayWake: false
            )
        )
    }
}
