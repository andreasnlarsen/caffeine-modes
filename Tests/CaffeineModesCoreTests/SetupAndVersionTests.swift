import CaffeineModesCore
import XCTest

final class SetupAndVersionTests: XCTestCase {
    func testVersionComparisonUsesNumericComponents() {
        XCTAssertFalse(VersionSupport.isSupported(nil))
        XCTAssertFalse(VersionSupport.isSupported("5.3.1"))
        XCTAssertTrue(VersionSupport.isSupported("5.3.2"))
        XCTAssertTrue(VersionSupport.isSupported("5.10.0"))
    }

    func testMissingAmphetamineIsDeterministic() {
        let fixture = Fixture()
        fixture.amphetamine.isInstalled = false
        fixture.amphetamine.installedVersion = nil

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.health, .amphetamineMissing)
        XCTAssertFalse(fixture.controller.setupReport().amphetamineInstalled)
    }

    func testOldAmphetamineIsRejectedBeforeMutation() {
        let fixture = Fixture()
        fixture.amphetamine.installedVersion = "5.3.1"

        XCTAssertThrowsError(try fixture.controller.transition(to: .work, replacingUnownedSession: false)) { error in
            XCTAssertEqual(error as? ModeControlError, .unsupportedVersion(found: "5.3.1"))
        }
        XCTAssertTrue(fixture.amphetamine.commands.isEmpty)
    }

    func testAutomationDenialIsReported() {
        let fixture = Fixture()
        fixture.amphetamine.readError = ModeControlError.automationDenied

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.health, .automationDenied)
        XCTAssertFalse(fixture.controller.setupReport().automationAuthorized)
    }

    func testEnabledTriggersBlockWork() {
        let fixture = Fixture()
        fixture.amphetamine.state.triggersEnabled = true

        XCTAssertThrowsError(try fixture.controller.transition(to: .work, replacingUnownedSession: false)) { error in
            XCTAssertEqual(error as? ModeControlError, .triggersEnabled)
        }
    }

    func testDisableTriggersVerifiesResult() throws {
        let fixture = Fixture()
        fixture.amphetamine.state.triggersEnabled = true

        try fixture.controller.disableTriggers()
        XCTAssertFalse(fixture.amphetamine.state.triggersEnabled)
        XCTAssertEqual(fixture.amphetamine.commands.suffix(2), ["triggers:false", "read"])
    }

    func testSetupReportFailsClosedForUnknownLockPolicy() {
        let fixture = Fixture()
        fixture.screenLock.error = ModeControlError.backend("Unknown output")

        let report = fixture.controller.setupReport()
        XCTAssertFalse(report.immediateScreenLock)
        XCTAssertFalse(report.isReady)
    }

    func testClosedDisplayReadinessTestIsBoundedAndEndsSession() throws {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false

        try fixture.controller.runClosedDisplayReadinessTest()

        XCTAssertTrue(fixture.store.closedDisplayReadinessPassed)
        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
        XCTAssertTrue(fixture.amphetamine.commands.contains("startTimed:1:true"))
        XCTAssertTrue(fixture.amphetamine.commands.contains("closed:true"))
        XCTAssertTrue(fixture.amphetamine.commands.contains("end"))
    }

    func testReadinessFailureAttemptsCleanupAndDoesNotPass() {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false
        fixture.amphetamine.failureCommand = "closed"

        XCTAssertThrowsError(try fixture.controller.runClosedDisplayReadinessTest())
        XCTAssertFalse(fixture.store.closedDisplayReadinessPassed)
        XCTAssertTrue(fixture.amphetamine.commands.contains("end"))
    }
}
