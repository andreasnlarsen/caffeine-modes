import CaffeineModesCore
import Foundation
import XCTest

final class UserDefaultsModeStoreTests: XCTestCase {
    func testRoundTripsRequestedModeAndOwnership() {
        let suiteName = "CaffeineModesCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsModeStore(defaults: defaults)
        let mode = OperatingMode.travel(durationMinutes: 60, expiresAt: Date(timeIntervalSince1970: 1234))
        let marker = OwnedSessionSignature(id: UUID(), mode: mode, startedAt: Date(timeIntervalSince1970: 1000))

        store.lastRequestedMode = mode
        store.ownedSessionSignature = marker
        store.closedDisplayReadinessPassed = true
        store.launchAtLoginPromptWasShown = true

        let reloaded = UserDefaultsModeStore(defaults: defaults)
        XCTAssertEqual(reloaded.lastRequestedMode, mode)
        XCTAssertEqual(reloaded.ownedSessionSignature, marker)
        XCTAssertTrue(reloaded.closedDisplayReadinessPassed)
        XCTAssertTrue(reloaded.launchAtLoginPromptWasShown)

        reloaded.ownedSessionSignature = nil
        XCTAssertNil(store.ownedSessionSignature)
    }
}
