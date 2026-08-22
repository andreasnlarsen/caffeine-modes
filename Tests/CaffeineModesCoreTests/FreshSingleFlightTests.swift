@testable import CaffeineModesAppSupport
import CaffeineModesCore
import Foundation
import XCTest

final class FreshSingleFlightTests: XCTestCase {
    func testJoinedCallerUsesFreshResultWithinOriginalDeadline() throws {
        let state = OperationState()
        let joined = DispatchSemaphore(value: 0)
        let flight = FreshSingleFlight<[String]>(
            didJoinExistingOperation: { joined.signal() },
            operation: {
                let call = state.nextCall()
                if call == 1 {
                    state.firstStarted.signal()
                    state.releaseFirst.wait()
                    return ["stale"]
                }
                return ["fresh"]
            }
        )

        XCTAssertThrowsError(try flight.value(timeout: 0.01)) { error in
            XCTAssertEqual(error as? ModeControlError, .operationTimedOut)
        }
        XCTAssertEqual(state.firstStarted.wait(timeout: .now() + 1), .success)

        let result = ResultBox<[String]>()
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            result.store(Result { try flight.value(timeout: 1) })
            completed.signal()
        }

        XCTAssertEqual(joined.wait(timeout: .now() + 1), .success)
        state.releaseFirst.signal()
        XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(try result.get().get(), ["fresh"])
        XCTAssertEqual(state.callCount, 2)
    }

    func testRepeatedTimeoutsDoNotStartConcurrentWorkers() {
        let state = OperationState()
        let flight = FreshSingleFlight<[String]> {
            let call = state.nextCall()
            if call == 1 {
                state.firstStarted.signal()
                state.releaseFirst.wait()
            }
            return []
        }

        XCTAssertThrowsError(try flight.value(timeout: 0.01))
        XCTAssertEqual(state.firstStarted.wait(timeout: .now() + 1), .success)
        XCTAssertThrowsError(try flight.value(timeout: 0.01))
        XCTAssertThrowsError(try flight.value(timeout: 0.01))
        XCTAssertEqual(state.callCount, 1)
        state.releaseFirst.signal()
    }
}

private final class OperationState: @unchecked Sendable {
    let firstStarted = DispatchSemaphore(value: 0)
    let releaseFirst = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCallCount
    }

    func nextCall() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storedCallCount += 1
        return storedCallCount
    }
}

private final class ResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<Value, Error> {
        lock.lock()
        defer { lock.unlock() }
        return result ?? .failure(ModeControlError.operationTimedOut)
    }
}
