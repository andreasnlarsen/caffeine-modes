@testable import CaffeineModesApp
import CaffeineModesCore
import XCTest

final class SystemDisplayStateInspectorTests: XCTestCase {
    func testDisplayStateClassificationFailsClosedWhenCollectionIsUnavailable() {
        XCTAssertEqual(SystemDisplayStateInspector.classify(asleepStates: nil), .unavailable)
    }

    func testDisplayStateClassificationRequiresEveryOnlineDisplayToBeAsleep() {
        XCTAssertEqual(SystemDisplayStateInspector.classify(asleepStates: []), .unavailable)
        XCTAssertEqual(SystemDisplayStateInspector.classify(asleepStates: [true, true]), .allAsleep)
        XCTAssertEqual(SystemDisplayStateInspector.classify(asleepStates: [true, false]), .visible)
    }
}
