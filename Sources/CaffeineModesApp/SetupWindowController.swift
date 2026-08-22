import AppKit
import CaffeineModesCore

@MainActor
final class SetupWindowController: NSWindowController {
    private let controller: ModeControlling
    private let statusStack = NSStackView()
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let disableTriggersButton = NSButton(title: "Disable Triggers", target: nil, action: nil)
    private let readinessButton = NSButton(title: "Run Closed-Display Test", target: nil, action: nil)

    init(controller: ModeControlling) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Caffeine Modes Setup"
        window.center()
        super.init(window: window)
        configureContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Setup Status")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: "Complete each check before you use Night or Travel. Caffeine Modes does not need Accessibility access.")
        intro.textColor = .secondaryLabelColor

        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 8

        disableTriggersButton.target = self
        disableTriggersButton.action = #selector(disableTriggers)
        readinessButton.target = self
        readinessButton.action = #selector(runReadinessTest)

        let appStore = linkButton(title: "Get Amphetamine", action: #selector(openAmphetamine))
        let automation = linkButton(title: "Open Automation Settings", action: #selector(openAutomationSettings))
        let lock = linkButton(title: "Open Lock Screen Settings", action: #selector(openLockSettings))
        let refresh = NSButton(title: "Check Again", target: self, action: #selector(refreshAction))
        refresh.keyEquivalent = "\r"

        let actions = NSStackView(views: [appStore, automation, lock, disableTriggersButton, readinessButton])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.distribution = .fillProportionally

        detailLabel.textColor = .secondaryLabelColor
        let root = NSStackView(views: [title, intro, statusStack, detailLabel, actions, refresh])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            intro.widthAnchor.constraint(equalToConstant: 472),
            detailLabel.widthAnchor.constraint(equalToConstant: 472)
        ])
    }

    @objc private func refreshAction() { refresh() }

    private func refresh() {
        let report = controller.setupReport()
        statusStack.arrangedSubviews.forEach {
            statusStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        statusStack.addArrangedSubview(status("Amphetamine 5.3.2 or later", passed: report.amphetamineInstalled && report.supportedVersion, detail: report.detectedVersion))
        statusStack.addArrangedSubview(status("Automation access", passed: report.automationAuthorized))
        statusStack.addArrangedSubview(status("Amphetamine Triggers are disabled", passed: report.triggersDisabled))
        statusStack.addArrangedSubview(status("Screen locks immediately", passed: report.immediateScreenLock))
        statusStack.addArrangedSubview(status("Closed-display readiness test", passed: report.closedDisplayReady))
        detailLabel.stringValue = report.isReady ? "Ready. You can use all three modes." : (report.detail ?? "Complete the checks above.")
        disableTriggersButton.isEnabled = report.automationAuthorized && !report.triggersDisabled
        readinessButton.isEnabled = report.automationAuthorized && report.triggersDisabled && !report.closedDisplayReady
    }

    private func status(_ title: String, passed: Bool, detail: String? = nil) -> NSTextField {
        let symbol = passed ? "checkmark.circle.fill" : "exclamationmark.circle"
        let attachment = NSTextAttachment()
        attachment.image = NSImage(systemSymbolName: symbol, accessibilityDescription: passed ? "Passed" : "Needs attention")
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: "  \(title)\(detail.map { " — \($0)" } ?? "")"))
        let label = NSTextField(labelWithAttributedString: text)
        label.setAccessibilityLabel("\(title): \(passed ? "Passed" : "Needs attention")")
        return label
    }

    private func linkButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        return button
    }

    @objc private func disableTriggers() {
        let alert = NSAlert()
        alert.messageText = "Disable Amphetamine Triggers?"
        alert.informativeText = "Caffeine Modes needs one owner for mode changes. This action changes only Amphetamine’s Triggers setting."
        alert.addButton(withTitle: "Disable Triggers")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform { try controller.disableTriggers() }
    }

    @objc private func runReadinessTest() {
        let alert = NSAlert()
        alert.messageText = "Run the Closed-Display Test?"
        alert.informativeText = "This starts a one-minute Amphetamine test session. It can replace another session that appears before the command finishes. Amphetamine may show its own Power Protect setup. The session expires automatically."
        alert.addButton(withTitle: "Run Test")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform {
            try controller.runClosedDisplayReadinessTest(
                authorizingSessionReplacement: true
            )
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }

    @objc private func openAmphetamine() {
        open("https://apps.apple.com/app/amphetamine/id937984704")
    }

    @objc private func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    @objc private func openLockSettings() {
        open("x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
