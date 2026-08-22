import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore
import Foundation

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let controller: ModeControlling
    private let store: ModeStateStoring
    private let launchManager: LaunchAtLoginManaging
    private let requestQuit: () -> Void
    private let setupWindow: SetupWindowController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "Checking status…", action: nil, keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var modeItems: [OperatingModeKey: NSMenuItem] = [:]
    private var snapshot = ModeSnapshot(requestedMode: .off, observedState: nil, ownershipMarker: nil, health: .setupIncomplete)
    private var timer: Timer?
    private lazy var modeSelectionCoordinator = ModeSelectionCoordinator(
        transition: { [controller] mode, authorization in
            try controller.transition(to: mode, replacingActiveSession: authorization)
        },
        confirm: { [weak self] reason in
            self?.confirmModeSelection(reason) ?? false
        }
    )

    init(
        controller: ModeControlling,
        store: ModeStateStoring,
        launchManager: LaunchAtLoginManaging,
        requestQuit: @escaping () -> Void
    ) {
        self.controller = controller
        self.store = store
        self.launchManager = launchManager
        self.requestQuit = requestQuit
        self.setupWindow = SetupWindowController(controller: controller)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func showSetupIfNeeded() {
        if !controller.setupReport().isReady {
            setupWindow.showWindow(nil)
        }

        guard !store.launchAtLoginPromptWasShown else { return }
        store.launchAtLoginPromptWasShown = true
        let alert = NSAlert()
        alert.messageText = "Launch Caffeine Modes at Login?"
        alert.informativeText = "Recommended. This keeps your menu-bar control ready after each restart."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try launchManager.setEnabled(true)
            } catch {
                showError(error)
            }
        }
        refresh()
    }

    private func configureMenu() {
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        addModeItem(title: "Off", key: .off, action: #selector(selectOff))
        addModeItem(title: "Work", key: .work, action: #selector(selectWork))
        addModeItem(title: "Night", key: .night, action: #selector(selectNight))

        let travel = NSMenuItem(title: "Travel", action: nil, keyEquivalent: "")
        let travelMenu = NSMenu(title: "Travel")
        for minutes in OperatingMode.allowedTravelDurations {
            let item = NSMenuItem(title: "\(minutes) Minutes", action: #selector(selectTravel(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            travelMenu.addItem(item)
            modeItems[.travel(minutes)] = item
        }
        travel.submenu = travelMenu
        menu.addItem(travel)
        menu.addItem(.separator())

        let setup = NSMenuItem(title: "Setup Status…", action: #selector(showSetup), keyEquivalent: ",")
        setup.target = self
        menu.addItem(setup)
        launchItem.target = self
        menu.addItem(launchItem)

        let about = NSMenuItem(title: "About Caffeine Modes", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Caffeine Modes", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }

    private func addModeItem(title: String, key: OperatingModeKey, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        modeItems[key] = item
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func selectOff() { select(.off) }
    @objc private func selectWork() { select(.work) }
    @objc private func selectNight() { select(.night) }

    @objc private func selectTravel(_ sender: NSMenuItem) {
        select(.travel(durationMinutes: sender.tag, expiresAt: Date()))
    }

    private func select(_ mode: OperatingMode) {
        do {
            if let selected = try modeSelectionCoordinator.select(mode) {
                snapshot = selected
            }
        } catch {
            showError(error)
        }
        refresh()
    }

    private func confirmModeSelection(_ reason: ModeSelectionConfirmation) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let presentation = reason.presentation
        alert.messageText = presentation.title
        alert.informativeText = presentation.message
        alert.addButton(withTitle: presentation.confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func showSetup() {
        setupWindow.showWindow(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchManager.setEnabled(!launchManager.isEnabled)
        } catch {
            showError(error)
        }
        refresh()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Caffeine Modes"
        alert.informativeText = "Three safe Amphetamine modes for work, night, and short travel.\n\nTravel is not thermal protection. Do not run a Mac in an enclosed bag."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        requestQuit()
    }

    func presentTerminationError(_ error: Error) {
        showError(error)
        refresh()
    }

    func confirmQuitWithActiveSession() -> ActiveSessionQuitChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let presentation = ActiveSessionQuitConfirmationPresentation.activeSession
        alert.messageText = presentation.title
        alert.informativeText = presentation.message
        alert.addButton(withTitle: presentation.endButtonTitle)
        alert.addButton(withTitle: presentation.leaveButtonTitle)
        alert.addButton(withTitle: presentation.cancelButtonTitle)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .endAndQuit
        case .alertSecondButtonReturn: return .leaveRunning
        default: return .cancel
        }
    }

    func confirmQuitWithoutInspection() -> UninspectedSessionQuitChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let presentation = UninspectedSessionQuitConfirmationPresentation.inspectionFailed
        alert.messageText = presentation.title
        alert.informativeText = presentation.message
        alert.addButton(withTitle: presentation.leaveButtonTitle)
        alert.addButton(withTitle: presentation.cancelButtonTitle)
        return alert.runModal() == .alertFirstButtonReturn
            ? .leaveUnchangedAndQuit
            : .cancel
    }

    private func refresh() {
        snapshot = controller.reconcile()
        updateCheckmarks()
        updateStatus()
        launchItem.state = launchManager.isEnabled ? .on : .off
    }

    private func updateCheckmarks() {
        modeItems.values.forEach { $0.state = .off }
        let key = OperatingModeKey(snapshot.requestedMode)
        modeItems[key]?.state = .on
    }

    private func updateStatus() {
        let title: String
        let symbol: String
        if snapshot.health != .ready && snapshot.requestedMode != .custom {
            title = snapshot.detail ?? "Setup needs attention"
            symbol = "exclamationmark.triangle.fill"
        } else {
            switch snapshot.requestedMode {
            case .off:
                title = externalBlockerSummary(prefix: "Off")
                symbol = "cup.and.saucer"
            case .work:
                title = "Work · Mac and displays stay awake"
                symbol = "cup.and.saucer.fill"
            case .night:
                title = "Night · Display asleep, Mac awake"
                symbol = "moon.fill"
            case let .travel(_, expiresAt):
                let remaining = max(0, Int(expiresAt.timeIntervalSinceNow.rounded(.up)))
                title = "Travel · \(TravelCountdownFormatter.string(seconds: remaining)) remaining"
                symbol = "car.fill"
            case .custom:
                title = snapshot.detail ?? "Custom Amphetamine session"
                symbol = "exclamationmark.triangle.fill"
            }
        }

        statusLine.title = title
        statusItem.button?.toolTip = "Caffeine Modes — \(title)"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func externalBlockerSummary(prefix: String) -> String {
        let blockers = (try? IOKitPowerAssertionInspector().displaySleepBlockingProcesses(timeout: 0.25)) ?? []
        guard !blockers.isEmpty else { return prefix }
        return "\(prefix) · Display held awake by \(blockers.joined(separator: ", "))"
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private enum OperatingModeKey: Hashable {
    case off
    case work
    case night
    case travel(Int)
    case custom

    init(_ mode: OperatingMode) {
        switch mode {
        case .off: self = .off
        case .work: self = .work
        case .night: self = .night
        case let .travel(durationMinutes, _): self = .travel(durationMinutes)
        case .custom: self = .custom
        }
    }
}
