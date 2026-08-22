import Foundation

/// Runs a narrow AppKit or Foundation boundary on the main thread while its
/// caller remains on a worker queue.
public enum MainThreadExecutor {
    public static func run<T: Sendable>(
        _ operation: @escaping @MainActor () throws -> T
    ) rethrows -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(operation)
        }
        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated(operation)
        }
    }
}
