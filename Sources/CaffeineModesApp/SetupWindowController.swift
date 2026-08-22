import AppKit
import CaffeineModesAppSupport
import CaffeineModesCore

@MainActor
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private enum Activity {
        case idle
        case refreshing
        case disablingTriggers
        case runningClosedLidCheck
    }

    private let runner: SetupCheckRunner
    private let amphetamineRow = SetupRowView()
    private let automationRow = SetupRowView()
    private let triggersRow = SetupRowView()
    private let screenLockRow = SetupRowView()
    private let closedLidRow = SetupRowView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let footerSpinner = NSProgressIndicator()
    private let checkAgainButton = NSButton(title: "Check Again", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let rootStack = NSStackView()

    private var activity = Activity.idle
    private var triggersFailure: String?
    private var closedLidFailure: String?
    private var lastAnnouncedSummary: String?
    private var lastRefreshFinishedAt: TimeInterval = -.greatestFiniteMagnitude
    private var autoRefreshTask: Task<Void, Never>?
    private var completionCoordinator = SetupCompletionCoordinator()
    var onSetupCompleted: (() -> Void)?
    var onWorkFinished: (() -> Void)?

    private var allRows: [SetupRowView] {
        [amphetamineRow, automationRow, triggersRow, screenLockRow, closedLidRow]
    }

    var isBusy: Bool {
        switch activity {
        case .idle: false
        case .refreshing, .disablingTriggers, .runningClosedLidCheck: true
        }
    }

    init(controller: ModeControlling) {
        self.runner = SetupCheckRunner(controller: controller)
        let window = SetupWindow(
            contentRect: NSRect(x: 0, y: 0, width: SetupLayout.windowWidth, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Caffeine Modes Setup"
        window.center()
        super.init(window: window)
        window.delegate = self
        configureContent()
        render(.checking)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
        beginRefresh(userInitiated: false)
    }

    func checkAndShowIfNeeded(completion: @escaping @MainActor (Bool) -> Void) {
        guard activity == .idle else {
            completion(false)
            return
        }
        activity = .refreshing
        completionCoordinator.beginRefresh()
        runner.fetchReport { [weak self] report in
            guard let self else {
                completion(false)
                return
            }
            let shouldShow = !report.isReady || self.window?.isVisible == true
            if shouldShow {
                self.showWindowWithoutRefresh()
            }
            self.finishRefresh(report: report, announceResult: false)
            completion(report.isReady)
        }
    }

    private func showWindowWithoutRefresh() {
        super.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.autoRefreshIfIdle()
        }
    }

    // MARK: - Layout

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Setup Status")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let intro = NSTextField(wrappingLabelWithString: SetupStatusPresentation.intro)
        intro.textColor = .secondaryLabelColor
        intro.preferredMaxLayoutWidth = SetupLayout.contentWidth

        let titleBlock = NSStackView(views: [title, intro])
        titleBlock.orientation = .vertical
        titleBlock.alignment = .leading
        titleBlock.spacing = 8

        let coreGroup = groupBlock(
            title: SetupStatusPresentation.coreGroupTitle,
            rows: [amphetamineRow, automationRow, triggersRow]
        )
        let displaySleepGroup = groupBlock(
            title: SetupStatusPresentation.displaySleepGroupTitle,
            rows: [screenLockRow, closedLidRow]
        )

        let separator = NSBox()
        separator.boxType = .separator

        footerSpinner.style = .spinning
        footerSpinner.controlSize = .small
        footerSpinner.isDisplayedWhenStopped = false
        footerSpinner.setAccessibilityElement(false)

        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail

        checkAgainButton.bezelStyle = .rounded
        checkAgainButton.controlSize = .small
        checkAgainButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        checkAgainButton.target = self
        checkAgainButton.action = #selector(checkAgainTapped)

        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(doneTapped)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.addView(footerSpinner, in: .leading)
        footer.addView(summaryLabel, in: .leading)
        footer.addView(checkAgainButton, in: .trailing)
        footer.addView(doneButton, in: .trailing)

        let footerBlock = NSStackView(views: [separator, footer])
        footerBlock.orientation = .vertical
        footerBlock.alignment = .leading
        footerBlock.spacing = 12

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 20
        rootStack.edgeInsets = NSEdgeInsets(
            top: SetupLayout.outerInset,
            left: SetupLayout.outerInset,
            bottom: SetupLayout.outerInset,
            right: SetupLayout.outerInset
        )
        rootStack.addArrangedSubview(titleBlock)
        rootStack.addArrangedSubview(coreGroup)
        rootStack.addArrangedSubview(displaySleepGroup)
        rootStack.addArrangedSubview(footerBlock)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        var constraints: [NSLayoutConstraint] = [
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            rootStack.widthAnchor.constraint(equalToConstant: SetupLayout.windowWidth),
            separator.widthAnchor.constraint(equalToConstant: SetupLayout.contentWidth),
            footer.widthAnchor.constraint(equalToConstant: SetupLayout.contentWidth)
        ]
        constraints += allRows.map {
            $0.widthAnchor.constraint(equalToConstant: SetupLayout.contentWidth)
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func groupBlock(title: String, rows: [SetupRowView]) -> NSStackView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor

        let rowsStack = NSStackView(views: rows)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 14

        let block = NSStackView(views: [header, rowsStack])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 8
        return block
    }

    private func sizeWindowToFit() {
        guard let window, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: SetupLayout.windowWidth,
            height: rootStack.fittingSize.height
        )
        let frameSize = window.frameRect(forContentRect: contentRect).size
        var frame = window.frame
        frame.origin.y += frame.height - frameSize.height
        frame.size = frameSize
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    // MARK: - Checks

    @objc private func checkAgainTapped() {
        beginRefresh(userInitiated: true)
    }

    @objc private func doneTapped() {
        window?.performClose(nil)
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

    private func autoRefreshIfIdle() {
        guard activity == .idle else { return }
        // A confirmation alert runs the main run loop; refreshing under it
        // would clobber the activity state the alert is about to commit.
        guard NSApplication.shared.modalWindow == nil else { return }
        guard ProcessInfo.processInfo.systemUptime - lastRefreshFinishedAt >= 1 else { return }
        beginRefresh(userInitiated: false)
    }

    private func beginRefresh(userInitiated: Bool) {
        guard activity == .idle else { return }
        activity = .refreshing
        completionCoordinator.beginRefresh()
        footerSpinner.startAnimation(nil)
        summaryLabel.stringValue = "Checking…"
        disableControlsWhileBusy()
        runner.fetchReport { [weak self] report in
            self?.finishRefresh(report: report, announceResult: userInitiated)
        }
    }

    private func finishRefresh(report: SetupReport, announceResult: Bool) {
        activity = .idle
        lastRefreshFinishedAt = ProcessInfo.processInfo.systemUptime
        if report.triggers == .passed { triggersFailure = nil }
        if report.closedDisplayReady { closedLidFailure = nil }
        let presentation = SetupStatusPresentation.make(
            report: report,
            triggersActionFailure: triggersFailure,
            closedLidActionFailure: closedLidFailure
        )
        render(presentation)
        if completionCoordinator.consumeCompletionAfterRefresh() {
            onSetupCompleted?()
        }
        announceIfNeeded(presentation.summary, force: announceResult)
        onWorkFinished?()
    }

    private func render(_ presentation: SetupStatusPresentation) {
        completionCoordinator.update(isComplete: presentation.isComplete)
        let action = #selector(rowActionTapped(_:))
        amphetamineRow.apply(presentation.amphetamine, target: self, action: action)
        automationRow.apply(presentation.automation, target: self, action: action)
        triggersRow.apply(presentation.triggers, target: self, action: action)
        screenLockRow.apply(presentation.screenLock, target: self, action: action)
        closedLidRow.apply(presentation.closedLid, target: self, action: action)

        footerSpinner.stopAnimation(nil)
        summaryLabel.stringValue = presentation.summary
        summaryLabel.textColor = presentation.isComplete ? .labelColor : .secondaryLabelColor
        checkAgainButton.isEnabled = true
        doneButton.isHidden = !presentation.isComplete
        doneButton.isEnabled = true

        rebuildKeyViewLoop()
        sizeWindowToFit()
    }

    private func disableControlsWhileBusy() {
        checkAgainButton.isEnabled = false
        doneButton.isEnabled = false
        for row in allRows {
            row.setActionTemporarilyDisabled(true)
        }
    }

    // MARK: - Row actions

    @objc private func rowActionTapped(_ sender: NSButton) {
        guard activity == .idle else { return }
        autoRefreshTask?.cancel()
        guard let row = allRows.first(where: { $0.actionButton === sender }),
              let rowAction = row.currentAction
        else { return }
        switch rowAction {
        case .getAmphetamine, .updateAmphetamine:
            open("https://apps.apple.com/app/amphetamine/id937984704")
        case .openAutomationSettings:
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .openLockScreenSettings:
            open("x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")
        case .disableTriggers:
            confirmAndDisableTriggers()
        case .runClosedLidCheck:
            confirmAndRunClosedLidCheck()
        }
    }

    private func confirmAndDisableTriggers() {
        let alert = NSAlert()
        alert.messageText = "Disable Amphetamine Triggers?"
        alert.informativeText = "Triggers let Amphetamine start sessions on its own. Caffeine Modes needs to be the only session owner. This changes only Amphetamine’s Triggers setting."
        alert.addButton(withTitle: "Disable Triggers")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        activity = .disablingTriggers
        triggersRow.showProgress("Turning Amphetamine Triggers off…")
        disableControlsWhileBusy()
        runner.disableTriggers { [weak self] failure in
            guard let self else { return }
            self.triggersFailure = failure
            self.activity = .idle
            self.beginRefresh(userInitiated: true)
        }
    }

    private func confirmAndRunClosedLidCheck() {
        let alert = NSAlert()
        alert.messageText = "Run the Closed-Lid Setup Check?"
        alert.informativeText = "This starts a one-minute Amphetamine session and verifies closed-display mode. You do not need to close the lid, and the session ends on its own after one minute.\n\nIf another Amphetamine session appears before the check starts, the check replaces it. Amphetamine may show its own Power Protect setup."
        alert.addButton(withTitle: "Run Check")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        activity = .runningClosedLidCheck
        closedLidRow.showProgress("Running the closed-lid setup check… Amphetamine may show its own Power Protect steps.")
        disableControlsWhileBusy()
        runner.runClosedLidCheck { [weak self] failure in
            guard let self else { return }
            self.closedLidFailure = failure
            self.activity = .idle
            self.beginRefresh(userInitiated: true)
        }
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Keyboard and VoiceOver

    private func rebuildKeyViewLoop() {
        guard let window else { return }
        window.autorecalculatesKeyViewLoop = false
        var chain: [NSView] = allRows.compactMap {
            $0.actionButton.isHidden ? nil : $0.actionButton
        }
        chain.append(checkAgainButton)
        if !doneButton.isHidden {
            chain.append(doneButton)
        }
        for (index, view) in chain.enumerated() {
            view.nextKeyView = chain[(index + 1) % chain.count]
        }
        window.initialFirstResponder = chain.first
    }

    private func announceIfNeeded(_ summary: String, force: Bool) {
        guard force || summary != lastAnnouncedSummary else { return }
        lastAnnouncedSummary = summary
        guard let window else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Setup status: \(summary)",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}

private enum SetupLayout {
    static let windowWidth: CGFloat = 520
    static let outerInset: CGFloat = 24
    static let iconColumnWidth: CGFloat = 28
    static var contentWidth: CGFloat { windowWidth - outerInset * 2 }
}

/// One self-contained setup check: state symbol, title, per-row detail,
/// and at most one trailing action.
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

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Subview order defines the VoiceOver order: title, detail, action.
        addSubview(iconView)
        addSubview(progressIndicator)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(actionButton)
        setAccessibilityElement(false)

        let buttonOnTitleLine = actionButton.centerYAnchor.constraint(
            equalTo: titleLabel.centerYAnchor
        )
        buttonOnTitleLine.priority = .defaultHigh
        let bottomHugsDetail = bottomAnchor.constraint(equalTo: detailLabel.bottomAnchor)
        bottomHugsDetail.priority = .defaultLow
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            progressIndicator.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: SetupLayout.iconColumnWidth
            ),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: actionButton.leadingAnchor,
                constant: -12
            ),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            buttonOnTitleLine,
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: detailLabel.bottomAnchor),
            bottomAnchor.constraint(greaterThanOrEqualTo: actionButton.bottomAnchor),
            bottomHugsDetail
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
            100,
            SetupLayout.contentWidth - SetupLayout.iconColumnWidth - reserved
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
            description = "Not checked yet"
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

/// The menu-bar app has no Window menu, so the setup window handles
/// Escape and Command-W itself.
private final class SetupWindow: NSWindow {
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
        if event.keyCode == 53 {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }
}

/// Runs controller orchestration on one serial worker queue. The narrow
/// NSAppleScript boundary marshals to the main thread because Apple requires
/// it; other bounded setup work stays off the main thread. ModeController
/// serializes public entry points so setup and menu work cannot race.
private final class SetupCheckRunner: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.andreaslar.caffeinemodes.setup-checks",
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

    func runClosedLidCheck(_ completion: @escaping @MainActor (String?) -> Void) {
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
