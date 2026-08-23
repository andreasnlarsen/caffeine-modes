import CaffeineModesCore
import XCTest
@testable import CaffeineModesApp

final class SystemClamshellContextInspectorTests: XCTestCase {
    func testPowerSourceMappingDistinguishesExternalBatteryAndUnknown() {
        XCTAssertEqual(
            SystemClamshellContextInspector.externalPowerConnected(sourceType: "AC Power"),
            true
        )
        XCTAssertEqual(
            SystemClamshellContextInspector.externalPowerConnected(sourceType: "UPS Power"),
            true
        )
        XCTAssertEqual(
            SystemClamshellContextInspector.externalPowerConnected(sourceType: "Battery Power"),
            false
        )
        XCTAssertNil(
            SystemClamshellContextInspector.externalPowerConnected(sourceType: "Unknown")
        )
    }

    func testOnlyActiveAwakeNonBuiltinDisplayIsEligible() {
        for isBuiltin in [false, true] {
            for isActive in [false, true] {
                for isAsleep in [false, true] {
                    XCTAssertEqual(
                        SystemClamshellContextInspector.isEligibleExternalDisplay(
                            isBuiltin: isBuiltin,
                            isActive: isActive,
                            isAsleep: isAsleep
                        ),
                        !isBuiltin && isActive && !isAsleep,
                        "builtin=\(isBuiltin), active=\(isActive), asleep=\(isAsleep)"
                    )
                }
            }
        }
    }

    func testStableContextFailsClosedWhenLidChangesDuringRead() {
        let stable = SystemClamshellContextInspector.stableContext(
            firstLidState: .closed,
            externalPowerConnected: true,
            activeExternalDisplayPresent: true,
            secondLidState: .closed
        )
        XCTAssertEqual(stable.lidState, .closed)
        XCTAssertTrue(stable.permitsActiveClosedDisplaySessionReplacement)

        let changed = SystemClamshellContextInspector.stableContext(
            firstLidState: .open,
            externalPowerConnected: true,
            activeExternalDisplayPresent: true,
            secondLidState: .closed
        )
        XCTAssertEqual(changed.lidState, .unavailable)
        XCTAssertFalse(changed.permitsActiveClosedDisplaySessionReplacement)
    }
}
