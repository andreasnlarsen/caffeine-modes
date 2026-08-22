import Foundation

/// Decides the screen-lock policy from `sysadminctl -screenLock status` output.
/// Only explicit immediate and explicit non-immediate forms are accepted;
/// every other output fails closed as unknown.
public enum ScreenLockStatusParser {
    /// Decides the current macOS device grace period. A missing or negative
    /// value is not safe to interpret and therefore fails closed.
    public static func isImmediate(deviceGracePeriodSeconds seconds: Int?) throws -> Bool {
        guard let seconds, seconds >= 0 else {
            throw ModeControlError.backend("macOS returned an unknown screen-lock grace period.")
        }
        return seconds == 0
    }

    public static func isImmediate(fromStatusOutput output: String) throws -> Bool {
        let normalized = output.lowercased()
        if normalized.contains("screenlock delay is immediate") {
            return true
        }
        if normalized.contains("screenlock is off") {
            return false
        }
        if normalized.range(
            of: "screenlock delay is [0-9]+ second",
            options: .regularExpression
        ) != nil {
            return false
        }
        throw ModeControlError.backend("macOS returned an unknown screen-lock status.")
    }
}
