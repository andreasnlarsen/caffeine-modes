import CaffeineModesCore
import Foundation

public final class FreshSingleFlight<Value: Sendable>: @unchecked Sendable {
    private final class Operation: @unchecked Sendable {
        private let completion = DispatchGroup()
        private let lock = NSLock()
        private var storedResult: Result<Value, Error>?

        init() {
            completion.enter()
        }

        func finish(_ result: Result<Value, Error>) {
            lock.lock()
            storedResult = result
            lock.unlock()
            completion.leave()
        }

        func wait(until deadline: DispatchTime) -> Bool {
            completion.wait(timeout: deadline) == .success
        }

        func completedResult() -> Result<Value, Error> {
            lock.lock()
            defer { lock.unlock() }
            return storedResult ?? .failure(ModeControlError.operationTimedOut)
        }
    }

    private struct Selection {
        let operation: Operation
        let startedNewOperation: Bool
    }

    private let lock = NSLock()
    private let didJoinExistingOperation: @Sendable () -> Void
    private let work: @Sendable () -> Result<Value, Error>
    private var inFlight: Operation?

    public convenience init(
        operation: @escaping @Sendable () throws -> Value
    ) {
        self.init(didJoinExistingOperation: {}, operation: operation)
    }

    init(
        didJoinExistingOperation: @escaping @Sendable () -> Void,
        operation: @escaping @Sendable () throws -> Value
    ) {
        self.didJoinExistingOperation = didJoinExistingOperation
        self.work = { Result(catching: operation) }
    }

    public func value(timeout: TimeInterval) throws -> Value {
        let maximumTimeout = TimeInterval(UInt64.max) / 1_000_000_000
        guard timeout > 0, timeout.isFinite, timeout <= maximumTimeout else {
            throw ModeControlError.operationTimedOut
        }
        let timeoutNanoseconds = UInt64(timeout * 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        let selection = currentOrStart()

        let firstResult = try waitForResult(selection.operation, until: deadline)
        if selection.startedNewOperation {
            return try firstResult.get()
        }

        let freshSelection = currentOrStart()
        return try waitForResult(freshSelection.operation, until: deadline).get()
    }

    private func currentOrStart() -> Selection {
        lock.lock()
        if let inFlight {
            lock.unlock()
            didJoinExistingOperation()
            return Selection(operation: inFlight, startedNewOperation: false)
        }
        let operation = Operation()
        inFlight = operation
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            self.finish(operation, result: self.work())
        }
        return Selection(operation: operation, startedNewOperation: true)
    }

    private func finish(_ operation: Operation, result: Result<Value, Error>) {
        lock.lock()
        if inFlight === operation {
            inFlight = nil
        }
        lock.unlock()
        operation.finish(result)
    }

    private func waitForResult(
        _ operation: Operation,
        until deadline: UInt64
    ) throws -> Result<Value, Error> {
        let now = DispatchTime.now().uptimeNanoseconds
        guard deadline > now else { throw ModeControlError.operationTimedOut }
        let remaining = min(deadline - now, UInt64(Int.max))
        guard operation.wait(until: .now() + .nanoseconds(Int(remaining))) else {
            throw ModeControlError.operationTimedOut
        }
        return operation.completedResult()
    }
}
