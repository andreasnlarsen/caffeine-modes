import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore

@MainActor
final class ScreenLifecycleController: NSObject {
    enum Operation {
        case unlockCheck(UUID)
        case resleep(UUID)

        var ownershipID: UUID {
            switch self {
            case let .unlockCheck(id), let .resleep(id): id
            }
        }

        var kind: Kind {
            switch self {
            case .unlockCheck: .unlockCheck
            case .resleep: .resleep
            }
        }

        enum Kind {
            case unlockCheck
            case resleep
        }
    }

    private let runner: ScreenLifecycleRunner
    private let didFinish: (ModeSnapshot?, Error?, Operation.Kind) -> Void
    private var machine = AwayModeWakeStateMachine()
    private var activity = ScreenLifecycleActivity()
    private var timer: Timer?
    private var unlockRetryTimer: Timer?
    private var activeOperation: Operation?
    private var observedMode: OperatingMode = .off
    private var observedOwnershipID: UUID?

    var isBusy: Bool { activity.isBusy }

    static func completionSucceeded(
        for operation: Operation.Kind,
        snapshot: ModeSnapshot
    ) -> Bool {
        switch operation {
        case .unlockCheck:
            return true
        case .resleep:
            return snapshot.requiresPostUnlockChoice || snapshot.safety == .ready
        }
    }

    init(
        controller: ModeControlling,
        didFinish: @escaping (ModeSnapshot?, Error?, Operation.Kind) -> Void
    ) {
        self.runner = ScreenLifecycleRunner(controller: controller)
        self.didFinish = didFinish
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func modeDidChange(snapshot: ModeSnapshot, restoredSession: Bool = false) {
        guard LifecycleObservationPolicy.accepts(snapshot) else { return }
        let mode = snapshot.requestedMode
        let ownershipID = mode.isAwayMode ? snapshot.ownershipMarker?.id : nil
        let identityChanged = observedOwnershipID != ownershipID
            || observedMode.isAwayMode != mode.isAwayMode
        if identityChanged {
            timer?.invalidate()
            timer = nil
            unlockRetryTimer?.invalidate()
            unlockRetryTimer = nil
            machine = AwayModeWakeStateMachine()
        }
        observedMode = mode
        observedOwnershipID = ownershipID
        activity.modeDidChange(
            awayModeIsActive: mode.isAwayMode,
            identityChanged: identityChanged
        )
        let action = machine.modeDidChange(
            to: mode,
            restoredSession: restoredSession,
            now: ProcessInfo.processInfo.systemUptime
        )
        if snapshot.requiresPostUnlockChoice {
            machine.verifiedUnlockObserved()
            activity.verifiedUnlockObserved()
            timer?.invalidate()
            timer = nil
        }
        if !mode.isAwayMode {
            timer?.invalidate()
            timer = nil
            unlockRetryTimer?.invalidate()
            unlockRetryTimer = nil
        }
        if action == .checkLockState {
            scheduleResleepTimer()
            checkForUnlock()
        }
    }

    @objc private func screensDidWake(_ notification: Notification) {
        handleDisplayMayBeVisible(
            machine.screensDidWake(now: ProcessInfo.processInfo.systemUptime)
        )
    }

    @objc private func displayConfigurationDidChange(_ notification: Notification) {
        handleDisplayMayBeVisible(
            machine.displayConfigurationDidChange(
                now: ProcessInfo.processInfo.systemUptime
            )
        )
    }

    private func handleDisplayMayBeVisible(_ action: AwayModeWakeAction) {
        guard action == .checkLockState else {
            return
        }
        activity.beginDisplayVisibilityEvent()
        scheduleResleepTimer()
        checkForUnlock()
    }

    @objc private func screensDidSleep(_ notification: Notification) {
        machine.screensDidSleep()
        timer?.invalidate()
        timer = nil
    }

    @objc private func screenDidUnlock(_ notification: Notification) {
        activity.beginUnlockEvent()
        checkForUnlock()
    }

    private func checkForUnlock() {
        guard observedMode.isAwayMode, let ownershipID = observedOwnershipID else { return }
        unlockRetryTimer?.invalidate()
        unlockRetryTimer = nil
        guard activity.requestUnlockCheck() else { return }
        activeOperation = .unlockCheck(ownershipID)
        runner.handleScreenUnlocked(expectedOwnershipID: ownershipID) { [weak self] result in
            self?.finish(result)
        }
    }

    private func scheduleResleepTimer() {
        timer?.invalidate()
        guard let deadline = machine.resleepDeadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        timer = LifecycleTimerScheduler.schedule(after: delay) { [weak self] in
            self?.resleepTimerFired()
        }
    }

    private func resleepTimerFired() {
        timer = nil
        guard machine.timerFired(now: ProcessInfo.processInfo.systemUptime) == .resleepDisplay else {
            return
        }
        guard activity.requestResleep() else { return }
        startResleep()
    }

    private func startResleep() {
        guard observedMode.policy.resleepsAfterDisplayWake,
              let ownershipID = observedOwnershipID
        else { return }
        activeOperation = .resleep(ownershipID)
        runner.resleepNightIfLocked(expectedOwnershipID: ownershipID) { [weak self] result in
            self?.finish(result)
        }
    }

    private func finish(_ result: Result<ModeSnapshot, Error>) {
        guard let completedOperation = activeOperation else { return }
        activeOperation = nil
        let operationIsCurrent = observedMode.isAwayMode
            && observedOwnershipID == completedOperation.ownershipID
        guard operationIsCurrent else {
            let followUp: ScreenLifecycleFollowUp
            switch completedOperation {
            case .unlockCheck:
                followUp = activity.finishUnlockCheck(
                    succeeded: true,
                    awayModeIsActive: observedMode.isAwayMode
                )
            case .resleep:
                followUp = activity.finishResleep(
                    succeeded: true,
                    awayModeIsActive: observedMode.isAwayMode
                )
            }
            perform(followUp)
            return
        }
        let succeeded: Bool
        switch result {
        case let .success(snapshot) where LifecycleObservationPolicy.accepts(snapshot):
            succeeded = Self.completionSucceeded(
                for: completedOperation.kind,
                snapshot: snapshot
            )
            modeDidChange(snapshot: snapshot)
            didFinish(snapshot, nil, completedOperation.kind)
        case let .success(snapshot):
            succeeded = false
            let error = ModeControlError.backend(
                snapshot.detail ?? "Caffeine Modes could not verify the active Amphetamine session."
            )
            didFinish(snapshot, error, completedOperation.kind)
        case let .failure(error):
            succeeded = false
            didFinish(nil, error, completedOperation.kind)
        }
        let followUp: ScreenLifecycleFollowUp
        switch completedOperation {
        case .unlockCheck:
            followUp = activity.finishUnlockCheck(
                succeeded: succeeded,
                awayModeIsActive: observedMode.isAwayMode
            )
        case .resleep:
            followUp = activity.finishResleep(
                succeeded: succeeded,
                awayModeIsActive: observedMode.isAwayMode
            )
        }
        perform(followUp)
    }

    private func perform(_ followUp: ScreenLifecycleFollowUp) {
        switch followUp {
        case .none:
            break
        case .checkUnlockNow:
            checkForUnlock()
        case .retryUnlockAfterDelay:
            unlockRetryTimer?.invalidate()
            unlockRetryTimer = LifecycleTimerScheduler.schedule(after: 1) { [weak self] in
                self?.checkForUnlock()
            }
        case .retryResleepAfterDelay:
            timer?.invalidate()
            timer = LifecycleTimerScheduler.schedule(after: 30) { [weak self] in
                guard let self else { return }
                self.timer = nil
                guard
                      self.observedMode.policy.resleepsAfterDisplayWake,
                      self.observedOwnershipID != nil,
                      self.activity.requestResleep()
                else { return }
                self.startResleep()
            }
        case .resleepNow:
            guard activity.requestResleep() else { return }
            startResleep()
        }
    }
}

@MainActor
enum LifecycleTimerScheduler {
    static func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        return timer
    }
}

private final class ScreenLifecycleRunner: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.andreaslar.caffeinemodes.screen-lifecycle",
        qos: .userInitiated
    )
    private let controller: ModeControlling

    init(controller: ModeControlling) {
        self.controller = controller
    }

    func handleScreenUnlocked(
        expectedOwnershipID: UUID,
        _ completion: @escaping @MainActor (Result<ModeSnapshot, Error>) -> Void
    ) {
        perform({
            try self.controller.handleScreenUnlocked(expectedOwnershipID: expectedOwnershipID)
        }, completion: completion)
    }

    func resleepNightIfLocked(
        expectedOwnershipID: UUID,
        _ completion: @escaping @MainActor (Result<ModeSnapshot, Error>) -> Void
    ) {
        perform({
            try self.controller.resleepNightIfLocked(expectedOwnershipID: expectedOwnershipID)
        }, completion: completion)
    }

    private func perform(
        _ operation: @escaping @Sendable () throws -> ModeSnapshot,
        completion: @escaping @MainActor (Result<ModeSnapshot, Error>) -> Void
    ) {
        queue.async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(result) }
            }
        }
    }
}
