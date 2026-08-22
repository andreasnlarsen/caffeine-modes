import CaffeineModesCore
import XCTest

final class TravelCountdownFormatterTests: XCTestCase {
    func testRoundsTotalMinutesBeforeSplittingHours() {
        XCTAssertEqual(TravelCountdownFormatter.string(seconds: 7_199), "2h 0m")
        XCTAssertEqual(TravelCountdownFormatter.string(seconds: 7_140), "1h 59m")
        XCTAssertEqual(TravelCountdownFormatter.string(seconds: 3_599), "1h 0m")
        XCTAssertEqual(TravelCountdownFormatter.string(seconds: 59), "1m")
        XCTAssertEqual(TravelCountdownFormatter.string(seconds: 0), "0m")
    }
}
