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
        store.postUnlockMode = .work
        store.batteryProtectionRequirement = BatteryProtectionRequirement(
            isRequired: false,
            thresholdPercent: 25
        )

        let reloaded = UserDefaultsModeStore(defaults: defaults)
        XCTAssertEqual(reloaded.lastRequestedMode, mode)
        XCTAssertEqual(reloaded.ownedSessionSignature, marker)
        XCTAssertEqual(reloaded.ownedSessionSignature?.purpose, .pendingCleanup)
        XCTAssertFalse(reloaded.ownedSessionSignature?.usesLegacyProjectionFormat ?? true)
        XCTAssertTrue(reloaded.closedDisplayReadinessPassed)
        XCTAssertTrue(reloaded.launchAtLoginPromptWasShown)
        XCTAssertEqual(reloaded.postUnlockMode, .work)
        XCTAssertEqual(
            reloaded.batteryProtectionRequirement,
            BatteryProtectionRequirement(isRequired: false, thresholdPercent: 25)
        )

        reloaded.ownedSessionSignature = nil
        XCTAssertNil(store.ownedSessionSignature)
    }

    func testPostUnlockModeDefaultsToOff() {
        let suiteName = "UserDefaultsModeStoreTests-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(UserDefaultsModeStore(defaults: defaults).postUnlockMode, .off)
    }

    func testBatteryProtectionDefaultsRequiredAtFifteenPercent() {
        let suiteName = "UserDefaultsModeStoreTests-battery-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            UserDefaultsModeStore(defaults: defaults).batteryProtectionRequirement,
            .defaultValue
        )
    }

    func testInvalidStoredLowBatteryThresholdFallsBackToFifteenPercent() throws {
        let suiteName = "UserDefaultsModeStoreTests-battery-invalid-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "isRequired": false,
                "thresholdPercent": 99
            ]),
            forKey: "batteryProtectionRequirement"
        )

        XCTAssertEqual(
            UserDefaultsModeStore(defaults: defaults).batteryProtectionRequirement,
            BatteryProtectionRequirement(isRequired: false, thresholdPercent: 15)
        )
    }
}

private struct LegacyOwnedSessionSignature: Encodable {
    let id: UUID
    let mode: OperatingMode
    let startedAt: Date
}
