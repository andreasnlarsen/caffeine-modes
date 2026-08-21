import Foundation

public enum VersionSupport {
    public static let minimumAmphetamineVersion = "5.3.2"

    public static func isSupported(_ version: String?) -> Bool {
        guard let version else { return false }
        return version.compare(
            minimumAmphetamineVersion,
            options: .numeric
        ) != .orderedAscending
    }
}
