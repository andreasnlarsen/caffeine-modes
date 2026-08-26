import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore
import Foundation

enum MenuBarCopy {
    static let aboutInformativeText =
        "Three clear Amphetamine modes for work, night, and short travel.\n\n"
        + "Night and Travel can make a closed Mac hot. "
        + "Do not run a closed Mac inside an enclosed bag."
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let controllerRunner: MenuControllerRunner
    private let store: ModeStateStoring
    private let launchManager: LaunchAtLoginManaging
    private let requestQuit: () -> Void
    private let settingsWindow: SettingsWindowController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "Checking status…", action: nil, keyEquivalent: "")
    private let safetyDetailItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let retrySafetyItem = NSMenuItem(title: "Try Again", action: #selector(retryModeSafety), keyEquivalent: "")
    private let turnOffSafetyItem = NSMenuItem(title: "Turn Off", action: #selector(turnOffDegradedMode), keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Caffeine Modes", action: #selector(quitApp), keyEquivalent: "q")
    private var modeItems: [OperatingModeKey: NSMenuItem] = [:]
    private var snapshot = ModeSnapshot(requestedMode: .off, observedState: nil, ownershipMarker: nil, health: .setupIncomplete)
    private var powerReport: PowerAssertionReport?
    private var lifecycleError = LifecycleErrorState()
    private var refreshCoordinator = RefreshRequestCoordinator()
    private var transitionInProgress = false
    private var timer: Timer?
    private var hasObservedSnapshot = false
    private var lastObservationWasRestoredSession = false
    private var postUnlockChoice = PostUnlockChoiceState()
    private weak var observedModalWindow: NSWindow?
    private var modalDismissalObservers: [NSObjectProtocol] = []
    var onModeObserved: ((ModeSnapshot, Bool) -> Void)? {
        didSet {
            if hasObservedSnapshot {
                onModeObserved?(snapshot, lastObservationWasRestoredSession)
            }
        }
    }
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
        batteryProtectionRequirement: BatteryProtectionRequirementStoring,
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
        self.settingsWindow = SettingsWindowController(
            controller: controller,
            store: store,
            batteryProtectionRequirement: batteryProtectionRequirement,
            launchManager: launchManager
        )
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        settingsWindow.onSetupCompleted = { [weak self] in
            self?.showLaunchAtLoginPromptIfNeeded()
        }
        settingsWindow.onWorkFinished = { [weak self] in
            self?.refresh()
        }
        settingsWindow.onBatteryProtectionRequirementChanged = { [weak self] in
            self?.refresh()
        }
        configureMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func showSetupIfNeeded() {
        settingsWindow.checkAndShowIfNeeded { [weak self] isReady in
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
        safetyDetailItem.isEnabled = false
        safetyDetailItem.isHidden = true
        menu.addItem(safetyDetailItem)
        retrySafetyItem.target = self
        retrySafetyItem.isHidden = true
        menu.addItem(retrySafetyItem)
        turnOffSafetyItem.target = self
        turnOffSafetyItem.isHidden = true
        menu.addItem(turnOffSafetyItem)
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

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let modesHelp = NSMenuItem(title: "How Modes Work…", action: #selector(showModesHelp), keyEquivalent: "")
        modesHelp.target = self
        menu.addItem(modesHelp)
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

    private func select(
        _ mode: OperatingMode,
        postUnlockOwnershipID: UUID? = nil
    ) {
        guard !settingsWindow.isBusy, !transitionInProgress else { return }
        transitionInProgress = true
        statusLine.title = "Checking \(mode.displayName)…"
        updateMenuAvailability()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if case .travel = mode {
                    self.powerReport = await self.controllerRunner.fetchPowerReport()
                }
                if let selected = try await self.modeSelectionCoordinator.select(mode) {
                    self.snapshot = selected
                    self.lifecycleError.clear()
                    self.publishModeObservation(selected)
                } else if let postUnlockOwnershipID {
                    self.postUnlockChoice.cancelPresentation(for: postUnlockOwnershipID)
                }
            } catch {
                if let postUnlockOwnershipID {
                    self.postUnlockChoice.transitionFailed(for: postUnlockOwnershipID)
                }
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
        var message = presentation.message
        let targetMode: OperatingMode
        switch reason {
        case let .start(mode), let .replaceActiveSession(mode):
            targetMode = mode
        }
        if case .travel = targetMode,
           let warning = TravelAssertionWarningPresentation.message(
               processes: powerReport?.displaySleepBlockingProcesses ?? []
           ) {
            message += "\n\n\(warning)"
        }
        alert.informativeText = message
        alert.addButton(withTitle: presentation.confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func showSettings() {
        settingsWindow.showWindow(nil)
    }

    @objc private func retryModeSafety() {
        guard !settingsWindow.isBusy,
              !transitionInProgress,
              let ownershipID = snapshot.ownershipMarker?.id
        else { return }
        let mode = snapshot.requestedMode
        guard mode == .night || mode.travelDurationMinutes != nil else { return }

        transitionInProgress = true
        statusLine.title = mode == .night ? "Retrying display sleep…" : "Trying to lock…"
        updateMenuAvailability()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let retried = try await self.controllerRunner.retrySafety(
                    for: mode,
                    expectedOwnershipID: ownershipID
                )
                self.snapshot = retried
                self.lifecycleError.clear()
                self.publishModeObservation(retried)
            } catch {
                self.showError(error)
            }
            self.transitionInProgress = false
            self.updateMenuAvailability()
            self.refresh()
        }
    }

    @objc private func turnOffDegradedMode() {
        select(.off)
    }

    @objc private func showModesHelp() {
        settingsWindow.show(pane: .modes)
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
        alert.informativeText = MenuBarCopy.aboutInformativeText
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

    func lifecycleDidFinish(
        snapshot: ModeSnapshot?,
        error: Error?,
        operation: ScreenLifecycleController.Operation.Kind
    ) {
        if let snapshot {
            self.snapshot = snapshot
            if LifecycleObservationPolicy.accepts(snapshot) {
                publishModeObservation(snapshot)
            }
            requestPostUnlockChoiceIfNeeded(snapshot)
        }
        let failure = error.map {
            ($0 as? LocalizedError)?.errorDescription ?? $0.localizedDescription
        }
        if error == nil {
            lifecycleError.noteSuccessfulLifecycleCheck()
            if operation == .resleep,
               let snapshot,
               ScreenLifecycleController.completionSucceeded(
                   for: operation,
                   snapshot: snapshot
               ) {
                lifecycleError.noteSuccessfulResleep()
            }
        }
        let requiresSuccessfulLifecycleCheck: Bool
        if case .screenLockStateUnavailable = error as? ModeControlError {
            requiresSuccessfulLifecycleCheck = true
        } else {
            requiresSuccessfulLifecycleCheck = false
        }
        lifecycleError.recordFailure(
            failure,
            at: Date(),
            requiresSuccessfulLifecycleCheck: requiresSuccessfulLifecycleCheck,
            requiresSuccessfulResleep: operation == .resleep
        )
        refresh()
    }

    var hasControllerWorkInProgress: Bool {
        menuActivity.hasControllerWorkInProgress
    }

    func presentBusyQuitMessage() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Caffeine Modes Is Busy"
        alert.informativeText = "Wait for the current task to finish before you quit Caffeine Modes."
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
        let blocked = settingsWindow.isBusy || transitionInProgress
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
                self.lifecycleError.refresh(
                    snapshot: snapshot,
                    report: report,
                    now: Date()
                )
                if LifecycleObservationPolicy.accepts(snapshot) {
                    self.publishModeObservation(
                        snapshot,
                        restoredSession: !self.hasObservedSnapshot && snapshot.requestedMode.isAwayMode
                    )
                }
                self.updateCheckmarks()
                self.updateStatus()
                self.presentPendingPostUnlockChoiceIfPossible(snapshot)
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
        retrySafetyItem.isEnabled = activity.modesAreEnabled
        turnOffSafetyItem.isEnabled = activity.modesAreEnabled
        quitItem.isEnabled = activity.quitIsEnabled
    }

    private func publishModeObservation(
        _ snapshot: ModeSnapshot,
        restoredSession: Bool = false
    ) {
        let awayOwnershipID = snapshot.requestedMode.isAwayMode
            ? snapshot.ownershipMarker?.id
            : nil
        postUnlockChoice.modeDidChange(awayOwnershipID: awayOwnershipID)
        hasObservedSnapshot = true
        lastObservationWasRestoredSession = restoredSession
        onModeObserved?(snapshot, restoredSession)
    }

    private var menuActivity: MenuActivityPolicy {
        MenuActivityPolicy(
            setupIsBusy: settingsWindow.isBusy,
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
        updateSafetyRecoveryItems()
        let title: String
        let toolTip: String
        let symbol: String
        var statusAccessibilityDescription: String?
        if snapshot.requestedMode.isAwayMode,
           snapshot.ownershipMarker?.id == postUnlockChoice.activeOwnershipID {
            title = "\(snapshot.requestedMode.displayName) is still active · Choose Off or Work"
            toolTip = "Caffeine Modes — \(title)"
            symbol = "exclamationmark.circle"
        } else if let lifecycleError = lifecycleError.message {
            title = lifecycleError
            toolTip = "Caffeine Modes — \(lifecycleError)"
            symbol = "exclamationmark.triangle.fill"
            self.lifecycleError.markPresented()
        } else if snapshot.health != .ready && snapshot.requestedMode != .custom {
            title = snapshot.detail ?? "Setup needs attention"
            toolTip = "Caffeine Modes — \(title)"
            symbol = "exclamationmark.triangle.fill"
        } else if snapshot.requestedMode == .custom {
            if snapshot.health == .ready,
               snapshot.ownershipMarker?.purpose == .readinessTest,
               case let .travel(_, expiresAt)? = snapshot.ownershipMarker?.mode {
                let seconds = max(0, Int(expiresAt.timeIntervalSinceNow.rounded(.up)))
                title = "Closed-lid diagnostic passed · Ends in \(TravelCountdownFormatter.string(seconds: seconds))"
                toolTip = "Caffeine Modes — \(title)"
                symbol = "hourglass"
            } else {
                title = snapshot.detail ?? "Custom Amphetamine session"
                toolTip = "Caffeine Modes — \(title)"
                symbol = "exclamationmark.triangle.fill"
            }
        } else {
            let travelSeconds: Int?
            if case let .travel(_, expiresAt) = snapshot.requestedMode {
                travelSeconds = max(0, Int(expiresAt.timeIntervalSinceNow.rounded(.up)))
            } else {
                travelSeconds = nil
            }
            let presentation = PowerStatusPresentation.make(
                mode: snapshot.requestedMode,
                safety: snapshot.safety,
                report: powerReport,
                travelSecondsRemaining: travelSeconds
            )
            title = presentation.statusLine
            toolTip = presentation.toolTip
            statusAccessibilityDescription = presentation.accessibilityDescription
            if presentation.hasModeSafetyWarning || presentation.hasInspectionError {
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
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: statusAccessibilityDescription ?? title
        )
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func updateSafetyRecoveryItems() {
        let postUnlockChoiceIsActive = snapshot.ownershipMarker?.id == postUnlockChoice.activeOwnershipID
        guard snapshot.safety != .ready, !postUnlockChoiceIsActive else {
            safetyDetailItem.isHidden = true
            retrySafetyItem.isHidden = true
            turnOffSafetyItem.isHidden = true
            return
        }
        guard let recovery = ModeSafetyRecoveryPresentation.make(
            mode: snapshot.requestedMode,
            safety: snapshot.safety,
            report: powerReport
        ) else {
            safetyDetailItem.isHidden = true
            retrySafetyItem.isHidden = true
            turnOffSafetyItem.isHidden = true
            return
        }
        safetyDetailItem.title = recovery.detail
        safetyDetailItem.isHidden = false
        retrySafetyItem.title = recovery.retryTitle
        turnOffSafetyItem.title = recovery.turnOffTitle
        retrySafetyItem.isHidden = false
        turnOffSafetyItem.isHidden = false
    }

    private func requestPostUnlockChoiceIfNeeded(_ snapshot: ModeSnapshot) {
        guard snapshot.requiresPostUnlockChoice,
              let ownershipID = snapshot.ownershipMarker?.id
        else { return }
        postUnlockChoice.request(for: ownershipID)
        updateStatus()
        presentPendingPostUnlockChoiceIfPossible(snapshot)
    }

    private func presentPendingPostUnlockChoiceIfPossible(_ snapshot: ModeSnapshot) {
        let modalWindow = NSApplication.shared.modalWindow
        let isBusy = PostUnlockPresentationPolicy.isBusy(
            setupIsBusy: settingsWindow.isBusy,
            transitionIsInProgress: transitionInProgress,
            modalWindowIsOpen: modalWindow != nil
        )
        guard snapshot.requestedMode.isAwayMode,
              let currentOwnershipID = snapshot.ownershipMarker?.id,
              currentOwnershipID == postUnlockChoice.activeOwnershipID
        else { return }
        if let modalWindow {
            observeModalDismissal(modalWindow)
        }
        guard let ownershipID = postUnlockChoice.presentationIfReady(
            isBusy: isBusy,
            prepareForPresentation: {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        ) else { return }
        let mode: OperatingMode = store.postUnlockMode == .work ? .work : .off
        select(mode, postUnlockOwnershipID: ownershipID)
    }

    private func observeModalDismissal(_ window: NSWindow) {
        guard observedModalWindow !== window else { return }
        stopObservingModalDismissal()
        observedModalWindow = window
        let windowID = ObjectIdentifier(window)
        let center = NotificationCenter.default
        for name in [
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didEndSheetNotification
        ] {
            modalDismissalObservers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.modalWindowDidDismiss(windowID)
                        }
                    }
                }
            )
        }
    }

    private func modalWindowDidDismiss(_ windowID: ObjectIdentifier) {
        guard observedModalWindow.map(ObjectIdentifier.init) == windowID else { return }
        stopObservingModalDismissal()
        if let nextModalWindow = NSApplication.shared.modalWindow {
            observeModalDismissal(nextModalWindow)
        } else {
            presentPendingPostUnlockChoiceIfPossible(snapshot)
        }
    }

    private func stopObservingModalDismissal() {
        let center = NotificationCenter.default
        modalDismissalObservers.forEach(center.removeObserver)
        modalDismissalObservers.removeAll()
        observedModalWindow = nil
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.runModal()
    }
}

final class MenuControllerRunner: @unchecked Sendable {
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

    func fetchPowerReport() async -> PowerAssertionReport? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(
                    returning: try? self.assertions.inspect(timeout: 0.25)
                )
            }
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

    func retrySafety(
        for mode: OperatingMode,
        expectedOwnershipID: UUID
    ) async throws -> ModeSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let snapshot: ModeSnapshot
                    if mode == .night {
                        snapshot = try self.controller.retryNightDisplaySleep(
                            expectedOwnershipID: expectedOwnershipID
                        )
                    } else {
                        snapshot = try self.controller.retryTravelLock(
                            expectedOwnershipID: expectedOwnershipID
                        )
                    }
                    continuation.resume(returning: snapshot)
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
