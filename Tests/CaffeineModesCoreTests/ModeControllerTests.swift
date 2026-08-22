import CaffeineModesCore
import XCTest

final class ModeControllerTests: XCTestCase {
    func testWorkUsesFixedOrderAndVerifiesBeforeCommit() throws {
        let fixture = Fixture()
        let snapshot = try fixture.controller.transition(to: .work, replacingActiveSession: true)

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

        XCTAssertThrowsError(try fixture.controller.transition(to: .night, replacingActiveSession: true)) { error in
            XCTAssertEqual(error as? ModeControlError, .displaySleepBlocked(["Raycast"]))
        }
        XCTAssertFalse(fixture.amphetamine.commands.contains(where: { $0.hasPrefix("start") }))
        XCTAssertEqual(fixture.display.sleepCount, 0)
    }

    func testNightDoesNotBlockOnSystemOrDiskAssertions() throws {
        let fixture = Fixture()
        fixture.assertions.report = PowerAssertionReport(
            systemSleepBlockingProcesses: ["ChatGPT", "Claude"],
            diskIdleBlockingProcesses: ["backupd"]
        )

        let snapshot = try fixture.controller.transition(
            to: .night,
            replacingActiveSession: true
        )

        XCTAssertEqual(snapshot.requestedMode, .night)
        XCTAssertEqual(fixture.display.sleepCount, 1)
    }

    func testNightAssertionInspectionUsesTheRemainingTransitionDeadline() {
        let fixture = Fixture()
        fixture.amphetamine.onOperation = { _ in
            fixture.monotonicClock.now += 0.5
        }
        fixture.assertions.onOperation = { timeout in
            XCTAssertEqual(timeout, 1, accuracy: 0.01)
            fixture.monotonicClock.now += 1.1
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .night, replacingActiveSession: true)
        ) { error in
            XCTAssertEqual(error as? ModeControlError, .operationTimedOut)
        }
        XCTAssertFalse(fixture.amphetamine.commands.contains(where: { $0.hasPrefix("start") }))
        XCTAssertEqual(fixture.assertions.receivedTimeouts.count, 1)
    }

    func testNightSleepsDisplayOnlyAfterAmphetamineVerification() throws {
        let fixture = Fixture()
        var markerAtDisplaySleep: OwnedSessionSignature?
        fixture.display.onSleep = {
            markerAtDisplaySleep = fixture.store.ownedSessionSignature
        }
        let snapshot = try fixture.controller.transition(to: .night, replacingActiveSession: true)

        XCTAssertEqual(
            fixture.amphetamine.commands,
            ["read", "read", "startInfinite:true", "closed:true", "read"]
        )
        XCTAssertEqual(snapshot.requestedMode, .night)
        XCTAssertEqual(fixture.display.sleepCount, 1)
        XCTAssertEqual(markerAtDisplaySleep?.purpose, .pendingCleanup)
        XCTAssertEqual(markerAtDisplaySleep?.expectedState, fixture.amphetamine.state)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .activeMode)
    }

    func testNightFailsClosedWhenScreenLockIsNotImmediate() {
        let fixture = Fixture()
        fixture.screenLock.immediate = false

        XCTAssertThrowsError(try fixture.controller.transition(to: .night, replacingActiveSession: true)) { error in
            XCTAssertEqual(error as? ModeControlError, .screenLockNotImmediate)
        }
        XCTAssertEqual(fixture.display.sleepCount, 0)
    }

    func testNightRequiresClosedDisplayReadiness() {
        let fixture = Fixture()
        fixture.store.closedDisplayReadinessPassed = false

        XCTAssertThrowsError(try fixture.controller.transition(to: .night, replacingActiveSession: true))
        XCTAssertEqual(fixture.display.sleepCount, 0)
    }

    func testTravelAcceptsOnlyAllowedDurationsAndPersistsExpiry() throws {
        let fixture = Fixture()
        let requested = OperatingMode.travel(durationMinutes: 90, expiresAt: .distantPast)
        let snapshot = try fixture.controller.transition(to: requested, replacingActiveSession: true)

        let expectedExpiry = fixture.clock.now.addingTimeInterval(90 * 60)
        XCTAssertEqual(snapshot.requestedMode, .travel(durationMinutes: 90, expiresAt: expectedExpiry))
        XCTAssertEqual(fixture.store.lastRequestedMode, snapshot.requestedMode)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.mode, snapshot.requestedMode)
        XCTAssertEqual(fixture.amphetamine.commands.suffix(3), ["startTimed:90:true", "closed:true", "read"])
        XCTAssertEqual(fixture.display.sleepCount, 1)
    }

    func testTravelExpiryUsesVerifiedBackendTimerAfterStartupDelay() throws {
        let fixture = Fixture()
        fixture.amphetamine.onStartTimedSession = {
            fixture.clock.now.addTimeInterval(8)
            fixture.amphetamine.state.sessionTimeRemainingSeconds -= 8
        }

        let snapshot = try fixture.controller.transition(
            to: .travel(durationMinutes: 30, expiresAt: .distantPast),
            replacingActiveSession: true
        )
        let expiry = fixture.clock.now.addingTimeInterval(29 * 60 + 52)

        XCTAssertEqual(snapshot.requestedMode, .travel(durationMinutes: 30, expiresAt: expiry))

        fixture.clock.now.addTimeInterval(29 * 60 + 52)
        fixture.amphetamine.state.sessionTimeRemainingSeconds = 1
        let reconciled = fixture.controller.reconcile()
        XCTAssertEqual(reconciled.requestedMode, snapshot.requestedMode)
        XCTAssertEqual(reconciled.health, .ready)
    }

    func testLegacyTravelProjectionMigratesToObservedBackendTimer() throws {
        let fixture = Fixture()
        let legacyID = UUID()
        let legacyStartedAt = fixture.clock.now.addingTimeInterval(-60)
        let legacy = LegacyTravelOwnedSessionSignature(
            id: legacyID,
            mode: .travel(
                durationMinutes: 30,
                expiresAt: fixture.clock.now.addingTimeInterval(30 * 60)
            ),
            startedAt: legacyStartedAt
        )
        fixture.store.ownedSessionSignature = try JSONDecoder().decode(
            OwnedSessionSignature.self,
            from: JSONEncoder().encode(legacy)
        )
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: true,
            triggersEnabled: false,
            sessionTimeRemainingSeconds: 29 * 60 + 40
        )

        let snapshot = fixture.controller.reconcile()
        let expectedMode = OperatingMode.travel(
            durationMinutes: 30,
            expiresAt: fixture.clock.now.addingTimeInterval(29 * 60 + 40)
        )

        XCTAssertEqual(snapshot.requestedMode, expectedMode)
        XCTAssertEqual(snapshot.health, .ready)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.id, legacyID)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.mode, expectedMode)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.startedAt, legacyStartedAt)
        XCTAssertFalse(fixture.store.ownedSessionSignature?.usesLegacyProjectionFormat ?? true)
    }

    func testInvalidTravelDurationMutatesNothing() {
        let fixture = Fixture()
        XCTAssertThrowsError(
            try fixture.controller.transition(
                to: .travel(durationMinutes: 45, expiresAt: fixture.clock.now),
                replacingActiveSession: true
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
            replacingActiveSession: true
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
            replacingActiveSession: true
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

        XCTAssertThrowsError(try fixture.controller.transition(to: .work, replacingActiveSession: false)) { error in
            XCTAssertEqual(error as? ModeControlError, .activeSessionRequiresConfirmation)
        }
        XCTAssertFalse(fixture.amphetamine.commands.contains("startInfinite:false"))
    }

    func testCustomDetailDescribesProjectionMismatchWithoutOwnershipClaim() {
        let fixture = Fixture()
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )

        let snapshot = fixture.controller.reconcile()

        XCTAssertEqual(
            snapshot.detail,
            "The active Amphetamine session does not match a stored Caffeine Modes projection."
        )
        XCTAssertFalse(snapshot.detail?.localizedCaseInsensitiveContains("own") ?? true)
    }

    func testInactiveSessionStartNeedsExplicitAuthorization() {
        let fixture = Fixture()

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: false)
        ) { error in
            XCTAssertEqual(error as? ModeControlError, .sessionStartRequiresConfirmation)
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

        let snapshot = try fixture.controller.transition(to: .work, replacingActiveSession: true)
        XCTAssertEqual(snapshot.requestedMode, .work)
    }

    func testSessionStartingDuringPreflightRequiresExplicitReplacement() {
        let fixture = Fixture()
        fixture.amphetamine.onRead = { readCount in
            guard readCount == 2 else { return }
            fixture.amphetamine.state = AmphetamineState(
                sessionIsActive: true,
                displaySleepAllowed: true,
                closedDisplayModeEnabled: false,
                triggersEnabled: false
            )
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: false)
        ) { error in
            XCTAssertEqual(error as? ModeControlError, .activeSessionRequiresConfirmation)
        }
        XCTAssertFalse(fixture.amphetamine.commands.contains("startInfinite:false"))
    }

    func testExplicitOffEndsSessionThatStartsDuringPreflight() throws {
        let fixture = Fixture()
        fixture.amphetamine.onRead = { readCount in
            guard readCount == 2 else { return }
            fixture.amphetamine.state = AmphetamineState(
                sessionIsActive: true,
                displaySleepAllowed: true,
                closedDisplayModeEnabled: false,
                triggersEnabled: false
            )
        }

        let snapshot = try fixture.controller.transition(to: .off, replacingActiveSession: true)

        XCTAssertEqual(snapshot.requestedMode, .off)
        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
        XCTAssertTrue(fixture.amphetamine.commands.contains("end"))
    }

    func testManualAmphetamineChangeInvalidatesOwnership() throws {
        let fixture = Fixture()
        _ = try fixture.controller.transition(to: .work, replacingActiveSession: true)
        fixture.amphetamine.state.displaySleepAllowed = true

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .conflicted)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testInfiniteSessionCannotMasqueradeAsOwnedTravel() throws {
        let fixture = Fixture()
        _ = try fixture.controller.transition(
            to: .travel(durationMinutes: 90, expiresAt: fixture.clock.now),
            replacingActiveSession: true
        )
        fixture.amphetamine.state.sessionTimeRemainingSeconds = 0

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .conflicted)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testWrongTimedSessionCannotMasqueradeAsOwnedTravel() throws {
        let fixture = Fixture()
        _ = try fixture.controller.transition(
            to: .travel(durationMinutes: 90, expiresAt: fixture.clock.now),
            replacingActiveSession: true
        )
        fixture.amphetamine.state.sessionTimeRemainingSeconds = 60 * 60

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .conflicted)
    }

    func testTimedSessionCannotMasqueradeAsOwnedWork() throws {
        let fixture = Fixture()
        _ = try fixture.controller.transition(to: .work, replacingActiveSession: true)
        fixture.amphetamine.state.sessionTimeRemainingSeconds = 5 * 60

        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .conflicted)
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

    func testRelaunchRetainsCleanupOwnershipForIncompleteSession() {
        let fixture = Fixture()
        let expectedState = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        let marker = OwnedSessionSignature(
            mode: .night,
            startedAt: fixture.clock.now,
            purpose: .pendingCleanup,
            expectedState: expectedState
        )
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = expectedState

        let snapshot = fixture.controller.reconcile()

        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .backendMismatch)
        XCTAssertEqual(snapshot.ownershipMarker, marker)
    }

    func testPartialFailureDoesNotSleepDisplayAndReportsMismatch() {
        let fixture = Fixture()
        let controller = fixture.controller
        fixture.amphetamine.failureCommand = "closed"

        XCTAssertThrowsError(try controller.transition(to: .night, replacingActiveSession: true))
        XCTAssertEqual(fixture.display.sleepCount, 0)
        let snapshot = controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .backendMismatch)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .pendingCleanup)
        XCTAssertEqual(
            fixture.store.ownedSessionSignature?.expectedState,
            fixture.amphetamine.state
        )

        fixture.amphetamine.failureCommand = nil
        XCTAssertNoThrow(try controller.endActiveSessionForQuit())
        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
    }

    func testFailedReplacementInvalidatesPriorProjectionWhenStartIsUnconfirmed() {
        let fixture = Fixture()
        let marker = OwnedSessionSignature(mode: .work, startedAt: fixture.clock.now)
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.failureCommand = "startInfinite"

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .night, replacingActiveSession: true)
        )

        XCTAssertNil(fixture.store.ownedSessionSignature)
        fixture.amphetamine.failureCommand = nil
        XCTAssertNoThrow(try fixture.controller.endActiveSessionForQuit())
        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
    }

    func testSameModeStartErrorAfterMutationInvalidatesPriorProjection() {
        let fixture = Fixture()
        let marker = OwnedSessionSignature(mode: .work, startedAt: fixture.clock.now)
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.errorAfterMutationCommand = "startInfinite"

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: true)
        )

        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertEqual(fixture.controller.reconcile().health, .conflicted)
    }

    func testFailedStartDoesNotClaimUnchangedUnownedSession() {
        let fixture = Fixture()
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.failureCommand = "startInfinite"

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: true)
        )

        XCTAssertNil(fixture.store.ownedSessionSignature)
        fixture.amphetamine.failureCommand = nil
        let snapshot = fixture.controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .conflicted)
    }

    func testFailedSameModeMutationRetainsOnlyCleanupOwnership() throws {
        let fixture = Fixture()
        _ = try fixture.controller.transition(to: .night, replacingActiveSession: true)
        fixture.amphetamine.onRead = { count in
            if count >= 6 {
                fixture.amphetamine.readError = ModeControlError.backend("Injected read failure")
            }
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .night, replacingActiveSession: true)
        )

        XCTAssertEqual(fixture.display.sleepCount, 1)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .pendingCleanup)

        fixture.amphetamine.readError = nil
        fixture.amphetamine.onRead = nil
        let relaunched = fixture.controller.reconcile()
        XCTAssertEqual(relaunched.requestedMode, .custom)
        XCTAssertEqual(relaunched.health, .backendMismatch)
    }

    func testFailedOffVerificationRetainsPriorOwnedSession() {
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

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .off, replacingActiveSession: true)
        )

        XCTAssertEqual(fixture.store.ownedSessionSignature, marker)
    }

    func testInactiveStateClearsStaleMutationFailure() {
        let fixture = Fixture()
        let controller = fixture.controller
        fixture.amphetamine.failureCommand = "closed"
        XCTAssertThrowsError(try controller.transition(to: .night, replacingActiveSession: true))

        fixture.amphetamine.failureCommand = nil
        fixture.amphetamine.state = .inactive
        let snapshot = controller.reconcile()

        XCTAssertEqual(snapshot.requestedMode, .off)
        XCTAssertEqual(snapshot.health, .ready)
    }

    func testDisplaySleepFailurePreservesOwnershipForQuit() throws {
        let fixture = Fixture()
        let controller = fixture.controller
        fixture.display.error = ModeControlError.backend("Display failed")

        XCTAssertThrowsError(try controller.transition(to: .night, replacingActiveSession: true))
        let snapshot = controller.reconcile()
        XCTAssertEqual(snapshot.health, .backendMismatch)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .pendingCleanup)
        let relaunchedSnapshot = fixture.controller.reconcile()
        XCTAssertEqual(relaunchedSnapshot.requestedMode, .custom)
        XCTAssertEqual(relaunchedSnapshot.health, .backendMismatch)

        try controller.endActiveSessionForQuit()
        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testTransitionUsesOneEndToEndDeadline() throws {
        let fixture = Fixture()
        fixture.amphetamine.onOperation = { _ in
            fixture.monotonicClock.now += 0.45
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: true)
        ) { error in
            guard case let ModeControlError.backend(detail) = error else {
                return XCTFail("Expected a backend timeout error.")
            }
            XCTAssertTrue(detail.contains("safety deadline"))
        }
        XCTAssertEqual(fixture.display.sleepCount, 0)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .pendingCleanup)
        let transitionTimeouts = fixture.amphetamine.receivedTimeouts
        XCTAssertEqual(transitionTimeouts.count, 5)
        XCTAssertGreaterThan(transitionTimeouts[0], transitionTimeouts[1])
        XCTAssertGreaterThan(transitionTimeouts[1], transitionTimeouts[2])
        XCTAssertGreaterThan(transitionTimeouts[2], transitionTimeouts[3])
        XCTAssertGreaterThan(transitionTimeouts[3], 0)
        XCTAssertGreaterThan(transitionTimeouts[4], transitionTimeouts[3])

        fixture.amphetamine.onOperation = nil
        try fixture.controller.endActiveSessionForQuit()
        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
    }

    func testFailedStartDoesNotClaimUnrelatedRecoveryState() {
        let fixture = Fixture()
        fixture.amphetamine.errorAfterMutationCommand = "startInfinite"
        fixture.amphetamine.onRead = { count in
            guard count == 3 else { return }
            fixture.amphetamine.state = AmphetamineState(
                sessionIsActive: true,
                displaySleepAllowed: true,
                closedDisplayModeEnabled: true,
                triggersEnabled: false
            )
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: true)
        )

        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
    }

    func testCompletedStartDoesNotClaimUnrelatedRecoveryState() {
        let fixture = Fixture()
        fixture.amphetamine.failureCommand = "closed"
        fixture.amphetamine.onRead = { count in
            guard count == 3 else { return }
            fixture.amphetamine.state = AmphetamineState(
                sessionIsActive: true,
                displaySleepAllowed: true,
                closedDisplayModeEnabled: true,
                triggersEnabled: false
            )
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: true)
        )

        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
    }

    func testCompletedStartRetainsFallbackOwnershipWhenRecoveryReadFails() throws {
        let fixture = Fixture()
        fixture.amphetamine.failureCommand = "closed"
        fixture.amphetamine.onRead = { count in
            if count >= 3 {
                fixture.amphetamine.readError = ModeControlError.backend("Injected read failure")
            }
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: true)
        )
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .pendingCleanup)

        fixture.amphetamine.failureCommand = nil
        fixture.amphetamine.readError = nil
        fixture.amphetamine.onRead = nil
        try fixture.controller.endActiveSessionForQuit()
        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
    }

    func testAmbiguousStartTimeoutDoesNotClaimTheObservedSession() {
        let fixture = Fixture()
        fixture.amphetamine.timeoutAfterMutationCommand = "startInfinite"
        fixture.amphetamine.onOperation = { timeout in
            if fixture.amphetamine.receivedTimeouts.count == 3 {
                fixture.monotonicClock.now += timeout
            }
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .work, replacingActiveSession: true)
        )

        XCTAssertEqual(fixture.amphetamine.commands.filter { $0 == "read" }.count, 3)
        XCTAssertLessThan(fixture.monotonicClock.now, 2)
        XCTAssertGreaterThan(fixture.amphetamine.receivedTimeouts.last ?? 0, 0)
        XCTAssertTrue(fixture.amphetamine.state.sessionIsActive)
        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertEqual(fixture.controller.reconcile().health, .conflicted)
    }

    func testExplicitQuitEndDoesNotDependOnCleanupProjection() throws {
        let fixture = Fixture()
        let expectedState = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.store.ownedSessionSignature = OwnedSessionSignature(
            mode: .night,
            startedAt: fixture.clock.now,
            purpose: .pendingCleanup,
            expectedState: expectedState
        )
        fixture.amphetamine.state = expectedState
        fixture.amphetamine.state.closedDisplayModeEnabled = true

        try fixture.controller.endActiveSessionForQuit()

        XCTAssertTrue(fixture.amphetamine.commands.contains("end"))
        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertEqual(fixture.store.lastRequestedMode, .off)
    }

    func testExplicitQuitEndDoesNotDependOnTimedProjection() throws {
        let fixture = Fixture()
        let expectedState = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: true,
            triggersEnabled: false,
            sessionTimeRemainingSeconds: 30 * 60
        )
        fixture.store.ownedSessionSignature = OwnedSessionSignature(
            mode: .travel(
                durationMinutes: 30,
                expiresAt: fixture.clock.now.addingTimeInterval(30 * 60)
            ),
            startedAt: fixture.clock.now,
            purpose: .pendingCleanup,
            expectedState: expectedState
        )
        fixture.amphetamine.state = expectedState
        fixture.amphetamine.state.sessionTimeRemainingSeconds = 60 * 60

        try fixture.controller.endActiveSessionForQuit()

        XCTAssertTrue(fixture.amphetamine.commands.contains("end"))
        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertEqual(fixture.store.lastRequestedMode, .off)
    }

    func testAmbiguousOffTimeoutClearsMarkerAfterFreshInactiveObservation() {
        let fixture = Fixture()
        let marker = OwnedSessionSignature(mode: .work, startedAt: fixture.clock.now)
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.timeoutAfterMutationCommand = "end"

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .off, replacingActiveSession: true)
        )
        XCTAssertNil(fixture.store.ownedSessionSignature)

        XCTAssertEqual(fixture.controller.reconcile().requestedMode, .off)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testFailedOffWithoutCleanupObservationInvalidatesOwnership() {
        let fixture = Fixture()
        fixture.store.ownedSessionSignature = OwnedSessionSignature(
            mode: .work,
            startedAt: fixture.clock.now
        )
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.refuseToEnd = true
        fixture.amphetamine.onRead = { count in
            if count >= 3 {
                fixture.amphetamine.readError = ModeControlError.backend("Injected read failure")
            }
        }

        XCTAssertThrowsError(
            try fixture.controller.transition(to: .off, replacingActiveSession: true)
        )
        XCTAssertNil(fixture.store.ownedSessionSignature)

        fixture.amphetamine.readError = nil
        fixture.amphetamine.onRead = nil
        let relaunched = fixture.controller.reconcile()
        XCTAssertEqual(relaunched.requestedMode, .custom)
        XCTAssertEqual(relaunched.health, .conflicted)
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

        let snapshot = try fixture.controller.transition(to: .off, replacingActiveSession: true)
        XCTAssertEqual(snapshot.requestedMode, .off)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testQuitInspectionReportsActiveWithoutEndingIt() throws {
        let fixture = Fixture()
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )

        XCTAssertTrue(try fixture.controller.hasActiveSessionForQuit())
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
        XCTAssertTrue(fixture.amphetamine.state.sessionIsActive)
    }

    func testQuitInspectionRejectsUnsupportedAmphetamineBeforeRead() {
        let fixture = Fixture()
        fixture.amphetamine.installedVersion = "5.3.1"

        XCTAssertThrowsError(try fixture.controller.hasActiveSessionForQuit()) { error in
            XCTAssertEqual(
                error as? ModeControlError,
                .unsupportedVersion(found: "5.3.1")
            )
        }
        XCTAssertTrue(fixture.amphetamine.commands.isEmpty)
    }

    func testExplicitQuitEndEndsAndVerifiesAnyActiveSession() throws {
        let fixture = Fixture()
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )

        try fixture.controller.endActiveSessionForQuit()
        XCTAssertTrue(fixture.amphetamine.commands.suffix(2).elementsEqual(["end", "read"]))
        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
        XCTAssertNil(fixture.store.ownedSessionSignature)
    }

    func testQuitRecoversPostMutationTimeoutAndFinalizesVerifiedOff() throws {
        let fixture = Fixture()
        fixture.store.ownedSessionSignature = OwnedSessionSignature(
            mode: .work,
            startedAt: fixture.clock.now
        )
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.timeoutAfterMutationCommand = "end"
        fixture.amphetamine.onOperation = { timeout in
            if fixture.amphetamine.receivedTimeouts.count == 2 {
                fixture.monotonicClock.now += timeout
            }
        }

        try fixture.controller.endActiveSessionForQuit()

        XCTAssertFalse(fixture.amphetamine.state.sessionIsActive)
        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertEqual(fixture.store.lastRequestedMode, .off)
        XCTAssertTrue(fixture.amphetamine.commands.suffix(2).elementsEqual(["end", "read"]))
        XCTAssertLessThan(fixture.monotonicClock.now, 2)
        XCTAssertGreaterThan(fixture.amphetamine.receivedTimeouts.last ?? 0, 0)
        XCTAssertLessThanOrEqual(fixture.amphetamine.receivedTimeouts.last ?? 1, 0.5)
    }

    func testQuitEndRejectsUnsupportedAmphetamineBeforeMutation() {
        let fixture = Fixture()
        fixture.amphetamine.installedVersion = "5.3.1"
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: true,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )

        XCTAssertThrowsError(try fixture.controller.endActiveSessionForQuit()) { error in
            XCTAssertEqual(
                error as? ModeControlError,
                .unsupportedVersion(found: "5.3.1")
            )
        }
        XCTAssertTrue(fixture.amphetamine.commands.isEmpty)
        XCTAssertTrue(fixture.amphetamine.state.sessionIsActive)
    }

    func testQuitInspectionClearsStaleMarkerWhenNoSessionIsActive() throws {
        let fixture = Fixture()
        fixture.store.ownedSessionSignature = OwnedSessionSignature(mode: .work, startedAt: fixture.clock.now)
        fixture.amphetamine.state = .inactive

        XCTAssertFalse(try fixture.controller.hasActiveSessionForQuit())

        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
        XCTAssertNil(fixture.store.ownedSessionSignature)
        XCTAssertEqual(fixture.store.lastRequestedMode, .off)
    }

    func testQuitFailureLeavesOwnedMarkerAndThrows() {
        let fixture = Fixture()
        let controller = fixture.controller
        let marker = OwnedSessionSignature(mode: .work, startedAt: fixture.clock.now)
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.refuseToEnd = true

        XCTAssertThrowsError(try controller.endActiveSessionForQuit())
        XCTAssertEqual(fixture.store.ownedSessionSignature?.id, marker.id)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.mode, marker.mode)
        XCTAssertEqual(fixture.store.ownedSessionSignature?.purpose, .pendingCleanup)
        XCTAssertEqual(fixture.amphetamine.commands.filter { $0 == "read" }.count, 3)

        let snapshot = controller.reconcile()
        XCTAssertEqual(snapshot.requestedMode, .custom)
        XCTAssertEqual(snapshot.health, .backendMismatch)
        XCTAssertEqual(
            snapshot.detail,
            "Caffeine Modes could not verify Off, so it will remain open."
        )

        let relaunchedSnapshot = fixture.controller.reconcile()
        XCTAssertEqual(relaunchedSnapshot.requestedMode, .custom)
        XCTAssertEqual(relaunchedSnapshot.health, .backendMismatch)
    }

    func testQuitStaysOpenWhenOwnedSessionCannotBeRead() {
        let fixture = Fixture()
        let marker = OwnedSessionSignature(mode: .work, startedAt: fixture.clock.now)
        fixture.store.ownedSessionSignature = marker
        fixture.amphetamine.state = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: false,
            closedDisplayModeEnabled: false,
            triggersEnabled: false
        )
        fixture.amphetamine.readError = ModeControlError.automationDenied

        XCTAssertThrowsError(try fixture.controller.endActiveSessionForQuit())
        XCTAssertEqual(fixture.store.ownedSessionSignature, marker)
        XCTAssertFalse(fixture.amphetamine.commands.contains("end"))
    }
}

private struct LegacyTravelOwnedSessionSignature: Encodable {
    let id: UUID
    let mode: OperatingMode
    let startedAt: Date
}
