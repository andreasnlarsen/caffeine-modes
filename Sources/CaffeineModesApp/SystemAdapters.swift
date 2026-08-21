import AppKit
import CaffeineModesCore
import Foundation
import IOKit.pwr_mgt
import ServiceManagement

final class IOKitPowerAssertionInspector: PowerAssertionInspecting {
    func displaySleepBlockingProcesses() throws -> [String] {
        var assertionsByProcess: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertionsByProcess)
        guard result == kIOReturnSuccess,
              let dictionary = assertionsByProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else {
            throw ModeControlError.backend("macOS did not return its power assertions.")
        }

        let displayTypes: Set<String> = [
            kIOPMAssertPreventUserIdleDisplaySleep as String,
            kIOPMAssertionTypeNoDisplaySleep as String
        ]
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var names = Set<String>()

        for (pidNumber, assertions) in dictionary {
            let pid = pid_t(pidNumber.int32Value)
            guard pid != ownPID else { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            if app?.bundleIdentifier == "com.if.Amphetamine" { continue }

            let blocksDisplay = assertions.contains { assertion in
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                      displayTypes.contains(type)
                else { return false }
                let level = (assertion[kIOPMAssertionLevelKey as String] as? NSNumber)?.uint32Value ?? 0
                return level == kIOPMAssertionLevelOn
            }

            if blocksDisplay {
                names.insert(app?.localizedName ?? "Process \(pid)")
            }
        }
        return names.sorted()
    }
}

final class SystemScreenLockPolicyChecker: ScreenLockPolicyChecking {
    func hasImmediateScreenLock() throws -> Bool {
        let output = try run(
            executable: "/usr/sbin/sysadminctl",
            arguments: ["-screenLock", "status"]
        )
        let normalized = output.lowercased()
        guard normalized.contains("screenlock") else {
            throw ModeControlError.backend("macOS returned an unknown screen-lock status.")
        }
        return normalized.contains("delay is immediate")
    }

    private func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw ModeControlError.backend("macOS could not read the screen-lock policy.")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

final class PMSetDisplaySleeper: DisplaySleeping {
    func sleepDisplay() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ModeControlError.backend("macOS did not accept the display-sleep request.")
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
