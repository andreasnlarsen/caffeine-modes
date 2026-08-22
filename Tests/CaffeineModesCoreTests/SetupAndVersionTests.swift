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

        XCTAssertThrowsError(try fixture.controller.transition(to: .work, replacingActiveSession: false)) { error in
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

        XCTAssertThrowsError(try fixture.controller.transition(to: .work, replacingActiveSession: false)) { error in
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

    func testDisableTriggersRecoversPostMutationTimeoutWithinOriginalDeadline() throws {
        let fixture = Fixture()
        fixture.amphetamine.state.triggersEnabled = true
        fixture.amphetamine.timeoutAfterMutationCommand = "triggers"
        fixture.amphetamine.onOperation = { timeout in
            if fixture.amphetamine.receivedTimeouts.count == 1 {
                fixture.monotonicClock.now += timeout
            }
        }

        try fixture.controller.disableTriggers()

        XCTAssertFalse(fixture.amphetamine.state.triggersEnabled)
        XCTAssertEqual(fixture.amphetamine.commands, ["triggers:false", "read"])
        XCTAssertLessThan(fixture.monotonicClock.now, 2)
        XCTAssertGreaterThan(fixture.amphetamine.receivedTimeouts.last ?? 0, 0)
        XCTAssertLessThanOrEqual(fixture.amphetamine.receivedTimeouts.last ?? 1, 0.5)
    }

    func testDisableTriggersThrowsWhenRecoveryStillShowsEnabled() {
        let fixture = Fixture()
        fixture.amphetamine.state.triggersEnabled = true
        fixture.amphetamine.failureCommand = "triggers"

        XCTAssertThrowsError(try fixture.controller.disableTriggers()) { error in
            XCTAssertEqual(
                error as? ModeControlError,
                .backend("Injected triggers failure")
            )
        }
        XCTAssertTrue(fixture.amphetamine.state.triggersEnabled)
        XCTAssertEqual(fixture.amphetamine.commands, ["read"])
    }

    func testSetupReportFailsClosedForUnknownLockPolicy() {
        let fixture = Fixture()
        fixture.screenLock.error = ModeControlError.backend("Unknown output")

        let report = fixture.controller.setupReport()
        XCTAssertFalse(report.immediateScreenLock)
        XCTAssertFalse(report.isReady)
    }

    func testSetupChecksUseIndependentDeadlines() {
        let fixture = Fixture()
        fixture.amphetamine.onOperation = { _ in
            fixture.monotonicClock.now += 2
        }

        let report = fixture.controller.setupReport()

        XCTAssertFalse(report.automationAuthorized)
        XCTAssertTrue(report.immediateScreenLock)
        XCTAssertEqual(fixture.screenLock.callCount, 1)
        XCTAssertEqual(fixture.screenLock.receivedTimeouts, [2])
    }

    func testClosedDisplayReadinessTestUsesABoundedSessionThatExpiresAutomatically() throws {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false

        try fixture.controller.runClosedDisplayReadinessTest(
            authorizingSessionReplacement: true
        )

        XCTAssertTrue(fixture.store.closedDisplayReadinessPassed)
        XCTAssertTrue(fixture.amphetamine.state.sessionIsActive)
        XCTAssertEqual(fixture.amphetamine.state.sessionTimeRemainingSeconds, 60)
        XCTAssertTrue(fixture.amphetamine.commands.contains("startTimed:1:true"))
        XCTAssertTrue(fixture.amphetamine.commands.contains("closed:true"))
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .readinessTest)

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .ready)
        XCTAssertTrue(snapshot.detail?.contains("end automatically") == true)
    }

    func testClosedDisplayReadinessAllowsTimeForInteractiveAmphetaminePrompt() throws {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false
        let sessionStartedAt = fixture.clock.now
        fixture.amphetamine.onStartTimedSession = {
            fixture.monotonicClock.now += 40
            fixture.clock.now.addTimeInterval(40)
            fixture.amphetamine.state.sessionTimeRemainingSeconds = 20
        }

        try fixture.controller.runClosedDisplayReadinessTest(
            authorizingSessionReplacement: true
        )

        XCTAssertTrue(fixture.store.closedDisplayReadinessPassed)
        XCTAssertGreaterThan(fixture.amphetamine.receivedTimeouts[2], 40)
        XCTAssertTrue(fixture.amphetamine.state.sessionIsActive)
        XCTAssertEqual(fixture.amphetamine.state.sessionTimeRemainingSeconds, 20)
        guard case let .travel(_, expiresAt)? = fixture.store.ownedSessionSignature?.mode else {
            return XCTFail("Expected a bounded readiness marker.")
        }
        XCTAssertEqual(expiresAt, sessionStartedAt.addingTimeInterval(60))
    }

    func testClosedDisplayReadinessAnchorsExpiryAfterDelayedSessionCreation() throws {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false
        fixture.amphetamine.onStartTimedSession = {
            fixture.monotonicClock.now += 40
            fixture.clock.now.addTimeInterval(40)
        }

        try fixture.controller.runClosedDisplayReadinessTest(
            authorizingSessionReplacement: true
        )

        guard case let .travel(_, expiresAt)? = fixture.store.ownedSessionSignature?.mode else {
            return XCTFail("Expected a bounded readiness marker.")
        }
        XCTAssertEqual(expiresAt, fixture.clock.now.addingTimeInterval(60))
        XCTAssertTrue(fixture.store.closedDisplayReadinessPassed)
    }

    func testReadinessFailureLeavesTheBoundedSessionToExpire() {
        let fixture = Fixture()
        let controller = fixture.controller
        fixture.store.closedDisplayReadinessPassed = false
        fixture.amphetamine.failureCommand = "closed"

        XCTAssertThrowsError(
            try controller.runClosedDisplayReadinessTest(
                authorizingSessionReplacement: true
            )
        )
        XCTAssertFalse(fixture.store.closedDisplayReadinessPassed)
        XCTAssertTrue(fixture.amphetamine.state.sessionIsActive)
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .pendingCleanup)
        let snapshot = controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .backendMismatch)
        XCTAssertEqual(snapshot.detail, "Injected closed failure")
    }

    func testReadinessLeavesUnexpectedInfiniteSessionUnowned() {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false
        fixture.amphetamine.forcedTimedSessionRemainingSeconds = 0

        XCTAssertThrowsError(
            try fixture.controller.runClosedDisplayReadinessTest(
                authorizingSessionReplacement: true
            )
        )
        XCTAssertFalse(fixture.store.closedDisplayReadinessPassed)
        XCTAssertTrue(fixture.amphetamine.state.sessionIsActive)
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testReadinessSessionReconcilesToOffAfterAmphetamineExpires() throws {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false

        try fixture.controller.runClosedDisplayReadinessTest(
            authorizingSessionReplacement: true
        )
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .readinessTest)

        fixture.clock.now.addTimeInterval(61)
        fixture.amphetamine.state = .inactive
        XCTAssertEqual(fixture.controller.reconcile().requestedMode, .off)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testReadinessActivePastExpectedExpiryIsBackendMismatch() throws {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false

        try fixture.controller.runClosedDisplayReadinessTest(
            authorizingSessionReplacement: true
        )
        fixture.clock.now.addTimeInterval(66)
        fixture.amphetamine.state.sessionTimeRemainingSeconds = 1

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .backendMismatch)
        XCTAssertEqual(
            snapshot.detail,
            "The readiness-test session is active after its expected expiry."
        )
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testReadinessDoesNotClaimAnUnconfirmedStart() {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false
        fixture.amphetamine.timeoutAfterMutationCommand = "startTimed"
        fixture.amphetamine.onOperation = { timeout in
            if fixture.amphetamine.receivedTimeouts.count == 3 {
                fixture.monotonicClock.now += timeout
            }
        }

        XCTAssertThrowsError(
            try fixture.controller.runClosedDisplayReadinessTest(
                authorizingSessionReplacement: true
            )
        )
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
        XCTAssertEqual(fixture.amphetamine.commands.filter { $0 == "read" }.count, 3)
        XCTAssertLessThan(fixture.monotonicClock.now, 45)
        XCTAssertGreaterThan(fixture.amphetamine.receivedTimeouts.last ?? 0, 0)
        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertEqual(fixture.store.lastRequestedMode, .custom)
    }

    func testReadinessClosedDisplayPostMutationErrorRetainsObservedCleanupProjection() {
        let fixture = Fixture()
        let controller = fixture.controller
        fixture.store.closedDisplayReadinessPassed = false
        fixture.amphetamine.errorAfterMutationCommand = "closed"

        XCTAssertThrowsError(
            try controller.runClosedDisplayReadinessTest(
                authorizingSessionReplacement: true
            )
        )

        XCTAssertFalse(fixture.store.closedDisplayReadinessPassed)
        XCTAssertEqual(fixture.amphetamine.commands.filter { $0 == "read" }.count, 3)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .pendingCleanup)
        XCTAssertEqual(
            fixture.store.ownedSessionSignature?.expectedState,
            fixture.amphetamine.state
        )
        let snapshot = controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .backendMismatch)
        XCTAssertEqual(snapshot.detail, "Injected post-mutation closed failure")
    }

    func testReadinessRequiresExplicitSessionReplacementAuthorization() {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false

        XCTAssertThrowsError(
            try fixture.controller.runClosedDisplayReadinessTest(
                authorizingSessionReplacement: false
            )
        ) { error in
            XCTAssertEqual(error as? ModeControlError, .sessionStartRequiresConfirmation)
        }
        XCTAssertFalse(fixture.amphetamine.commands.contains(where: { $0.hasPrefix("start") }))
        XCTAssertFalse(fixture.store.closedDisplayReadinessPassed)
    }
}
