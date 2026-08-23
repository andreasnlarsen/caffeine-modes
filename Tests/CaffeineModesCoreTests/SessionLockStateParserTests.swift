import CaffeineModesAppSupport
import XCTest

final class SessionLockStateParserTests: XCTestCase {
    func testMissingLockKeyMeansUnlocked() {
        XCTAssertEqual(SessionLockStateParser.isLocked(from: nil), false)
    }

    func testBooleanAndNumberLockValuesAreParsed() {
        XCTAssertEqual(SessionLockStateParser.isLocked(from: true), true)
        XCTAssertEqual(SessionLockStateParser.isLocked(from: false), false)
        XCTAssertEqual(SessionLockStateParser.isLocked(from: NSNumber(value: 1)), true)
        XCTAssertEqual(SessionLockStateParser.isLocked(from: NSNumber(value: 0)), false)
    }

    func testUnknownLockValueFailsClosed() {
        XCTAssertNil(SessionLockStateParser.isLocked(from: "locked"))
    }
}
