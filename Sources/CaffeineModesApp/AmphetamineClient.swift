import AppKit
import CaffeineModesCore
import Foundation

final class AmphetamineClient: AmphetamineControlling {
    private static let bundleIdentifier = "com.if.Amphetamine"

    var isInstalled: Bool {
        applicationURL != nil
    }

    var installedVersion: String? {
        guard let url = applicationURL,
              let bundle = Bundle(url: url)
        else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func readState() throws -> AmphetamineState {
        let descriptor = try execute("""
        tell application id "com.if.Amphetamine"
            return {session is active, display sleep allowed, closed display mode enabled, Triggers are enabled, session time remaining}
        end tell
        """)

        guard descriptor.numberOfItems >= 5 else {
            throw ModeControlError.backend("Amphetamine returned an incomplete status response.")
        }

        let active = descriptor.atIndex(1)?.booleanValue ?? false
        let remaining = Int(descriptor.atIndex(5)?.int32Value ?? 0)
        return AmphetamineState(
            sessionIsActive: active,
            displaySleepAllowed: descriptor.atIndex(2)?.booleanValue ?? false,
            closedDisplayModeEnabled: descriptor.atIndex(3)?.booleanValue ?? false,
            triggersEnabled: descriptor.atIndex(4)?.booleanValue ?? false,
            remainingMinutes: active && remaining > 0 ? remaining : nil
        )
    }

    func startInfiniteSession(displaySleepAllowed: Bool) throws {
        let allowed = displaySleepAllowed ? "true" : "false"
        _ = try execute("""
        tell application id "com.if.Amphetamine"
            start new session with options {duration:0, interval:0, displaySleepAllowed:\(allowed)}
        end tell
        """)
    }

    func startTimedSession(minutes: Int, displaySleepAllowed: Bool) throws {
        guard OperatingMode.allowedTravelDurations.contains(minutes) || minutes == 1 else {
            throw ModeControlError.invalidTravelDuration(minutes)
        }
        let allowed = displaySleepAllowed ? "true" : "false"
        _ = try execute("""
        tell application id "com.if.Amphetamine"
            start new session with options {duration:\(minutes), interval:minutes, displaySleepAllowed:\(allowed)}
        end tell
        """)
    }

    func endSession() throws {
        _ = try execute("tell application id \"com.if.Amphetamine\" to end session")
    }

    func setClosedDisplayMode(enabled: Bool) throws {
        let command = enabled ? "enable closed display mode" : "disable closed display mode"
        _ = try execute("tell application id \"com.if.Amphetamine\" to \(command)")
    }

    func setTriggers(enabled: Bool) throws {
        let command = enabled ? "enable Triggers" : "disable Triggers"
        _ = try execute("tell application id \"com.if.Amphetamine\" to \(command)")
    }

    private var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier)
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard isInstalled else { throw ModeControlError.amphetamineMissing }
        guard let script = NSAppleScript(source: source) else {
            throw ModeControlError.backend("Caffeine Modes could not create its fixed Amphetamine command.")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            if code == -1743 || code == -1744 {
                throw ModeControlError.automationDenied
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Amphetamine rejected an Automation command."
            throw ModeControlError.backend(message)
        }
        return result
    }
}
