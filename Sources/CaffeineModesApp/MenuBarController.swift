import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore
import Foundation

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let controllerRunner: MenuControllerRunner
    private let store: ModeStateStoring
    private let launchManager: LaunchAtLoginManaging
    private let requestQuit: () -> Void
    private let setupWindow: SetupWindowController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "Checking status…", action: nil, keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Caffeine Modes", action: #selector(quitApp), keyEquivalent: "q")
    private var modeItems: [OperatingModeKey: NSMenuItem] = [:]
    private var snapshot = ModeSnapshot(requestedMode: .off, observedState: nil, ownershipMarker: nil, health: .setupIncomplete)
    private var powerReport: PowerAssertionReport?
    private var refreshCoordinator = RefreshRequestCoordinator()
    private var transitionInProgress = false
    private var timer: Timer?
    private lazy var modeSelectionCoordinator = ModeSelectionCoordinator(
        transition: { [controllerRunner] mode, authorization in
            try await controllerRunner.transition(
                to: mode,
                authorizingReplacement: authorization
            )
        },
        confirm: { [weak self] reason in
            self?.confirmModeSelection(reason) ?? false
        }
    )

    init(
        controller: ModeControlling,
        assertions: PowerAssertionInspecting,
        store: ModeStateStoring,
        launchManager: LaunchAtLoginManaging,
        requestQuit: @escaping () -> Void
    ) {
        self.controllerRunner = MenuControllerRunner(
            controller: controller,
            assertions: assertions
        )
        self.store = store
        self.launchManager = launchManager
        self.requestQuit = requestQuit
        self.setupWindow = SetupWindowController(controller: controller)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        setupWindow.onSetupCompleted = { [weak self] in
            self?.showLaunchAtLoginPromptIfNeeded()
        }
        setupWindow.onWorkFinished = { [weak self] in
            self?.refresh()
        }
        configureMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func showSetupIfNeeded() {
        setupWindow.checkAndShowIfNeeded { [weak self] isReady in
            guard let self else { return }
            if isReady {
                self.showLaunchAtLoginPromptIfNeeded()
            } else {
                self.refresh()
            }
        }
    }

    private func showLaunchAtLoginPromptIfNeeded() {
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

        quitItem.target = self
        menu.addItem(quitItem)
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
        updateMenuAvailability()
        switch menuActivity.menuOpenBehavior {
        case .showSetupBusy:
            statusLine.title = "Setup check in progress…"
        case .preserveCurrentStatus:
            break
        case .refreshStatus:
            refresh()
        }
    }

    @objc private func selectOff() { select(.off) }
    @objc private func selectWork() { select(.work) }
    @objc private func selectNight() { select(.night) }

    @objc private func selectTravel(_ sender: NSMenuItem) {
        select(.travel(durationMinutes: sender.tag, expiresAt: Date()))
    }

    private func select(_ mode: OperatingMode) {
        guard !setupWindow.isBusy, !transitionInProgress else { return }
        transitionInProgress = true
        statusLine.title = "Checking \(mode.displayName)…"
        updateMenuAvailability()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let selected = try await self.modeSelectionCoordinator.select(mode) {
                    self.snapshot = selected
                }
            } catch {
                self.showError(error)
            }
            self.transitionInProgress = false
            self.updateMenuAvailability()
            self.refresh()
        }
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

    var hasControllerWorkInProgress: Bool {
        menuActivity.hasControllerWorkInProgress
    }

    func presentBusyQuitMessage() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Caffeine Modes Is Busy"
        alert.informativeText = "Wait for the current status or setup check to finish before you quit Caffeine Modes."
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        let blocked = setupWindow.isBusy || transitionInProgress
        guard refreshCoordinator.request(blocked: blocked) else {
            updateMenuAvailability()
            return
        }
        updateMenuAvailability()
        controllerRunner.fetchStatus { [weak self] snapshot, report in
            guard let self else { return }
            let shouldRetry = self.refreshCoordinator.finish()
            if self.menuActivity.acceptsRefreshResults {
                self.snapshot = snapshot
                self.powerReport = report
                self.updateCheckmarks()
                self.updateStatus()
            }
            self.launchItem.state = self.launchManager.isEnabled ? .on : .off
            self.updateMenuAvailability()
            if shouldRetry {
                self.refresh()
            }
        }
    }

    private func updateMenuAvailability() {
        let activity = menuActivity
        modeItems.values.forEach { $0.isEnabled = activity.modesAreEnabled }
        quitItem.isEnabled = activity.quitIsEnabled
    }

    private var menuActivity: MenuActivityPolicy {
        MenuActivityPolicy(
            setupIsBusy: setupWindow.isBusy,
            transitionIsInProgress: transitionInProgress,
            refreshIsInProgress: refreshCoordinator.isInProgress
        )
    }

    private func updateCheckmarks() {
        modeItems.values.forEach { $0.state = .off }
        let key = OperatingModeKey(snapshot.requestedMode)
        modeItems[key]?.state = .on
    }

    private func updateStatus() {
        let title: String
        let toolTip: String
        let symbol: String
        if snapshot.health != .ready && snapshot.requestedMode != .custom {
            title = snapshot.detail ?? "Setup needs attention"
            toolTip = "Caffeine Modes — \(title)"
            symbol = "exclamationmark.triangle.fill"
        } else if snapshot.requestedMode == .custom {
            title = snapshot.detail ?? "Custom Amphetamine session"
            toolTip = "Caffeine Modes — \(title)"
            symbol = "exclamationmark.triangle.fill"
        } else {
            let travelSeconds: Int?
            if case let .travel(_, expiresAt) = snapshot.requestedMode {
                travelSeconds = max(0, Int(expiresAt.timeIntervalSinceNow.rounded(.up)))
            } else {
                travelSeconds = nil
            }
            let presentation = PowerStatusPresentation.make(
                mode: snapshot.requestedMode,
                report: powerReport,
                travelSecondsRemaining: travelSeconds
            )
            title = presentation.statusLine
            toolTip = presentation.toolTip
            if presentation.hasUnexpectedDisplayBlocker || presentation.hasInspectionError {
                symbol = "exclamationmark.triangle.fill"
            } else {
                switch snapshot.requestedMode {
                case .off: symbol = "cup.and.saucer"
                case .work: symbol = "cup.and.saucer.fill"
                case .night: symbol = "moon.fill"
                case .travel: symbol = "car.fill"
                case .custom: symbol = "exclamationmark.triangle.fill"
                }
            }
        }

        statusLine.title = title
        statusItem.button?.toolTip = toolTip
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private final class MenuControllerRunner: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.andreaslar.caffeinemodes.menu-controller",
        qos: .userInitiated
    )
    private let controller: ModeControlling
    private let assertions: PowerAssertionInspecting

    init(controller: ModeControlling, assertions: PowerAssertionInspecting) {
        self.controller = controller
        self.assertions = assertions
    }

    func fetchStatus(
        _ completion: @escaping @MainActor (ModeSnapshot, PowerAssertionReport?) -> Void
    ) {
        queue.async {
            let snapshot = self.controller.reconcile()
            let report = try? self.assertions.inspect(timeout: 0.25)
            Self.deliver { completion(snapshot, report) }
        }
    }

    func transition(
        to mode: OperatingMode,
        authorizingReplacement: Bool
    ) async throws -> ModeSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(
                        returning: try self.controller.transition(
                            to: mode,
                            replacingActiveSession: authorizingReplacement
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func deliver(_ update: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(update)
        }
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
