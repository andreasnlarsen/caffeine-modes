import Foundation

public final class UserDefaultsModeStore: ModeStateStoring, BatteryProtectionRequirementStoring {
    private enum Key {
        static let lastRequestedMode = "lastRequestedMode"
        static let ownedSessionSignature = "ownedSessionSignature"
        static let closedDisplayReadinessPassed = "closedDisplayReadinessPassed"
        static let launchAtLoginPromptWasShown = "launchAtLoginPromptWasShown"
        static let postUnlockMode = "postUnlockMode"
        static let batteryProtectionRequirement = "batteryProtectionRequirement"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastRequestedMode: OperatingMode {
        get {
            guard
                let data = defaults.data(forKey: Key.lastRequestedMode),
                let value = try? decoder.decode(OperatingMode.self, from: data)
            else { return .off }
            return value
        }
        set {
            defaults.set(try? encoder.encode(newValue), forKey: Key.lastRequestedMode)
        }
    }

    public var ownedSessionSignature: OwnedSessionSignature? {
        get {
            guard let data = defaults.data(forKey: Key.ownedSessionSignature) else { return nil }
            return try? decoder.decode(OwnedSessionSignature.self, from: data)
        }
        set {
            if let newValue {
                defaults.set(try? encoder.encode(newValue), forKey: Key.ownedSessionSignature)
            } else {
                defaults.removeObject(forKey: Key.ownedSessionSignature)
            }
        }
    }

    public var closedDisplayReadinessPassed: Bool {
        get { defaults.bool(forKey: Key.closedDisplayReadinessPassed) }
        set { defaults.set(newValue, forKey: Key.closedDisplayReadinessPassed) }
    }

    public var launchAtLoginPromptWasShown: Bool {
        get { defaults.bool(forKey: Key.launchAtLoginPromptWasShown) }
        set { defaults.set(newValue, forKey: Key.launchAtLoginPromptWasShown) }
    }

    public var postUnlockMode: PostUnlockMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.postUnlockMode),
                  let mode = PostUnlockMode(rawValue: rawValue)
            else { return .off }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.postUnlockMode) }
    }

    public var batteryProtectionRequirement: BatteryProtectionRequirement {
        get {
            guard
                let data = defaults.data(forKey: Key.batteryProtectionRequirement),
                let value = try? decoder.decode(BatteryProtectionRequirement.self, from: data)
            else { return .defaultValue }
            return value
        }
        set {
            defaults.set(try? encoder.encode(newValue), forKey: Key.batteryProtectionRequirement)
        }
    }
}
