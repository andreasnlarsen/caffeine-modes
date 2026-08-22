import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var controller: ModeControlling?
    private var terminationRouter: ApplicationTerminationRouter?
    private var systemWillPowerOff = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = UserDefaultsModeStore()
        let assertions = IOKitPowerAssertionInspector()
        let controller = ModeController(
            amphetamine: AmphetamineClient(),
            assertions: assertions,
            screenLock: SystemScreenLockPolicyChecker(),
            display: PMSetDisplaySleeper(),
            store: store
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
            launchManager: LaunchAtLoginManager(),
            requestQuit: { NSApplication.shared.terminate(nil) }
        )
        self.controller = controller
        self.terminationRouter = terminationRouter
        self.menuBarController = menuBarController
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
        if request == .user, menuBarController?.hasControllerWorkInProgress == true {
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
