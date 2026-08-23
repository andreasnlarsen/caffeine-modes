import Foundation

public enum SessionLockStateParser {
    public static func isLocked(from value: Any?) -> Bool? {
        guard let value else { return false }
        if let boolean = value as? Bool { return boolean }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
}
