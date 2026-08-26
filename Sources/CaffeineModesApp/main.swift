import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var screenLifecycleController: ScreenLifecycleController?
    private var controller: ModeControlling?
    private var terminationRouter: ApplicationTerminationRouter?
    private var systemWillPowerOff = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = UserDefaultsModeStore()
        let assertions = IOKitPowerAssertionInspector()
        let controller = ModeController(
            amphetamine: AmphetamineClient(),
            screenLock: SystemScreenLockPolicyChecker(),
            screenLockState: CGSessionScreenLockStateInspector(),
            powerProtect: AmphetaminePowerProtectInspector(),
            clamshellContext: SystemClamshellContextInspector(),
            display: PMSetDisplaySleeper(),
            displayState: SystemDisplayStateInspector(),
            store: store,
            batteryProtection: AmphetamineBatteryProtectionInspector(),
            batteryProtectionRequirement: store
        )
        let terminationRouter = ApplicationTerminationRouter(
            coordinator: ApplicationTerminationCoordinator(
                hasActiveSession: controller.hasActiveSessionForQuit,
                endActiveSession: controller.endActiveSessionForQuit,
                choose: { [weak self] in
                    self?.menuBarController?.confirmQuitWithActiveSession() ?? .cancel
                },
                chooseWhenInspectionFails: { [weak self] in
                    self?.menuBarController?.confirmQuitWithoutInspection() ?? .cancel
                }
            )
        )
        let menuBarController = MenuBarController(
            controller: controller,
            assertions: assertions,
            store: store,
            batteryProtectionRequirement: store,
            launchManager: LaunchAtLoginManager(),
            requestQuit: { NSApplication.shared.terminate(nil) }
        )
        let screenLifecycleController = ScreenLifecycleController(
            controller: controller,
            didFinish: { [weak menuBarController] snapshot, error, operation in
                menuBarController?.lifecycleDidFinish(
                    snapshot: snapshot,
                    error: error,
                    operation: operation
                )
            }
        )
        menuBarController.onModeObserved = { [weak screenLifecycleController] snapshot, restoredSession in
            screenLifecycleController?.modeDidChange(
                snapshot: snapshot,
                restoredSession: restoredSession
            )
        }
        self.controller = controller
        self.terminationRouter = terminationRouter
        self.menuBarController = menuBarController
        self.screenLifecycleController = screenLifecycleController
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillPowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
        menuBarController.showSetupIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationRouter else { return .terminateNow }

        let request = currentTerminationRequest()
        let userTaskIsRunning = menuBarController?.hasControllerWorkInProgress == true
            || screenLifecycleController?.isBusy == true
        if request == .user, userTaskIsRunning {
            menuBarController?.presentBusyQuitMessage()
            return .terminateCancel
        }

        do {
            switch try terminationRouter.decision(for: request) {
            case .terminateNow: return .terminateNow
            case .terminateCancel: return .terminateCancel
            }
        } catch {
            menuBarController?.presentTerminationError(error)
            return .terminateCancel
        }
    }

    @objc private func handleSystemWillPowerOff(_ notification: Notification) {
        systemWillPowerOff = true
    }

    private func currentTerminationRequest() -> ApplicationTerminationRequest {
        let quitReason = NSAppleEventManager.shared()
            .currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?
            .typeCodeValue
        return ApplicationTerminationClassifier.request(
            systemWillPowerOff: systemWillPowerOff,
            appleEventQuitReason: quitReason
        )
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
