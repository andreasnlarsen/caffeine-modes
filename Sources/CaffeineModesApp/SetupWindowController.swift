import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private typealias AcceptedSetupReportHandler = @MainActor (SetupReport) -> Void

    enum Pane: String {
        case general
        case setup
        case modes
        case developer

        var identifier: NSToolbarItem.Identifier { .init(rawValue) }

        var title: String {
            switch self {
            case .general: "General"
            case .setup: "Setup"
            case .modes: "Modes"
            case .developer: "Developer"
            }
        }

        var symbolName: String {
            switch self {
            case .general: "gearshape"
            case .setup: "checklist"
            case .modes: "cup.and.saucer"
            case .developer: "wrench.and.screwdriver"
            }
        }
    }

    private enum Activity {
        case idle
        case refreshing
        case disablingTriggers
        case runningDiagnostic
    }

    private let runner: SettingsCheckRunner
    private let store: ModeStateStoring
    private let batteryProtectionRequirement: BatteryProtectionRequirementStoring
    private let launchManager: LaunchAtLoginManaging

    private let contentHost = NSView()
    private var appearanceObservation: NSKeyValueObservation?
    private lazy var generalView = makeGeneralView()
    private lazy var setupView = makeSetupView()
    private lazy var modesView = makeModesView()
    private lazy var developerView = makeDeveloperView()

    private let launchCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let unlockOffButton = NSButton(radioButtonWithTitle: "Off", target: nil, action: nil)
    private let unlockWorkButton = NSButton(radioButtonWithTitle: "Work", target: nil, action: nil)
    private let batteryProtectionCheckbox = NSButton(
        checkboxWithTitle: "Require battery protection for Night and Travel at:",
        target: nil,
        action: nil
    )
    private let batteryProtectionPercentPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let batteryProtectionNote = NSTextField(labelWithString: "")

    private let amphetamineRow = SetupRowView()
    private let automationRow = SetupRowView()
    private let triggersRow = SetupRowView()
    private let screenLockRow = SetupRowView()
    private let powerProtectRow = SetupRowView()
    private let batteryProtectionRow = SetupRowView()
    private let setupSummaryLabel = NSTextField(labelWithString: "")
    private let setupSpinner = NSProgressIndicator()
    private let checkAgainButton = NSButton(title: "Check Again", target: nil, action: nil)

    private let diagnosticStatus = NSTextField(wrappingLabelWithString: "Not run")
    private let diagnosticIcon = NSImageView()
    private let diagnosticSpinner = NSProgressIndicator()
    private let diagnosticButton = NSButton(title: "Run Diagnostic", target: nil, action: nil)

    private var activity = Activity.idle
    private var triggersFailure: String?
    private var diagnosticFailure: String?
    private var latestReport: SetupReport?
    private var selectedPane: Pane = .general
    private var developerIsVisible = false
    private var lastAnnouncedSummary: String?
    private var lastRefreshFinishedAt: TimeInterval = -.greatestFiniteMagnitude
    private var autoRefreshTask: Task<Void, Never>?
    private var completionCoordinator = SetupCompletionCoordinator()
    private var reportRefreshState = SetupReportRefreshState()

    var onSetupCompleted: (() -> Void)?
    var onWorkFinished: (() -> Void)?
    var onBatteryProtectionRequirementChanged: (() -> Void)?
    var confirmBatteryProtectionOptOut: (() -> Bool)?

    private var allRows: [SetupRowView] {
        [
            amphetamineRow,
            automationRow,
            triggersRow,
            screenLockRow,
            powerProtectRow,
            batteryProtectionRow
        ]
    }

    var isBusy: Bool {
        switch activity {
        case .idle: false
        case .refreshing, .disablingTriggers, .runningDiagnostic: true
        }
    }

    init(
        controller: ModeControlling,
        store: ModeStateStoring,
        batteryProtectionRequirement: BatteryProtectionRequirementStoring,
        launchManager: LaunchAtLoginManaging
    ) {
        self.runner = SettingsCheckRunner(controller: controller)
        self.store = store
        self.batteryProtectionRequirement = batteryProtectionRequirement
        self.launchManager = launchManager
        let window = SettingsWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsLayout.windowWidth,
                height: SettingsLayout.initialContentHeight
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.rebuildToolbarForAppearanceChange()
            }
        }
        configureContentHost()
        configureControls()
        configureToolbar()
        select(.general, refresh: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        let optionHeld = NSApp.currentEvent?.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.option) == true
        show(pane: .general, includeDeveloper: optionHeld)
    }

    func show(pane: Pane, includeDeveloper: Bool = false) {
        if developerIsVisible != includeDeveloper {
            developerIsVisible = includeDeveloper
            configureToolbar()
        }
        let destination = pane == .developer && !developerIsVisible ? .general : pane
        select(destination, refresh: destination == .setup || destination == .developer)
        super.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func checkAndShowIfNeeded(completion: @escaping @MainActor (Bool) -> Void) {
        guard activity == .idle else {
            completion(false)
            return
        }
        beginRefresh(userInitiated: false) { [weak self] report in
            guard let self else {
                completion(false)
                return
            }
            if !report.isReady || self.window?.isVisible == true {
                self.developerIsVisible = false
                self.configureToolbar()
                self.select(.setup, refresh: false)
                self.showWindowWithoutRefresh()
            }
            completion(report.isReady)
        }
    }

    private func showWindowWithoutRefresh() {
        super.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        autoRefreshTask?.cancel()
        if selectedPane == .general {
            refreshGeneralControls()
        }
        guard selectedPane == .setup || selectedPane == .developer else { return }
        autoRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.autoRefreshIfIdle()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isBusy {
            completionCoordinator.noteCloseDuringRefresh()
            return true
        }
        if completionCoordinator.consumeCompletionForClose() {
            onSetupCompleted?()
        }
        return true
    }

    // MARK: - Toolbar

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "CaffeineModesSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbarStyle = .preference
        window?.toolbar = toolbar
        toolbar.selectedItemIdentifier = selectedPane.identifier
    }

    /// On current macOS, live WindowServer captures show the selected
    /// preference-toolbar capsule re-resolving on its own when the app's
    /// appearance changes; the earlier stale-capsule diagnosis came from
    /// offscreen `cacheDisplay` renders, which rasterize the glass capsule as
    /// an opaque white fallback and are not evidence of on-screen state. The
    /// rebuild stays as a low-cost guarantee for older supported systems that
    /// cannot be re-verified from this machine.
    private func rebuildToolbarForAppearanceChange() {
        guard window?.toolbar != nil else { return }
        configureToolbar()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneList.map(\.identifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneList.map(\.identifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneList.map(\.identifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = paneList.first(where: { $0.identifier == itemIdentifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
        item.target = self
        switch pane {
        case .general: item.action = #selector(showGeneral)
        case .setup: item.action = #selector(showSetup)
        case .modes: item.action = #selector(showModes)
        case .developer: item.action = #selector(showDeveloper)
        }
        return item
    }

    private var paneList: [Pane] {
        developerIsVisible ? [.general, .setup, .modes, .developer] : [.general, .setup, .modes]
    }

    @objc private func showGeneral() { select(.general, refresh: false) }
    @objc private func showSetup() { select(.setup, refresh: true) }
    @objc private func showModes() { select(.modes, refresh: false) }
    @objc private func showDeveloper() { select(.developer, refresh: true) }

    private func select(_ pane: Pane, refresh: Bool) {
        selectedPane = pane
        window?.toolbar?.selectedItemIdentifier = pane.identifier
        window?.title = pane.title
        let view: NSView
        switch pane {
        case .general:
            refreshGeneralControls()
            view = generalView
        case .setup: view = setupView
        case .modes: view = modesView
        case .developer: view = developerView
        }
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            view.bottomAnchor.constraint(lessThanOrEqualTo: contentHost.bottomAnchor)
        ])
        resizeWindow(toFit: view)
        if refresh { beginRefresh(userInitiated: false) }
    }

    // MARK: - General

    private func makeGeneralView() -> NSView {
        let intro = detailText("After you unlock, Caffeine Modes asks before it changes Amphetamine.")

        let unlockLabel = NSTextField(labelWithString: "Suggested action after unlock")
        unlockLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let choiceStack = NSStackView(views: [unlockOffButton, unlockWorkButton])
        choiceStack.orientation = .vertical
        choiceStack.alignment = .leading
        choiceStack.spacing = 8

        let unlockStack = NSStackView(views: [unlockLabel, choiceStack, intro])
        unlockStack.orientation = .vertical
        unlockStack.alignment = .leading
        unlockStack.spacing = 8

        let batteryRow = NSStackView(views: [
            batteryProtectionCheckbox,
            batteryProtectionPercentPopUp
        ])
        batteryRow.orientation = .horizontal
        batteryRow.alignment = .firstBaseline
        batteryRow.spacing = 8

        batteryProtectionNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        batteryProtectionNote.textColor = .secondaryLabelColor
        let batteryStack = NSStackView(views: [batteryRow, batteryProtectionNote])
        batteryStack.orientation = .vertical
        batteryStack.alignment = .leading
        batteryStack.spacing = 8

        let workLidNote = detailText(
            "Starting Work turns off Amphetamine’s closed-display mode, so the lid follows normal macOS behavior. That includes sessions you start in Amphetamine yourself."
        )

        let stack = NSStackView(views: [
            launchCheckbox,
            separator(),
            unlockStack,
            separator(),
            batteryStack,
            separator(),
            workLidNote
        ])
        return paneStack(stack, spacing: 20)
    }

    private func configureControls() {
        launchCheckbox.target = self
        launchCheckbox.action = #selector(toggleLaunchAtLogin)
        unlockOffButton.target = self
        unlockOffButton.action = #selector(selectPostUnlockOff)
        unlockWorkButton.target = self
        unlockWorkButton.action = #selector(selectPostUnlockWork)
        batteryProtectionCheckbox.target = self
        batteryProtectionCheckbox.action = #selector(toggleBatteryProtectionRequirement)
        batteryProtectionPercentPopUp.target = self
        batteryProtectionPercentPopUp.action = #selector(selectBatteryProtectionThreshold)
        for percentage in BatteryProtectionRequirement.allowedPercentages {
            batteryProtectionPercentPopUp.addItem(withTitle: "\(percentage)%")
            batteryProtectionPercentPopUp.lastItem?.tag = percentage
        }
        batteryProtectionPercentPopUp.setAccessibilityLabel("Battery level")
        batteryProtectionPercentPopUp.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        setupSpinner.style = .spinning
        setupSpinner.controlSize = .small
        setupSpinner.isDisplayedWhenStopped = false
        diagnosticSpinner.style = .spinning
        diagnosticSpinner.controlSize = .small
        diagnosticSpinner.isDisplayedWhenStopped = false
    }

    private func refreshGeneralControls() {
        launchCheckbox.state = launchManager.isEnabled ? .on : .off
        unlockOffButton.state = store.postUnlockMode == .off ? .on : .off
        unlockWorkButton.state = store.postUnlockMode == .work ? .on : .off
        let requirement = batteryProtectionRequirement.batteryProtectionRequirement
        batteryProtectionCheckbox.state = requirement.isRequired ? .on : .off
        batteryProtectionPercentPopUp.selectItem(withTag: requirement.thresholdPercent)
        batteryProtectionPercentPopUp.isEnabled = requirement.isRequired
        batteryProtectionNote.stringValue = requirement.isRequired
            ? "Night and Travel will not start until Amphetamine matches."
            : "Caffeine Modes will not check Amphetamine’s battery limit."
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try launchManager.setEnabled(launchCheckbox.state == .on)
        } catch {
            refreshGeneralControls()
            showError(error)
        }
        onWorkFinished?()
    }

    @objc private func selectPostUnlockOff() {
        store.postUnlockMode = .off
        refreshGeneralControls()
    }

    @objc private func selectPostUnlockWork() {
        store.postUnlockMode = .work
        refreshGeneralControls()
    }

    @objc private func toggleBatteryProtectionRequirement() {
        var requirement = batteryProtectionRequirement.batteryProtectionRequirement
        if batteryProtectionCheckbox.state == .off {
            let confirmed = confirmBatteryProtectionOptOut?()
                ?? presentBatteryProtectionOptOutConfirmation()
            guard confirmed else {
                refreshGeneralControls()
                return
            }
        }
        requirement.isRequired = batteryProtectionCheckbox.state == .on
        batteryProtectionRequirement.batteryProtectionRequirement = requirement
        refreshGeneralControls()
        refreshSetupAfterBatteryProtectionChange()
        onBatteryProtectionRequirementChanged?()
    }

    private func presentBatteryProtectionOptOutConfirmation() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop Requiring Battery Protection?"
        alert.informativeText = "Night and Travel can start without a matching Amphetamine battery limit. Amphetamine keeps its own settings."
        alert.addButton(withTitle: "Stop Requiring")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func selectBatteryProtectionThreshold() {
        guard let selectedItem = batteryProtectionPercentPopUp.selectedItem else { return }
        var requirement = batteryProtectionRequirement.batteryProtectionRequirement
        requirement.thresholdPercent = selectedItem.tag
        batteryProtectionRequirement.batteryProtectionRequirement = requirement
        refreshGeneralControls()
        refreshSetupAfterBatteryProtectionChange()
        onBatteryProtectionRequirementChanged?()
    }

    private func refreshSetupAfterBatteryProtectionChange() {
        completionCoordinator.beginRefresh()
        latestReport = nil
        guard reportRefreshState.request(isBusy: activity != .idle) else { return }
        beginRefresh(userInitiated: false)
    }

    // MARK: - Setup

    private func makeSetupView() -> NSView {
        let intro = secondaryText(SetupStatusPresentation.intro)
        let allModes = groupBlock(
            title: SetupStatusPresentation.coreGroupTitle,
            rows: [amphetamineRow, automationRow, triggersRow]
        )
        let awayModes = groupBlock(
            title: SetupStatusPresentation.displaySleepGroupTitle,
            rows: [screenLockRow, powerProtectRow, batteryProtectionRow]
        )

        setupSummaryLabel.textColor = .secondaryLabelColor
        checkAgainButton.controlSize = .small
        checkAgainButton.target = self
        checkAgainButton.action = #selector(checkAgainTapped)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.addView(setupSpinner, in: .leading)
        footer.addView(setupSummaryLabel, in: .leading)
        footer.addView(checkAgainButton, in: .trailing)
        footer.widthAnchor.constraint(equalToConstant: SettingsLayout.contentWidth).isActive = true

        let stack = NSStackView(views: [intro, allModes, awayModes, separator(), footer])
        let view = paneStack(stack, spacing: 16)
        allRows.forEach {
            $0.widthAnchor.constraint(equalToConstant: SettingsLayout.contentWidth).isActive = true
        }
        let presentation = latestReport.map {
            SetupStatusPresentation.make(
                report: $0,
                triggersActionFailure: triggersFailure
            )
        } ?? .checking
        apply(presentation)
        return view
    }

    @objc private func checkAgainTapped() {
        beginRefresh(userInitiated: true)
    }

    private func autoRefreshIfIdle() {
        guard activity == .idle, NSApplication.shared.modalWindow == nil else { return }
        guard ProcessInfo.processInfo.systemUptime - lastRefreshFinishedAt >= 1 else { return }
        beginRefresh(userInitiated: false)
    }

    private func beginRefresh(
        userInitiated: Bool,
        acceptedReport: AcceptedSetupReportHandler? = nil
    ) {
        guard activity == .idle else { return }
        activity = .refreshing
        completionCoordinator.beginRefresh()
        setupSpinner.startAnimation(nil)
        setupSummaryLabel.stringValue = "Checking…"
        setControlsDisabled(true)
        runner.fetchReport { [weak self] report in
            guard let self else {
                acceptedReport?(report)
                return
            }
            self.finishRefresh(
                report: report,
                announceResult: userInitiated,
                acceptedReport: acceptedReport
            )
        }
    }

    private func finishRefresh(
        report: SetupReport,
        announceResult: Bool,
        acceptedReport: AcceptedSetupReportHandler? = nil
    ) {
        activity = .idle
        if reportRefreshState.finishCurrentRefresh() {
            beginRefresh(userInitiated: false, acceptedReport: acceptedReport)
            return
        }
        latestReport = report
        lastRefreshFinishedAt = ProcessInfo.processInfo.systemUptime
        if report.triggers == .passed { triggersFailure = nil }
        let presentation = SetupStatusPresentation.make(
            report: report,
            triggersActionFailure: triggersFailure
        )
        render(presentation)
        renderDeveloperStatus(report)
        if completionCoordinator.consumeCompletionAfterRefresh() {
            onSetupCompleted?()
        }
        announceIfNeeded(presentation.summary, force: announceResult)
        onWorkFinished?()
        acceptedReport?(report)
    }

    private func render(_ presentation: SetupStatusPresentation) {
        apply(presentation)
        if selectedPane == .setup {
            resizeWindow(toFit: setupView)
        }
    }

    /// Applies the presentation without resizing the window. `makeSetupView`
    /// must use this: resizing reads the lazy `setupView`, which would re-enter
    /// its initializer and recurse.
    private func apply(_ presentation: SetupStatusPresentation) {
        completionCoordinator.update(isComplete: presentation.isComplete)
        let action = #selector(rowActionTapped(_:))
        amphetamineRow.apply(presentation.amphetamine, target: self, action: action)
        automationRow.apply(presentation.automation, target: self, action: action)
        triggersRow.apply(presentation.triggers, target: self, action: action)
        screenLockRow.apply(presentation.screenLock, target: self, action: action)
        powerProtectRow.apply(presentation.powerProtect, target: self, action: action)
        batteryProtectionRow.apply(presentation.batteryProtection, target: self, action: action)
        setupSpinner.stopAnimation(nil)
        setupSummaryLabel.stringValue = presentation.summary
        setupSummaryLabel.textColor = presentation.isComplete ? .labelColor : .secondaryLabelColor
        setControlsDisabled(false)
        rebuildKeyViewLoop()
    }

    private func setControlsDisabled(_ disabled: Bool) {
        checkAgainButton.isEnabled = !disabled
        diagnosticButton.isEnabled = !disabled
            && DeveloperDiagnosticAvailability.make(report: latestReport).isEnabled
        allRows.forEach { $0.setActionTemporarilyDisabled(disabled) }
    }

    @objc private func rowActionTapped(_ sender: NSButton) {
        guard activity == .idle,
              let row = allRows.first(where: { $0.actionButton === sender }),
              let action = row.currentAction
        else { return }
        autoRefreshTask?.cancel()
        switch action {
        case .getAmphetamine, .updateAmphetamine:
            open("https://apps.apple.com/app/amphetamine/id937984704")
        case .openAutomationSettings:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .openLockScreenSettings:
            open("x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")
        case .disableTriggers:
            confirmAndDisableTriggers()
        case .getPowerProtect:
            open("https://github.com/x74353/Amphetamine-Power-Protect")
        case .openAmphetamine:
            openAmphetamine()
        }
    }

    private func openAmphetamine() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.if.Amphetamine"
        ) else {
            open("https://apps.apple.com/app/amphetamine/id937984704")
            return
        }
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func confirmAndDisableTriggers() {
        let alert = NSAlert()
        alert.messageText = "Turn Off Amphetamine Triggers?"
        alert.informativeText = "This prevents Triggers from changing the mode you select here."
        alert.addButton(withTitle: "Turn Off Triggers")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        activity = .disablingTriggers
        triggersRow.showProgress("Turning off Triggers…")
        setControlsDisabled(true)
        runner.disableTriggers { [weak self] failure in
            guard let self else { return }
            self.triggersFailure = failure
            self.activity = .idle
            self.beginRefresh(userInitiated: true)
        }
    }

    // MARK: - Modes

    private func makeModesView() -> NSView {
        let rows = Self.modeGridRows()
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 16
        grid.rowSpacing = 12
        grid.column(at: 0).width = 72
        for index in 1...3 {
            grid.column(at: index).width = SettingsLayout.modeColumnWidth
        }
        for index in 1..<grid.numberOfRows {
            grid.row(at: index).topPadding = 4
            grid.row(at: index).bottomPadding = 4
        }

        let notes = NSStackView(views: [
            detailText("Night keeps all connected displays off. Travel does not."),
            detailText("If a display turns on while your Mac is locked, Night turns it off again. Travel does nothing."),
            detailText("Unplugging or reconnecting a display does not stop Travel or its timer."),
            detailText("When you require battery protection, Amphetamine ends Night and Travel at that battery level."),
            detailText("No mode keeps your network connected."),
            detailText("Works with displays and docks that already work normally with macOS and Amphetamine."),
            detailText("Night and Travel can make a closed Mac hot. Do not run a closed Mac inside an enclosed bag.")
        ])
        notes.orientation = .vertical
        notes.alignment = .leading
        notes.spacing = 8

        let stack = NSStackView(views: [grid, separator(), notes])
        return paneStack(stack, spacing: 20)
    }

    static func modeGridRows() -> [[NSTextField]] {
        let headers = ["Mode", "Laptop", "Open + external", "Closed + external"]
        return [
            headers.map { Self.modeGridText($0, header: true) },
            [
                Self.modeGridText("Work", header: true),
                Self.modeGridText(
                    "Mac and built-in display stay awake.",
                    mode: "Work",
                    setup: "Laptop"
                ),
                Self.modeGridText(
                    "Mac and all displays stay awake.",
                    mode: "Work",
                    setup: "Open + external"
                ),
                Self.modeGridText(
                    "External display stays awake. Normal clamshell rules apply.",
                    mode: "Work",
                    setup: "Closed + external"
                )
            ],
            [
                Self.modeGridText("Night", header: true),
                Self.modeGridText(
                    "Display turns off. Mac locks and keeps working.",
                    mode: "Night",
                    setup: "Laptop"
                ),
                Self.modeGridText(
                    "All displays turn off. Mac locks and keeps working.",
                    mode: "Night",
                    setup: "Open + external"
                ),
                Self.modeGridText(
                    "External display turns off. Mac locks and keeps working.",
                    mode: "Night",
                    setup: "Closed + external"
                )
            ],
            [
                Self.modeGridText("Travel", header: true),
                Self.modeGridText(
                    "Mac locks and keeps working until the timer ends. The display is not kept off.",
                    mode: "Travel",
                    setup: "Laptop"
                ),
                Self.modeGridText(
                    "Mac locks and keeps working until the timer ends. Displays are not kept off.",
                    mode: "Travel",
                    setup: "Open + external"
                ),
                Self.modeGridText(
                    "Mac locks and keeps working until the timer ends. The lid can stay closed.",
                    mode: "Travel",
                    setup: "Closed + external"
                )
            ]
        ]
    }

    static func modeGridText(
        _ text: String,
        mode: String? = nil,
        setup: String? = nil,
        header: Bool = false
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(
            ofSize: header ? NSFont.systemFontSize : NSFont.smallSystemFontSize,
            weight: header ? .semibold : .regular
        )
        label.textColor = header ? .labelColor : .secondaryLabelColor
        label.alignment = .left
        label.preferredMaxLayoutWidth = SettingsLayout.modeColumnWidth
        if let mode, let setup {
            label.setAccessibilityLabel("\(mode), \(setup). \(text)")
        }
        return label
    }

    // MARK: - Developer

    private func makeDeveloperView() -> NSView {
        let title = NSTextField(labelWithString: "Closed-lid diagnostic")
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let detail = detailText(
            "Verifies Amphetamine in a few seconds. A temporary one-minute session then ends automatically. Keep the lid open."
        )
        diagnosticStatus.textColor = .secondaryLabelColor
        diagnosticStatus.preferredMaxLayoutWidth = SettingsLayout.contentWidth - 160
        diagnosticButton.target = self
        diagnosticButton.action = #selector(runDiagnostic)

        let statusSymbol = NSView()
        statusSymbol.translatesAutoresizingMaskIntoConstraints = false
        diagnosticIcon.translatesAutoresizingMaskIntoConstraints = false
        diagnosticSpinner.translatesAutoresizingMaskIntoConstraints = false
        statusSymbol.addSubview(diagnosticIcon)
        statusSymbol.addSubview(diagnosticSpinner)
        NSLayoutConstraint.activate([
            statusSymbol.widthAnchor.constraint(equalToConstant: 20),
            statusSymbol.heightAnchor.constraint(equalToConstant: 20),
            diagnosticIcon.centerXAnchor.constraint(equalTo: statusSymbol.centerXAnchor),
            diagnosticIcon.centerYAnchor.constraint(equalTo: statusSymbol.centerYAnchor),
            diagnosticIcon.widthAnchor.constraint(equalToConstant: 20),
            diagnosticIcon.heightAnchor.constraint(equalToConstant: 20),
            diagnosticSpinner.centerXAnchor.constraint(equalTo: statusSymbol.centerXAnchor),
            diagnosticSpinner.centerYAnchor.constraint(equalTo: statusSymbol.centerYAnchor)
        ])

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        statusRow.addView(statusSymbol, in: .leading)
        statusRow.addView(diagnosticStatus, in: .leading)
        statusRow.addView(diagnosticButton, in: .trailing)
        statusRow.widthAnchor.constraint(equalToConstant: SettingsLayout.contentWidth).isActive = true

        let stack = NSStackView(views: [title, detail, statusRow])
        return paneStack(stack, spacing: 12)
    }

    @objc private func runDiagnostic() {
        guard activity == .idle,
              DeveloperDiagnosticAvailability.make(report: latestReport).isEnabled
        else { return }
        let alert = NSAlert()
        alert.messageText = "Run Closed-Lid Diagnostic?"
        alert.informativeText = "Amphetamine starts a temporary one-minute session. It ends automatically. Keep the lid open. If another Amphetamine session starts first, Caffeine Modes replaces it."
        alert.addButton(withTitle: "Run Diagnostic")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        activity = .runningDiagnostic
        diagnosticFailure = nil
        diagnosticIcon.image = nil
        diagnosticSpinner.startAnimation(nil)
        diagnosticStatus.stringValue = "Checking Amphetamine…"
        setControlsDisabled(true)
        runner.runClosedLidDiagnostic { [weak self] failure in
            guard let self else { return }
            self.diagnosticFailure = failure
            self.activity = .idle
            self.beginRefresh(userInitiated: true)
        }
    }

    private func renderDeveloperStatus(_ report: SetupReport) {
        diagnosticSpinner.stopAnimation(nil)
        let availability = DeveloperDiagnosticAvailability.make(report: report)
        diagnosticButton.isEnabled = activity == .idle && availability.isEnabled
        if report.developerDiagnosticPassed,
           report.developerDiagnosticIsActive {
            diagnosticStatus.stringValue = "Passed · Temporary session ends within a minute"
            diagnosticStatus.textColor = .secondaryLabelColor
            diagnosticIcon.image = NSImage(
                systemSymbolName: "hourglass",
                accessibilityDescription: "Temporary diagnostic session"
            )
        } else if let diagnosticFailure {
            diagnosticStatus.stringValue = diagnosticFailure
            diagnosticStatus.textColor = .systemOrange
            diagnosticIcon.image = NSImage(
                systemSymbolName: "exclamationmark.circle.fill",
                accessibilityDescription: "Diagnostic failed"
            )
        } else if let blockedStatus = availability.blockedStatus {
            diagnosticStatus.stringValue = blockedStatus
            diagnosticStatus.textColor = .secondaryLabelColor
            diagnosticIcon.image = nil
        } else if report.developerDiagnosticPassed {
            diagnosticStatus.stringValue = "Passed"
            diagnosticStatus.textColor = .labelColor
            diagnosticIcon.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: "Diagnostic passed"
            )
        } else {
            diagnosticStatus.stringValue = "Not run"
            diagnosticStatus.textColor = .secondaryLabelColor
            diagnosticIcon.image = nil
        }
        if selectedPane == .developer {
            resizeWindow(toFit: developerView)
        }
    }

    // MARK: - Shared layout and accessibility

    private func configureContentHost() {
        guard let contentView = window?.contentView else { return }
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentHost)
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SettingsLayout.outerInset),
            contentHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SettingsLayout.outerInset),
            contentHost.topAnchor.constraint(equalTo: contentView.topAnchor, constant: SettingsLayout.outerInset),
            contentHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -SettingsLayout.outerInset)
        ])
    }

    private func paneStack(_ stack: NSStackView, spacing: CGFloat) -> NSView {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return view
    }

    private func resizeWindow(toFit paneView: NSView) {
        guard let window else { return }
        paneView.layoutSubtreeIfNeeded()
        let paneHeight = ceil(paneView.fittingSize.height)
        let contentSize = NSSize(
            width: SettingsLayout.windowWidth,
            height: paneHeight + SettingsLayout.outerInset * 2
        )
        var targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        )
        let currentFrame = window.frame
        targetFrame.origin = NSPoint(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetFrame.height
        )
        if let screen = window.screen {
            targetFrame = window.constrainFrameRect(targetFrame, to: screen)
        }
        window.setFrame(targetFrame, display: true, animate: window.isVisible)
    }

    private func groupBlock(title: String, rows: [SetupRowView]) -> NSStackView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        header.textColor = .secondaryLabelColor
        let rowsStack = NSStackView(views: rows)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 12
        let block = NSStackView(views: [header, rowsStack])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 8
        return block
    }

    private func secondaryText(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = SettingsLayout.contentWidth
        return label
    }

    private func detailText(_ text: String) -> NSTextField {
        let label = secondaryText(text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: SettingsLayout.contentWidth).isActive = true
        return box
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func rebuildKeyViewLoop() {
        guard let window else { return }
        window.autorecalculatesKeyViewLoop = true
        switch selectedPane {
        case .general: window.initialFirstResponder = launchCheckbox
        case .setup:
            window.initialFirstResponder = allRows.compactMap {
                $0.actionButton.isHidden ? nil : $0.actionButton
            }.first ?? checkAgainButton
        case .modes: window.initialFirstResponder = nil
        case .developer: window.initialFirstResponder = diagnosticButton
        }
    }

    private func announceIfNeeded(_ summary: String, force: Bool) {
        guard force || summary != lastAnnouncedSummary, let window else { return }
        lastAnnouncedSummary = summary
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Setup: \(summary)",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}

private enum SettingsLayout {
    static let windowWidth: CGFloat = 720
    static let initialContentHeight: CGFloat = 220
    static let outerInset: CGFloat = 24
    static let iconColumnWidth: CGFloat = 28
    static let modeColumnWidth: CGFloat = 184
    static var contentWidth: CGFloat { windowWidth - outerInset * 2 }
}

@MainActor
private final class SetupRowView: NSView {
    let actionButton = NSButton(title: "", target: nil, action: nil)
    private(set) var currentAction: SetupRowAction?

    private let iconView = NSImageView()
    private let progressIndicator = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var appliedPresentation: SetupRowPresentation?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setAccessibilityElement(false)
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.setAccessibilityElement(false)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        actionButton.controlSize = .small
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(iconView)
        addSubview(progressIndicator)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(actionButton)
        setAccessibilityElement(false)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            progressIndicator.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsLayout.iconColumnWidth),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -12),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -12),
            bottomAnchor.constraint(equalTo: detailLabel.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(_ presentation: SetupRowPresentation, target: AnyObject, action: Selector) {
        appliedPresentation = presentation
        currentAction = presentation.action
        progressIndicator.stopAnimation(nil)
        iconView.isHidden = false
        iconView.image = Self.icon(for: presentation.indicator)
        iconView.contentTintColor = Self.tint(for: presentation.indicator)
        titleLabel.stringValue = presentation.title
        titleLabel.setAccessibilityLabel("\(presentation.title), \(presentation.stateDescription)")
        detailLabel.stringValue = presentation.detail
        if let rowAction = presentation.action {
            actionButton.isHidden = false
            actionButton.title = rowAction.title
            actionButton.isEnabled = presentation.actionIsEnabled
            actionButton.target = target
            actionButton.action = action
        } else {
            actionButton.isHidden = true
            actionButton.title = ""
        }
        updateDetailWrapWidth()
    }

    func showProgress(_ text: String) {
        iconView.isHidden = true
        progressIndicator.startAnimation(nil)
        detailLabel.stringValue = text
        actionButton.isHidden = true
        titleLabel.setAccessibilityLabel("\(titleLabel.stringValue), in progress")
        updateDetailWrapWidth()
    }

    func setActionTemporarilyDisabled(_ disabled: Bool) {
        if disabled {
            actionButton.isEnabled = false
        } else if let appliedPresentation {
            actionButton.isEnabled = appliedPresentation.actionIsEnabled
        }
    }

    private func updateDetailWrapWidth() {
        let reserved = actionButton.isHidden ? 0 : actionButton.fittingSize.width + 12
        detailLabel.preferredMaxLayoutWidth = max(
            160,
            SettingsLayout.contentWidth - SettingsLayout.iconColumnWidth - reserved
        )
    }

    private static func icon(for indicator: SetupRowIndicator) -> NSImage? {
        let name: String
        let description: String
        switch indicator {
        case .complete:
            name = "checkmark.circle.fill"
            description = "Complete"
        case .needsAction:
            name = "exclamationmark.circle.fill"
            description = "Needs action"
        case .notChecked:
            name = "circle.dashed"
            description = "Not checked"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
    }

    private static func tint(for indicator: SetupRowIndicator) -> NSColor {
        switch indicator {
        case .complete: .systemGreen
        case .needsAction: .systemOrange
        case .notChecked: .secondaryLabelColor
        }
    }
}

private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    override func keyDown(with event: NSEvent) {
        let commandPressed = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.command)
        if commandPressed, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }
}

private final class SettingsCheckRunner: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.andreaslar.caffeinemodes.settings-checks",
        qos: .userInitiated
    )
    private let controller: ModeControlling

    init(controller: ModeControlling) {
        self.controller = controller
    }

    func fetchReport(_ completion: @escaping @MainActor (SetupReport) -> Void) {
        queue.async {
            let report = self.controller.setupReport()
            Self.deliver { completion(report) }
        }
    }

    func disableTriggers(_ completion: @escaping @MainActor (String?) -> Void) {
        queue.async {
            let failure = Self.failureDescription { try self.controller.disableTriggers() }
            Self.deliver { completion(failure) }
        }
    }

    func runClosedLidDiagnostic(_ completion: @escaping @MainActor (String?) -> Void) {
        queue.async {
            let failure = Self.failureDescription {
                try self.controller.runClosedDisplayReadinessTest(
                    authorizingSessionReplacement: true
                )
            }
            Self.deliver { completion(failure) }
        }
    }

    private static func failureDescription(_ work: () throws -> Void) -> String? {
        do {
            try work()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func deliver(_ update: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(update)
        }
    }
}
