import CaffeineModesAppSupport
import CaffeineModesCore
import XCTest

final class AwayModeWakeStateMachineTests: XCTestCase {
    func testWakeInNightChecksLockAndArmsThirtySecondResleep() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(to: .night)

        XCTAssertEqual(machine.screensDidWake(now: 100), .checkLockState)
        XCTAssertEqual(machine.resleepDeadline, 130)
        XCTAssertEqual(machine.lockStateObserved(isLocked: true, now: 100), .none)
        XCTAssertEqual(machine.timerFired(now: 129.9), .none)
        XCTAssertEqual(machine.timerFired(now: 130), .resleepDisplay)
        XCTAssertNil(machine.resleepDeadline)
    }

    func testDisplayConfigurationChangeInNightChecksLockAndArmsResleep() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(to: .night)

        XCTAssertEqual(
            machine.displayConfigurationDidChange(now: 100),
            .checkLockState
        )
        XCTAssertEqual(machine.resleepDeadline, 130)
    }

    func testDisplayConfigurationChangeOutsideAwayModeDoesNothing() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(to: .work)

        XCTAssertEqual(
            machine.displayConfigurationDidChange(now: 100),
            .none
        )
        XCTAssertNil(machine.resleepDeadline)
    }

    func testTravelNeverArmsDisplayResleepAfterWakeOrDisplayReconnect() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(
            to: .travel(durationMinutes: 90, expiresAt: .distantFuture)
        )

        XCTAssertEqual(machine.screensDidWake(now: 100), .none)
        XCTAssertEqual(machine.displayConfigurationDidChange(now: 110), .none)
        XCTAssertNil(machine.resleepDeadline)
        XCTAssertEqual(machine.timerFired(now: 200), .none)
    }

    func testUnlockEndsNightAndCancelsResleep() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(to: .night)
        _ = machine.screensDidWake(now: 100)

        XCTAssertEqual(machine.lockStateObserved(isLocked: false, now: 101), .finishAfterUnlock)
        XCTAssertNil(machine.resleepDeadline)
        XCTAssertEqual(machine.timerFired(now: 140), .none)
    }

    func testVerifiedUnlockSnapshotCancelsResleepWhileAwayModeRemainsActive() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(to: .night)
        _ = machine.screensDidWake(now: 100)

        machine.verifiedUnlockObserved()
        _ = machine.modeDidChange(to: .night)

        XCTAssertNil(machine.resleepDeadline)
        XCTAssertEqual(machine.timerFired(now: 140), .none)
    }

    func testWakeOutsideAwayModeDoesNothing() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(to: .work)

        XCTAssertEqual(machine.screensDidWake(now: 100), .none)
        XCTAssertNil(machine.resleepDeadline)
    }

    func testModeChangeAndScreenSleepCancelPendingResleep() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(to: .travel(durationMinutes: 90, expiresAt: .distantFuture))
        _ = machine.screensDidWake(now: 100)
        machine.screensDidSleep()
        XCTAssertNil(machine.resleepDeadline)

        _ = machine.screensDidWake(now: 200)
        _ = machine.modeDidChange(to: .off)
        XCTAssertNil(machine.resleepDeadline)
        XCTAssertEqual(machine.timerFired(now: 240), .none)
    }

    func testFirstObservedAwayModeRequestsLiveLockCheck() {
        var machine = AwayModeWakeStateMachine()

        XCTAssertEqual(
            machine.modeDidChange(to: .night, restoredSession: true, now: 100),
            .checkLockState
        )
        XCTAssertEqual(machine.resleepDeadline, 130)
        XCTAssertEqual(machine.modeDidChange(to: .night), .none)
    }

    func testNewAwayModeDoesNotLookLikeRestorationWithoutAnEarlierObservation() {
        var machine = AwayModeWakeStateMachine()

        XCTAssertEqual(machine.modeDidChange(to: .night, now: 100), .none)
        XCTAssertNil(machine.resleepDeadline)
    }

    func testConsumedResleepDeadlineDoesNotCreateIdlePolling() {
        var machine = AwayModeWakeStateMachine()
        _ = machine.modeDidChange(to: .night)
        _ = machine.screensDidWake(now: 100)
        XCTAssertEqual(machine.timerFired(now: 130), .resleepDisplay)

        XCTAssertNil(machine.resleepDeadline)
        XCTAssertEqual(machine.timerFired(now: 160), .none)
    }
}
