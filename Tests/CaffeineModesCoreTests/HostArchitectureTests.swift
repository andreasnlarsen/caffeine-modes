import CaffeineModesAppSupport
import XCTest
@testable import CaffeineModesApp

final class HostArchitectureTests: XCTestCase {
    func testAppleSiliconHostRequiresPowerProtect() {
        XCTAssertTrue(HostArchitecture.requiresPowerProtect(arm64Capability: 1))
    }

    func testIntelHostDoesNotRequirePowerProtect() {
        XCTAssertFalse(HostArchitecture.requiresPowerProtect(arm64Capability: 0))
    }

    func testUnknownHostArchitectureRequiresPowerProtect() {
        XCTAssertTrue(HostArchitecture.requiresPowerProtect(arm64Capability: nil))
    }

    func testPowerProtectConfigurationUsesInstalledFilenameCase() {
        XCTAssertEqual(
            AmphetaminePowerProtectInspector.configurationPath,
            "/private/etc/sudoers.d/amphetamine_PowerProtect"
        )
    }
}
