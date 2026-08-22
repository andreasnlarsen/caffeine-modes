public enum PowerAssertionProcessFilter {
    public static func hidesFromSystemAndDiskSummary(
        bundleIdentifier: String?,
        executablePath: String?,
        isUserFacingApplication: Bool
    ) -> Bool {
        guard !isUserFacingApplication else { return false }
        if bundleIdentifier?.hasPrefix("com.apple.") == true {
            return true
        }
        guard let executablePath else { return false }
        return executablePath.hasPrefix("/System/")
            || executablePath.hasPrefix("/usr/libexec/")
            || executablePath.hasPrefix("/usr/sbin/")
    }
}
