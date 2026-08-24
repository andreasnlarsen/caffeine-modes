@testable import CaffeineModesApp
import CaffeineModesCore
import Foundation
import XCTest

final class AmphetamineBatteryProtectionInspectorTests: XCTestCase {
    private let valid: [String: Any] = [
        "End Session On Low Battery": true,
        "Low Battery Percent": 15,
        "Always Ask to End For Low Battery": false,
        "Ignore Battery on AC": true
    ]

    func testMapsTheKnownAmphetaminePreferenceProjection() {
        XCTAssertEqual(
            AmphetamineBatteryProtectionInspector.configuration(from: valid),
            AmphetamineBatteryProtectionConfiguration(
                endsSessionOnLowBattery: true,
                thresholdPercent: 15,
                promptsBeforeEnding: false,
                ignoresLimitOnExternalPower: true
            )
        )
    }

    func testMapsAmphetaminesIntegerBackedBooleanEncoding() throws {
        let integerBacked: [String: Any] = [
            "End Session On Low Battery": 1,
            "Low Battery Percent": 15,
            "Always Ask to End For Low Battery": 0,
            "Ignore Battery on AC": 1
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: integerBacked,
            format: .binary,
            options: 0
        )
        let decoded = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            AmphetamineBatteryProtectionInspector.configuration(from: decoded),
            AmphetamineBatteryProtectionConfiguration(
                endsSessionOnLowBattery: true,
                thresholdPercent: 15,
                promptsBeforeEnding: false,
                ignoresLimitOnExternalPower: true
            )
        )
    }

    func testFailsClosedForMissingMalformedOrOutOfRangeValues() {
        for key in valid.keys {
            var dictionary = valid
            dictionary.removeValue(forKey: key)
            XCTAssertNil(AmphetamineBatteryProtectionInspector.configuration(from: dictionary))
        }

        let malformedValues: [(String, Any)] = [
            ("End Session On Low Battery", 2),
            ("End Session On Low Battery", 1.0),
            ("Low Battery Percent", 15.0),
            ("Low Battery Percent", 15.5),
            ("Low Battery Percent", 101),
            ("Always Ask to End For Low Battery", "false"),
            ("Ignore Battery on AC", -1),
            ("Ignore Battery on AC", 0.0)
        ]
        for (key, value) in malformedValues {
            var dictionary = valid
            dictionary[key] = value
            XCTAssertNil(AmphetamineBatteryProtectionInspector.configuration(from: dictionary))
        }
    }

    func testInspectReadsOneSynchronizedSnapshot() {
        var events: [String] = []
        let inspector = AmphetamineBatteryProtectionInspector(
            synchronize: {
                events.append("synchronize")
                return true
            },
            readSnapshot: {
                events.append("read")
                return self.valid
            }
        )

        XCTAssertEqual(
            try inspector.inspect(timeout: 1),
            AmphetamineBatteryProtectionConfiguration(
                endsSessionOnLowBattery: true,
                thresholdPercent: 15,
                promptsBeforeEnding: false,
                ignoresLimitOnExternalPower: true
            )
        )
        XCTAssertEqual(events, ["synchronize", "read"])
    }

    func testFailedSynchronizationFailsClosedWithoutReading() {
        var readCount = 0
        let inspector = AmphetamineBatteryProtectionInspector(
            synchronize: { false },
            readSnapshot: {
                readCount += 1
                return self.valid
            }
        )

        XCTAssertNil(try inspector.inspect(timeout: 1))
        XCTAssertEqual(readCount, 0)
    }

    func testMissingOrMalformedSynchronizedSnapshotFailsClosed() {
        let missing = AmphetamineBatteryProtectionInspector(
            synchronize: { true },
            readSnapshot: { nil }
        )
        let malformed = AmphetamineBatteryProtectionInspector(
            synchronize: { true },
            readSnapshot: { [:] }
        )

        XCTAssertNil(try missing.inspect(timeout: 1))
        XCTAssertNil(try malformed.inspect(timeout: 1))
    }

    func testTimeoutDoesNotStartConcurrentPreferenceReads() {
        let release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "blocked preference read finishes")
        let lock = NSLock()
        var synchronizationCount = 0
        let inspector = AmphetamineBatteryProtectionInspector(
            synchronize: {
                lock.lock()
                synchronizationCount += 1
                lock.unlock()
                release.wait()
                finished.fulfill()
                return true
            },
            readSnapshot: { self.valid }
        )
        addTeardownBlock {
            release.signal()
        }

        XCTAssertThrowsError(try inspector.inspect(timeout: 0.01)) { error in
            XCTAssertEqual(error as? ModeControlError, .operationTimedOut)
        }
        XCTAssertThrowsError(try inspector.inspect(timeout: 0.01)) { error in
            XCTAssertEqual(error as? ModeControlError, .operationTimedOut)
        }
        lock.lock()
        let count = synchronizationCount
        lock.unlock()
        XCTAssertEqual(count, 1)

        release.signal()
        wait(for: [finished], timeout: 1)
    }
}
