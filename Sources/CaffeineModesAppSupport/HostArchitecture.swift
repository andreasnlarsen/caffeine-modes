public enum HostArchitecture {
    public static func requiresPowerProtect(arm64Capability: Int32?) -> Bool {
        arm64Capability != 0
    }
}
