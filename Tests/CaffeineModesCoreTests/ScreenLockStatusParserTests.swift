import CaffeineModesCore
import XCTest

final class ScreenLockStatusParserTests: XCTestCase {
    func testZeroDeviceGracePeriodIsImmediate() throws {
        XCTAssertTrue(try ScreenLockStatusParser.isImmediate(deviceGracePeriodSeconds: 0))
    }

    func testPositiveDeviceGracePeriodIsNotImmediate() throws {
        XCTAssertFalse(try ScreenLockStatusParser.isImmediate(deviceGracePeriodSeconds: 1))
        XCTAssertFalse(try ScreenLockStatusParser.isImmediate(deviceGracePeriodSeconds: 300))
    }

    func testUnknownDeviceGracePeriodFailsClosed() {
        for value in [nil, -1] as [Int?] {
            XCTAssertThrowsError(
                try ScreenLockStatusParser.isImmediate(deviceGracePeriodSeconds: value)
            ) { error in
                XCTAssertEqual(
                    error as? ModeControlError,
                    .backend("macOS returned an unknown screen-lock grace period.")
                )
            }
        }
    }

    func testExplicitImmediateDelayIsImmediate() throws {
        let output = "Getting screenlock state\n screenLock delay is immediate\n"
        XCTAssertTrue(try ScreenLockStatusParser.isImmediate(fromStatusOutput: output))
    }

    func testExplicitDelayInSecondsIsNotImmediate() throws {
        XCTAssertFalse(
            try ScreenLockStatusParser.isImmediate(fromStatusOutput: " screenLock delay is 60 seconds")
        )
        XCTAssertFalse(
            try ScreenLockStatusParser.isImmediate(fromStatusOutput: "screenLock delay is 1 second")
        )
    }

    func testExplicitOffIsNotImmediate() throws {
        XCTAssertFalse(try ScreenLockStatusParser.isImmediate(fromStatusOutput: " screenLock is off"))
    }

    func testUnrecognizedScreenLockWordingFailsClosed() {
        XCTAssertThrowsError(
            try ScreenLockStatusParser.isImmediate(fromStatusOutput: "screenLock policy is managed")
        ) { error in
            XCTAssertEqual(
                error as? ModeControlError,
                .backend("macOS returned an unknown screen-lock status.")
            )
        }
    }

    func testEmptyOutputFailsClosed() {
        XCTAssertThrowsError(try ScreenLockStatusParser.isImmediate(fromStatusOutput: ""))
    }
}
