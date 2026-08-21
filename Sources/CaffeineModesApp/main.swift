import AppKit
import CaffeineModesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = UserDefaultsModeStore()
        let controller = ModeController(
            amphetamine: AmphetamineClient(),
            assertions: IOKitPowerAssertionInspector(),
            screenLock: SystemScreenLockPolicyChecker(),
            display: PMSetDisplaySleeper(),
            store: store
        )
        let menuBarController = MenuBarController(
            controller: controller,
            store: store,
            launchManager: LaunchAtLoginManager()
        )
        self.menuBarController = menuBarController
        menuBarController.showSetupIfNeeded()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
