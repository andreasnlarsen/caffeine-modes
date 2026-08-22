import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore
import Foundation

final class AmphetamineClient: AmphetamineControlling {
    private static let bundleIdentifier = "com.if.Amphetamine"

    var isInstalled: Bool {
        MainThreadExecutor.run { Self.applicationURL != nil }
    }

    var installedVersion: String? {
        MainThreadExecutor.run {
            guard let url = Self.applicationURL,
                  let bundle = Bundle(url: url)
            else { return nil }
            return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        }
    }

    func readState(timeout: TimeInterval) throws -> AmphetamineState {
        try execute("""
        tell application id "com.if.Amphetamine"
            return {session is active, display sleep allowed, closed display mode enabled, Triggers are enabled, session time remaining}
        end tell
        """, timeout: timeout) { descriptor in
            guard descriptor.numberOfItems >= 5 else {
                throw ModeControlError.backend("Amphetamine returned an incomplete status response.")
            }

            let active = descriptor.atIndex(1)?.booleanValue ?? false
            let remainingSeconds = Int(descriptor.atIndex(5)?.int32Value ?? -3)
            return AmphetamineState(
                sessionIsActive: active,
                displaySleepAllowed: descriptor.atIndex(2)?.booleanValue ?? false,
                closedDisplayModeEnabled: descriptor.atIndex(3)?.booleanValue ?? false,
                triggersEnabled: descriptor.atIndex(4)?.booleanValue ?? false,
                sessionTimeRemainingSeconds: remainingSeconds
            )
        }
    }

    func startInfiniteSession(displaySleepAllowed: Bool, timeout: TimeInterval) throws {
        let allowed = displaySleepAllowed ? "true" : "false"
        try execute("""
        tell application id "com.if.Amphetamine"
            start new session with options {duration:0, interval:0, displaySleepAllowed:\(allowed)}
        end tell
        """, timeout: timeout) { _ in () }
    }

    func startTimedSession(minutes: Int, displaySleepAllowed: Bool, timeout: TimeInterval) throws {
        guard OperatingMode.allowedTravelDurations.contains(minutes) || minutes == 1 else {
            throw ModeControlError.invalidTravelDuration(minutes)
        }
        let allowed = displaySleepAllowed ? "true" : "false"
        try execute("""
        tell application id "com.if.Amphetamine"
            start new session with options {duration:\(minutes), interval:minutes, displaySleepAllowed:\(allowed)}
        end tell
        """, timeout: timeout) { _ in () }
    }

    func endSession(timeout: TimeInterval) throws {
        try execute(
            "tell application id \"com.if.Amphetamine\" to end session",
            timeout: timeout
        ) { _ in () }
    }

    func setClosedDisplayMode(enabled: Bool, timeout: TimeInterval) throws {
        let command = enabled ? "enable closed display mode" : "disable closed display mode"
        try execute(
            "tell application id \"com.if.Amphetamine\" to \(command)",
            timeout: timeout
        ) { _ in () }
    }

    func setTriggers(enabled: Bool, timeout: TimeInterval) throws {
        let command = enabled ? "enable Triggers" : "disable Triggers"
        try execute(
            "tell application id \"com.if.Amphetamine\" to \(command)",
            timeout: timeout
        ) { _ in () }
    }

    @MainActor
    private static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier)
    }

    private func execute<T: Sendable>(
        _ source: String,
        timeout: TimeInterval,
        transform: @escaping @MainActor (NSAppleEventDescriptor) throws -> T
    ) throws -> T {
        try MainThreadExecutor.run {
            try Self.executeOnMainThread(
                source,
                timeout: timeout,
                transform: transform
            )
        }
    }

    @MainActor
    private static func executeOnMainThread<T: Sendable>(
        _ source: String,
        timeout: TimeInterval,
        transform: (NSAppleEventDescriptor) throws -> T
    ) throws -> T {
        precondition(Thread.isMainThread)
        guard applicationURL != nil else { throw ModeControlError.amphetamineMissing }
        let timeoutLiteral = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            max(0.001, timeout)
        )
        let timedSource = """
        with timeout of \(timeoutLiteral) seconds
            \(source)
        end timeout
        """
        guard let script = NSAppleScript(source: timedSource) else {
            throw ModeControlError.backend("Caffeine Modes could not create its fixed Amphetamine command.")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            if code == -1743 || code == -1744 {
                throw ModeControlError.automationDenied
            }
            if code == -1712 {
                throw ModeControlError.operationTimedOut
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Amphetamine rejected an Automation command."
            throw ModeControlError.backend(message)
        }
        return try transform(result)
    }
}
