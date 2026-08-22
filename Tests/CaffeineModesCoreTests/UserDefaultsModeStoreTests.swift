import CaffeineModesCore
import Foundation
import XCTest

final class UserDefaultsModeStoreTests: XCTestCase {
    func testDecodesPre101SignatureAsActiveMode() throws {
        let legacy = LegacyOwnedSessionSignature(
            id: UUID(),
            mode: .night,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(OwnedSessionSignature.self, from: data)

        XCTAssertEqual(decoded.id, legacy.id)
        XCTAssertEqual(decoded.mode, .night)
        XCTAssertEqual(decoded.startedAt, legacy.startedAt)
        XCTAssertEqual(decoded.purpose, .activeMode)
        XCTAssertNil(decoded.expectedState)
        XCTAssertTrue(decoded.usesLegacyProjectionFormat)
    }

    func testRoundTripsRequestedModeAndOwnership() {
        let suiteName = "CaffeineModesCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsModeStore(defaults: defaults)
        let mode = OperatingMode.travel(durationMinutes: 60, expiresAt: Date(timeIntervalSince1970: 1234))
        let marker = OwnedSessionSignature(
            id: UUID(),
            mode: mode,
            startedAt: Date(timeIntervalSince1970: 1000),
            purpose: .pendingCleanup,
            expectedState: AmphetamineState(
                sessionIsActive: true,
                displaySleepAllowed: true,
                closedDisplayModeEnabled: true,
                triggersEnabled: false,
                sessionTimeRemainingSeconds: 234
            )
        )

        store.lastRequestedMode = mode
        store.ownedSessionSignature = marker
        store.closedDisplayReadinessPassed = true
        store.launchAtLoginPromptWasShown = true

        let reloaded = UserDefaultsModeStore(defaults: defaults)
        XCTAssertEqual(reloaded.lastRequestedMode, mode)
        XCTAssertEqual(reloaded.ownedSessionSignature, marker)
        XCTAssertEqual(reloaded.ownedSessionSignature?.purpose, .pendingCleanup)
        XCTAssertFalse(reloaded.ownedSessionSignature?.usesLegacyProjectionFormat ?? true)
        XCTAssertTrue(reloaded.closedDisplayReadinessPassed)
        XCTAssertTrue(reloaded.launchAtLoginPromptWasShown)

        reloaded.ownedSessionSignature = nil
        XCTAssertNil(store.ownedSessionSignature)
    }
}

private struct LegacyOwnedSessionSignature: Encodable {
    let id: UUID
    let mode: OperatingMode
    let startedAt: Date
}
