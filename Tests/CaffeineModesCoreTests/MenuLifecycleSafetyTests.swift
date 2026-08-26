import CaffeineModesCore
import XCTest
@testable import CaffeineModesApp

@MainActor
final class MenuLifecycleSafetyTests: XCTestCase {
    func testDegradedNightResleepRequiresRetryWithoutCreatingAVisibleError() {
        let snapshot = ModeSnapshot(
            requestedMode: .night,
            observedState: nil,
            ownershipMarker: nil,
            health: .ready,
            safety: .nightDisplaysVisible
        )

        XCTAssertFalse(
            ScreenLifecycleController.completionSucceeded(
                for: .resleep,
                snapshot: snapshot
            )
        )
    }

    func testVerifiedUnlockDoesNotScheduleANightResleepRetry() {
        let snapshot = ModeSnapshot(
            requestedMode: .night,
            observedState: nil,
            ownershipMarker: nil,
            health: .ready,
            safety: .nightUnlocked,
            requiresPostUnlockChoice: true
        )

        XCTAssertTrue(
            ScreenLifecycleController.completionSucceeded(
                for: .resleep,
                snapshot: snapshot
            )
        )
    }

    func testTravelSelectionCanReadAFreshAssertionSnapshot() async {
        let fixture = Fixture()
        let runner = MenuControllerRunner(
            controller: fixture.controller,
            assertions: fixture.assertions
        )
        fixture.assertions.blockers = ["Old Process"]
        _ = await runner.fetchPowerReport()
        fixture.assertions.blockers = ["Polytopia"]

        let fresh = await runner.fetchPowerReport()

        XCTAssertEqual(fresh?.displaySleepBlockingProcesses, ["Polytopia"])
        XCTAssertEqual(fixture.assertions.callCount, 2)
    }
}
