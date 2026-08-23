import AppKit
import XCTest
@testable import CaffeineModesApp

final class ScreenLifecycleTimerTests: XCTestCase {
    @MainActor
    func testTimerFiresWhileMainRunLoopUsesModalPanelMode() {
        let state = TimerState()
        let timer = LifecycleTimerScheduler.schedule(after: 0.01) {
            state.didFire = true
        }
        addTeardownBlock {
            timer.invalidate()
        }

        let deadline = Date().addingTimeInterval(0.5)
        while !state.didFire, Date() < deadline {
            RunLoop.main.run(
                mode: .modalPanel,
                before: Date().addingTimeInterval(0.02)
            )
        }

        XCTAssertTrue(state.didFire)
    }

    @MainActor
    func testInvalidatedTimerDoesNotFireAfterReplacement() {
        let state = TimerState()
        var timer = LifecycleTimerScheduler.schedule(after: 0.01) {
            state.invalidatedTimerDidFire = true
        }
        timer.invalidate()
        timer = LifecycleTimerScheduler.schedule(after: 0.02) {
            state.didFire = true
        }
        addTeardownBlock {
            timer.invalidate()
        }

        let deadline = Date().addingTimeInterval(0.5)
        while !state.didFire, Date() < deadline {
            RunLoop.main.run(
                mode: .modalPanel,
                before: Date().addingTimeInterval(0.02)
            )
        }

        XCTAssertTrue(state.didFire)
        XCTAssertFalse(state.invalidatedTimerDidFire)
    }
}

private final class TimerState: @unchecked Sendable {
    var didFire = false
    var invalidatedTimerDidFire = false
}
