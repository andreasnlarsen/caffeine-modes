import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore
import CoreGraphics
import Darwin
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement

final class IOKitPowerAssertionInspector: PowerAssertionInspecting {
    private static let inspections = FreshSingleFlight<PowerAssertionReport> {
        try inspectSynchronously()
    }

    func inspect(timeout: TimeInterval) throws -> PowerAssertionReport {
        try Self.inspections.value(timeout: timeout)
    }

    private static func inspectSynchronously() throws -> PowerAssertionReport {
        var assertionsByProcess: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertionsByProcess)
        guard result == kIOReturnSuccess,
              let dictionary = assertionsByProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else {
            throw ModeControlError.backend("macOS did not return its power assertions.")
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var displayNames = Set<String>()
        var systemNames = Set<String>()
        var diskNames = Set<String>()

        for (pidNumber, assertions) in dictionary {
            let pid = pid_t(pidNumber.int32Value)
            guard pid != ownPID else { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            if app?.bundleIdentifier == "com.if.Amphetamine" { continue }

            let owner = processName(pid: pid, application: app)
            let isSystemProcess = isMacOSSystemProcess(pid: pid, application: app)
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                      let category = PowerAssertionClassifier.category(forType: type)
                else { continue }
                let level = (assertion[kIOPMAssertionLevelKey as String] as? NSNumber)?.uint32Value ?? 0
                guard level == kIOPMAssertionLevelOn else { continue }
                switch category {
                case .displaySleep:
                    displayNames.insert(owner)
                case .systemSleep:
                    if !isSystemProcess { systemNames.insert(owner) }
                case .diskIdle:
                    if !isSystemProcess { diskNames.insert(owner) }
                }
            }
        }
        return PowerAssertionReport(
            displaySleepBlockingProcesses: displayNames.sorted(),
            systemSleepBlockingProcesses: systemNames.sorted(),
            diskIdleBlockingProcesses: diskNames.sorted()
        )
    }

    private static func processName(
        pid: pid_t,
        application: NSRunningApplication?
    ) -> String {
        if let name = application?.localizedName, !name.isEmpty {
            return name
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let count = proc_name(pid, &buffer, UInt32(buffer.count))
        if count > 0 {
            return buffer.withUnsafeBytes {
                String(decoding: $0.prefix(Int(count)), as: UTF8.self)
            }
        }
        return "Process \(pid)"
    }

    private static func isMacOSSystemProcess(
        pid: pid_t,
        application: NSRunningApplication?
    ) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path: String?
        if count > 0 {
            path = buffer.withUnsafeBytes {
                String(decoding: $0.prefix(Int(count)), as: UTF8.self)
            }
        } else {
            path = nil
        }
        return PowerAssertionProcessFilter.hidesFromSystemAndDiskSummary(
            bundleIdentifier: application?.bundleIdentifier,
            executablePath: path,
            isUserFacingApplication: application.map {
                $0.activationPolicy != .prohibited
            } ?? false
        )
    }
}

final class SystemScreenLockPolicyChecker: ScreenLockPolicyChecking {
    private enum DeviceGracePeriodReadError: Error {
        case sourceUnavailable
    }

    private static let mobileKeyBagPath =
        "/System/Library/PrivateFrameworks/MobileKeyBag.framework/MobileKeyBag"

    private static let gracePeriodReads = FreshSingleFlight<Int> {
        try readDeviceGracePeriodSynchronously()
    }

    private typealias DeviceGracePeriodFunction = @convention(c) (
        CFDictionary?
    ) -> Unmanaged<CFDictionary>?

    func hasImmediateScreenLock(timeout: TimeInterval) throws -> Bool {
        guard timeout > 0, timeout.isFinite else {
            throw ModeControlError.operationTimedOut
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout

        do {
            return try ScreenLockStatusParser.isImmediate(
                deviceGracePeriodSeconds: Self.gracePeriodReads.value(timeout: timeout)
            )
        } catch DeviceGracePeriodReadError.sourceUnavailable {
            // macOS 26 moved this setting to the device grace period. Its
            // sysadminctl output can disagree with System Settings, so there
            // is no safe legacy fallback on macOS 26 or later.
            if #available(macOS 26, *) {
                throw ModeControlError.backend("macOS could not read the screen-lock grace period.")
            }
        }

        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw ModeControlError.operationTimedOut }

        let result = try BoundedProcessRunner.run(
            executable: "/usr/sbin/sysadminctl",
            arguments: ["-screenLock", "status"],
            timeout: remaining
        )
        guard result.status == 0 else {
            throw ModeControlError.backend("macOS could not read the screen-lock policy.")
        }
        return try ScreenLockStatusParser.isImmediate(fromStatusOutput: result.output)
    }

    private static func readDeviceGracePeriodSynchronously() throws -> Int {
        guard let library = dlopen(Self.mobileKeyBagPath, RTLD_LAZY | RTLD_LOCAL) else {
            throw DeviceGracePeriodReadError.sourceUnavailable
        }
        defer { dlclose(library) }

        guard let symbol = dlsym(library, "MKBDeviceGetGracePeriod") else {
            throw DeviceGracePeriodReadError.sourceUnavailable
        }
        let readGracePeriod = unsafeBitCast(symbol, to: DeviceGracePeriodFunction.self)
        guard let unmanagedDictionary = readGracePeriod(nil) else {
            throw ModeControlError.backend("macOS returned no screen-lock grace period.")
        }
        let dictionary = unmanagedDictionary.takeRetainedValue() as NSDictionary
        guard let number = dictionary["GracePeriod"] as? NSNumber else {
            throw ModeControlError.backend("macOS returned an unknown screen-lock grace period.")
        }
        return number.intValue
    }
}

final class CGSessionScreenLockStateInspector: ScreenLockStateInspecting {
    func screenIsLocked() throws -> Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            throw ModeControlError.screenLockStateUnavailable(
                "macOS did not return the current lock state."
            )
        }
        if let isLocked = SessionLockStateParser.isLocked(
            from: dictionary["CGSSessionScreenIsLocked"]
        ) {
            return isLocked
        }
        throw ModeControlError.screenLockStateUnavailable(
            "macOS returned an unknown lock state."
        )
    }
}

final class AmphetaminePowerProtectInspector: PowerProtectInspecting {
    static let configurationPath = "/private/etc/sudoers.d/amphetamine_PowerProtect"

    func inspect() -> PowerProtectStatus {
        guard HostArchitecture.requiresPowerProtect(
            arm64Capability: Self.runtimeArm64Capability()
        ) else {
            return PowerProtectStatus(isRequired: false, isInstalled: false)
        }
        let script = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt")
        let configuration = URL(fileURLWithPath: Self.configurationPath)
        return PowerProtectStatus(
            isRequired: true,
            isInstalled: FileManager.default.fileExists(atPath: script.path)
                && FileManager.default.fileExists(atPath: configuration.path)
        )
    }

    private static func runtimeArm64Capability() -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else {
            return nil
        }
        return value
    }
}

final class SystemClamshellContextInspector: ClamshellContextInspecting {
    func currentContext() -> ClamshellContext {
        let firstLidState = Self.lidState()
        let externalPowerConnected = Self.externalPowerConnected()
        let activeExternalDisplayPresent = Self.activeExternalDisplayPresent()
        let secondLidState = Self.lidState()
        return Self.stableContext(
            firstLidState: firstLidState,
            externalPowerConnected: externalPowerConnected,
            activeExternalDisplayPresent: activeExternalDisplayPresent,
            secondLidState: secondLidState
        )
    }

    static func stableContext(
        firstLidState: LidState,
        externalPowerConnected: Bool?,
        activeExternalDisplayPresent: Bool?,
        secondLidState: LidState
    ) -> ClamshellContext {
        ClamshellContext(
            lidState: firstLidState == secondLidState ? firstLidState : .unavailable,
            externalPowerConnected: externalPowerConnected,
            activeExternalDisplayPresent: activeExternalDisplayPresent
        )
    }

    static func externalPowerConnected(sourceType: String) -> Bool? {
        switch sourceType {
        case kIOPMACPowerKey, kIOPMUPSPowerKey:
            true
        case kIOPMBatteryPowerKey:
            false
        default:
            nil
        }
    }

    static func isEligibleExternalDisplay(
        isBuiltin: Bool,
        isActive: Bool,
        isAsleep: Bool
    ) -> Bool {
        !isBuiltin && isActive && !isAsleep
    }

    private static func lidState() -> LidState {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return .unavailable }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        else { return .unavailable }
        if let boolean = value as? Bool {
            return boolean ? .closed : .open
        }
        if let number = value as? NSNumber {
            return number.boolValue ? .closed : .open
        }
        return .unavailable
    }

    private static func externalPowerConnected() -> Bool? {
        guard let unmanagedSnapshot = IOPSCopyPowerSourcesInfo() else { return nil }
        let snapshot = unmanagedSnapshot.takeRetainedValue()
        let sourceType = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue() as String
        return externalPowerConnected(sourceType: sourceType)
    }

    private static func activeExternalDisplayPresent() -> Bool? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var filledCount: UInt32 = 0
        guard CGGetOnlineDisplayList(count, &displays, &filledCount) == .success else {
            return nil
        }
        return displays.prefix(Int(filledCount)).contains { display in
            isEligibleExternalDisplay(
                isBuiltin: CGDisplayIsBuiltin(display) != 0,
                isActive: CGDisplayIsActive(display) != 0,
                isAsleep: CGDisplayIsAsleep(display) != 0
            )
        }
    }
}

final class SystemDisplayStateInspector: DisplayStateInspecting {
    func currentState() -> DisplayStateObservation {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            return Self.classify(asleepStates: nil)
        }
        guard count > 0 else { return Self.classify(asleepStates: []) }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var filledCount: UInt32 = 0
        guard CGGetOnlineDisplayList(count, &displays, &filledCount) == .success else {
            return Self.classify(asleepStates: nil)
        }
        let asleepStates = displays.prefix(Int(filledCount)).map {
            CGDisplayIsAsleep($0) != 0
        }
        return Self.classify(asleepStates: asleepStates)
    }

    static func classify(asleepStates: [Bool]?) -> DisplayStateObservation {
        guard let asleepStates, !asleepStates.isEmpty else { return .unavailable }
        return asleepStates.contains(false) ? .visible : .allAsleep
    }
}

final class AmphetamineBatteryProtectionInspector: AmphetamineBatteryProtectionInspecting {
    private final class PreferenceRead: @unchecked Sendable {
        let synchronize: () -> Bool
        let readSnapshot: () -> [String: Any]?

        init(
            synchronize: @escaping () -> Bool,
            readSnapshot: @escaping () -> [String: Any]?
        ) {
            self.synchronize = synchronize
            self.readSnapshot = readSnapshot
        }

        func configuration() -> AmphetamineBatteryProtectionConfiguration? {
            guard synchronize(), let snapshot = readSnapshot() else { return nil }
            return AmphetamineBatteryProtectionInspector.configuration(from: snapshot)
        }
    }

    private static let enabledKey = "End Session On Low Battery"
    private static let thresholdKey = "Low Battery Percent"
    private static let promptKey = "Always Ask to End For Low Battery"
    private static let ignoreOnPowerKey = "Ignore Battery on AC"

    private static let preferenceKeys = [
        enabledKey,
        thresholdKey,
        promptKey,
        ignoreOnPowerKey
    ]

    private let inspections: FreshSingleFlight<AmphetamineBatteryProtectionConfiguration?>

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let domain = homeDirectory
            .appendingPathComponent("Library/Containers/com.if.Amphetamine/Data/Library/Preferences")
            .appendingPathComponent("com.if.Amphetamine")
            .path as CFString
        let preferenceRead = PreferenceRead(synchronize: {
            CFPreferencesSynchronize(
                domain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }, readSnapshot: {
            CFPreferencesCopyMultiple(
                Self.preferenceKeys as CFArray,
                domain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String: Any]
        })
        inspections = FreshSingleFlight {
            preferenceRead.configuration()
        }
    }

    init(
        synchronize: @escaping () -> Bool,
        readSnapshot: @escaping () -> [String: Any]?
    ) {
        let preferenceRead = PreferenceRead(
            synchronize: synchronize,
            readSnapshot: readSnapshot
        )
        inspections = FreshSingleFlight {
            preferenceRead.configuration()
        }
    }

    func inspect(timeout: TimeInterval) throws -> AmphetamineBatteryProtectionConfiguration? {
        try inspections.value(timeout: timeout)
    }

    static func configuration(
        from dictionary: [String: Any]
    ) -> AmphetamineBatteryProtectionConfiguration? {
        guard let enabled = strictBoolean(dictionary[enabledKey]),
              let threshold = strictInteger(dictionary[thresholdKey]),
              (0...100).contains(threshold),
              let prompts = strictBoolean(dictionary[promptKey]),
              let ignoresOnPower = strictBoolean(dictionary[ignoreOnPowerKey])
        else { return nil }
        return AmphetamineBatteryProtectionConfiguration(
            endsSessionOnLowBattery: enabled,
            thresholdPercent: threshold,
            promptsBeforeEnding: prompts,
            ignoresLimitOnExternalPower: ignoresOnPower
        )
    }

    private static func strictBoolean(_ value: Any?) -> Bool? {
        guard let value, let number = value as? NSNumber else { return nil }
        let typeID = CFGetTypeID(value as CFTypeRef)
        if typeID == CFBooleanGetTypeID() {
            return number.boolValue
        }
        guard typeID == CFNumberGetTypeID(),
              let integer = strictInteger(value)
        else { return nil }
        switch integer {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let value,
              CFGetTypeID(value as CFTypeRef) == CFNumberGetTypeID(),
              let number = value as? NSNumber,
              !CFNumberIsFloatType(number)
        else { return nil }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite, doubleValue.rounded() == doubleValue else { return nil }
        return Int(exactly: number.int64Value)
    }
}

final class PMSetDisplaySleeper: DisplaySleeping {
    func sleepDisplay(timeout: TimeInterval) throws {
        let result = try BoundedProcessRunner.run(
            executable: "/usr/bin/pmset",
            arguments: ["displaysleepnow"],
            timeout: timeout
        )
        guard result.status == 0 else {
            throw ModeControlError.backend("macOS did not accept the display-sleep request.")
        }
    }
}

private enum BoundedProcessRunner {
    struct Result {
        let output: String
        let status: Int32
    }

    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> Result {
        guard timeout > 0, timeout.isFinite else {
            throw ModeControlError.operationTimedOut
        }
        let timeoutNanoseconds = UInt64(timeout * 1_000_000_000)
        let hardDeadlineNanoseconds = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        let cleanupReserveNanoseconds = min(timeoutNanoseconds, 200_000_000)
        let operationDeadline = DispatchTime(
            uptimeNanoseconds: hardDeadlineNanoseconds - cleanupReserveNanoseconds
        )
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        let pid = try spawn(
            executable: executable,
            arguments: arguments,
            outputPipe: pipe
        )

        guard let waitStatus = try waitForExit(
            pid,
            until: operationDeadline.uptimeNanoseconds
        ) else {
            stopOwnedChild(pid, hardDeadlineNanoseconds: hardDeadlineNanoseconds)
            throw ModeControlError.operationTimedOut
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Result(
            output: String(decoding: data, as: UTF8.self),
            status: waitStatus == 0 ? 0 : 1
        )
    }

    private static func spawn(
        executable: String,
        arguments: [String],
        outputPipe: Pipe
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        let actionsStatus = posix_spawn_file_actions_init(&fileActions)
        guard actionsStatus == 0 else {
            throw ModeControlError.backend("macOS could not prepare a fixed system command.")
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        let readDescriptor = outputPipe.fileHandleForReading.fileDescriptor
        let writeDescriptor = outputPipe.fileHandleForWriting.fileDescriptor
        guard posix_spawn_file_actions_adddup2(
            &fileActions,
            writeDescriptor,
            STDOUT_FILENO
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            writeDescriptor,
            STDERR_FILENO
        ) == 0,
        posix_spawn_file_actions_addclose(&fileActions, readDescriptor) == 0,
        posix_spawn_file_actions_addclose(&fileActions, writeDescriptor) == 0
        else {
            throw ModeControlError.backend("macOS could not configure a fixed system command.")
        }

        var argumentPointers = ([executable] + arguments).map { strdup($0) }
        argumentPointers.append(nil)
        defer {
            for pointer in argumentPointers {
                free(pointer)
            }
        }

        var pid: pid_t = 0
        let spawnStatus = executable.withCString { executablePointer in
            argumentPointers.withUnsafeMutableBufferPointer { buffer in
                posix_spawn(
                    &pid,
                    executablePointer,
                    &fileActions,
                    nil,
                    buffer.baseAddress,
                    environ
                )
            }
        }
        try? outputPipe.fileHandleForWriting.close()
        guard spawnStatus == 0 else {
            throw ModeControlError.backend("macOS could not start a fixed system command.")
        }
        return pid
    }

    private static func waitForExit(
        _ pid: pid_t,
        until deadlineNanoseconds: UInt64
    ) throws -> Int32? {
        while true {
            var waitStatus: Int32 = 0
            let result = waitpid(pid, &waitStatus, WNOHANG)
            if result == pid {
                return waitStatus
            }
            if result == -1 {
                if errno == EINTR { continue }
                throw ModeControlError.backend("macOS could not observe a fixed system command.")
            }

            let nowNanoseconds = DispatchTime.now().uptimeNanoseconds
            guard nowNanoseconds < deadlineNanoseconds else { return nil }
            let remainingMicroseconds = max(
                1,
                min(5_000, (deadlineNanoseconds - nowNanoseconds) / 1_000)
            )
            usleep(useconds_t(remainingMicroseconds))
        }
    }

    // posix_spawn and waitpid keep this exact child unreaped until signaling is complete.
    // Its PID cannot be reused while this function owns the wait.
    private static func stopOwnedChild(
        _ pid: pid_t,
        hardDeadlineNanoseconds: UInt64
    ) {
        _ = Darwin.kill(pid, SIGTERM)
        let termDeadlineNanoseconds = min(
            hardDeadlineNanoseconds,
            DispatchTime.now().uptimeNanoseconds + 100_000_000
        )
        do {
            if try waitForExit(pid, until: termDeadlineNanoseconds) != nil {
                return
            }
        } catch {
            return
        }
        _ = Darwin.kill(pid, SIGKILL)
        do {
            if try waitForExit(pid, until: hardDeadlineNanoseconds) != nil {
                return
            }
        } catch {
            return
        }
        reapLater(pid)
    }

    private static func reapLater(_ pid: pid_t) {
        DispatchQueue.global(qos: .utility).async {
            var waitStatus: Int32 = 0
            while waitpid(pid, &waitStatus, 0) == -1, errno == EINTR {}
        }
    }
}

protocol LaunchAtLoginManaging: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

final class LaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
