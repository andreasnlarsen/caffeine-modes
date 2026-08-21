import CaffeineModesCore
import XCTest

final class ModeControllerTests: XCTestCase {
    func testWorkUsesFixedOrderAndVerifiesBeforeCommit() throws {
        let fixture = Fixture()
        let snapshot = try fixture.controller.transition(to: .work, replacingUnownedSession: false)

        XCTAssertEqual(
            fixture.amphetamine.commands,
            ["read", "read", "startInfinite:false", "closed:false", "read"]
        )
        XCTAssertEqual(snapshot.requestedMode, .work)
        XCTAssertEqual(snapshot.health, .ready)
        XCTAssertEqual(fixture.store.lastRequestedMode, .work)
        XCTAssertNotNil(fixture.store.ownedSessionSignature)
        XCTAssertEqual(fixture.display.sleepCount, 0)
    }

    func testNightChecksPolicyAndBlockersBeforeMutation() {
        let fixture = Fixture()
        fixture.assertions.blockers = ["Raycast"]

        XCTAssertThrowsError(try fixture.controller.transition(to: .night, replacingUnownedSession: false)) { error in
            XCTAssertEqual(error as? ModeControlError, .displaySleepBlocked(["Raycast"]))
        }
        XCTAssertFalse(fixture.amphetamine.commands.contains(where: { $0.hasPrefix("start") }))
        XCTAssertEqual(fixture.display.sleepCount, 0)
    }

    func testNightSleepsDisplayOnlyAfterAmphetamineVerification() throws {
        let fixture = Fixture()
        let snapshot = try fixture.controller.transition(to: .night, replacingUnownedSession: false)

        XCTAssertEqual(
            fixture.amphetamine.commands,
            ["read", "read", "startInfinite:true", "closed:true", "read"]
        )
        XCTAssertEqual(snapshot.requestedMode, .night)
        XCTAssertEqual(fixture.display.sleepCount, 1)
    }

    func testNightFailsClosedWhenScreenLockIsNotImmediate() {
        let fixture = Fixture()
        fixture.screenLock.immediate = false

        XCTAssertThrowsError(try fixture.controller.transition(to: .night, replacingUnownedSession: false)) { error in
            XCTAssertEqual(error as? ModeControlError, .screenLockNotImmediate)
        }
        XCTAssertEqual(fixture.display.sleepCount, 0)
    }

    func testNightRequiresClosedDisplayReadiness() {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false

        XCTAssertThrowsError(try fixture.controller.transition(to: .night, replacingUnownedSession: false))
        XCTAssertEqual(fixture.display.sleepCount, 0)
    }

    func testTravelAcceptsOnlyAllowedDurationsAndPersistsExpiry() throws {
        let fixture = Fixture()
        let requested = OperatingMode.travel(durationMinutes: 90, expiresAt: .distantPast)
        let snapshot = try fixture.controller.transition(to: requested, replacingUnownedSession: false)

        let expectedExpiry = fixture.clock.now.addingTimeInterval(90 * 60)
        XCTAssertEqual(snapshot.requestedMode, .travel(durationMinutes: 90, expiresAt: expectedExpiry))
        XCTAssertEqual(fixture.store.lastRequestedMode, snapshot.requestedMode)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.mode, snapshot.requestedMode)
        XCTAssertEqual(fixture.amphetamine.commands.suffix(3), ["startTimed:90:true", "closed:true", "read"])
        XCTAssertEqual(fixture.display.sleepCount, 1)
    }

    func testInvalidTravelDurationMutatesNothing() {
        let fixture = Fixture()
        XCTAssertThrowsError(
            try fixture.controller.transition(
                to: .travel(durationMinutes: 45, expiresAt: fixture.clock.now),
                replacingUnownedSession: false
            )
        ) { error in
            XCTAssertEqual(error as? ModeControlError, .invalidTravelDuration(45))
        }
        XCTAssertTrue(fixture.amphetamine.commands.isEmpty)
    }

    func testTravelExpiryReconcilesToOffWhenAmphetamineExpires() throws {
        let fixture = Fixture()
        _ = try fixture.controller.transition(
            to: .travel(durationMinutes: 30, expiresAt: fixture.clock.now),
            replacingUnownedSession: false
        )
        fixture.amphetamine.state = .inactive
        fixture.clock.now.addTimeInterval(31 * 60)

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .off)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testTravelActivePastExpectedExpiryIsBackendMismatch() throws {
        let fixture = Fixture()
        _ = try fixture.controller.transition(
            to: .travel(durationMinutes: 30, expiresAt: fixture.clock.now),
            replacingUnownedSession: false
        )
        fixture.clock.now.addTimeInterval(31 * 60)

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .backendMismatch)
    }

    func testUnownedSessionNeedsExplicitReplacement() {
        let fixture = Fixture()
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )

        XCTAssertThrowsError(try fixture.controller.transition(to: .work, replacingUnownedSession: false)) { error in
            XCTAssertEqual(error as? ModeControlError, .unownedSessionRequiresConfirmation)
        }
        XCTAssertFalse(fixture.amphetamine.commands.contains("startInfinite:false"))
    }

    func testExplicitReplacementCanReplaceUnownedSession() throws {
        let fixture = Fixture()
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )

        let snapshot = try fixture.controller.transition(to: .work, replacingUnownedSession: true)
        XCTAssertEqual(snapshot.requestedMode, .work)
    }

    func testManualAmphetamineChangeInvalidatesOwnership() throws {
        let fixture = Fixture()
        _ = try fixture.controller.transition(to: .work, replacingUnownedSession: false)
        fixture.amphetamine.state.displaySleepAllowed = true

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .conflicted)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testRelaunchReconstructsOwnedNightState() {
        let fixture = Fixture()
        let marker = OwnedSessionSignature(mode: .night, startedAt: fixture.clock.now)
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: true,
            triggersEnabled: false
        )

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .night)
        XCTAssertEqual(snapshot.ownershipMarker, marker)
    }

    func testPartialFailureDoesNotSleepDisplayAndReportsMismatch() {
        let fixture = Fixture()
        let controller = fixture.controller
        fixture.amphetamine.failureCommand = "closed"

        XCTAssertThrowsError(try controller.transition(to: .night, replacingUnownedSession: false))
        XCTAssertEqual(fixture.display.sleepCount, 0)
        let snapshot = controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .backendMismatch)
    }

    func testDisplaySleepFailureLeavesBackendMismatch() {
        let fixture = Fixture()
        let controller = fixture.controller
        fixture.display.error = ModeControlError.backend("Display failed")

        XCTAssertThrowsError(try controller.transition(to: .night, replacingUnownedSession: false))
        let snapshot = controller.reconcile()
        XCTAssertEqual(snapshot.health, .backendMismatch)
    }

    func testOffEndsOwnedSessionEvenWhenTriggersWereManuallyEnabled() throws {
        let fixture = Fixture()
        let marker = OwnedSessionSignature(mode: .work, startedAt: fixture.clock.now)
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: true
        )

        let snapshot = try fixture.controller.transition(to: .off, replacingUnownedSession: false)
        XCTAssertEqual(snapshot.requestedMode, .off)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testQuitEndsAndVerifiesOwnedSession() throws {
        let fixture = Fixture()
        fixture.store.ownedSessionSignature = OwnedSessionSignature(mode: .night, startedAt: fixture.clock.now)
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: true,
            triggersEnabled: false
        )

        try fixture.controller.prepareToQuit()
        XCTAssertTrue(fixture.amphetamine.commands.suffix(2).elementsEqual(["end", "read"]))
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testQuitDoesNotEndUnownedCustomSession() throws {
        let fixture = Fixture()
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )

        try fixture.controller.prepareToQuit()
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
    }

    func testQuitFailureLeavesOwnedMarkerAndThrows() {
        let fixture = Fixture()
        let marker = OwnedSessionSignature(mode: .work, startedAt: fixture.clock.now)
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.refuseToEnd = true

        XCTAssertThrowsError(try fixture.controller.prepareToQuit())
        XCTAssertEqual(fixture.store.ownedSessionSignature, marker)
    }
}
