import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore
import Darwin
import Foundation
import IOKit.pwr_mgt
import ServiceManagement

final class IOKitPowerAssertionInspector: PowerAssertionInspecting {
    private static let inspections = FreshSingleFlight<[String]> {
        try inspectSynchronously()
    }

    func displaySleepBlockingProcesses(timeout: TimeInterval) throws -> [String] {
        try Self.inspections.value(timeout: timeout)
    }

    private static func inspectSynchronously() throws -> [String] {
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
    func hasImmediateScreenLock(timeout: TimeInterval) throws -> Bool {
        let result = try BoundedProcessRunner.run(
            executable: "/usr/sbin/sysadminctl",
            arguments: ["-screenLock", "status"],
            timeout: timeout
        )
        guard result.status == 0 else {
            throw ModeControlError.backend("macOS could not read the screen-lock policy.")
        }
        let output = result.output
        let normalized = output.lowercased()
        guard normalized.contains("screenlock") else {
            throw ModeControlError.backend("macOS returned an unknown screen-lock status.")
        }
        return normalized.contains("delay is immediate")
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
