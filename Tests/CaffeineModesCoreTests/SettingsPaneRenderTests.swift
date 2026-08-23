import AppKit
import CaffeineModesCore
import XCTest
@testable import CaffeineModesApp

/// Renders the real Settings window and writes one PNG per pane state, then
/// asserts the sizing contract: a stable 720-point width, a height that fits
/// the selected pane, and a fixed top edge across pane changes.
///
/// Rendering needs a window server, so the whole class is skipped unless
/// `RENDER_SETTINGS_PANES=1` is set. Output goes to `RENDER_SETTINGS_DIR`
/// (default: the system temporary directory). Captures ask the WindowServer
/// for the composited window image because offscreen `cacheDisplay` cannot
/// rasterize the glass toolbar-selection capsule: it falls back to an opaque
/// white block that fakes a broken toolbar. Ordering a window in is what makes
/// the WindowServer composite it, and macOS relocates fully-offscreen windows
/// onto a screen at that moment, so the window is kept ordered in for the
/// whole test at a level below the desktop wallpaper, excluded from Mission
/// Control, with the process at the `.prohibited` activation policy: runs
/// stay invisible and never take focus.
final class SettingsPaneRenderTests: XCTestCase {
    private let readyReport = SetupReport(
        amphetamineInstalled: true,
        supportedVersion: true,
        detectedVersion: "5.3.2",
        automation: .passed,
        triggers: .passed,
        screenLock: .passed,
        powerProtect: PowerProtectStatus(isRequired: true, isInstalled: true),
        developerDiagnosticPassed: false,
        amphetamineSessionIsActive: false
    )

    private let needsActionReport = SetupReport(
        amphetamineInstalled: true,
        supportedVersion: false,
        detectedVersion: "5.2.1",
        automation: .needsAction,
        triggers: .needsAction,
        screenLock: .needsAction,
        powerProtect: PowerProtectStatus(isRequired: true, isInstalled: false),
        developerDiagnosticPassed: false
    )

    @MainActor
    func testGeneralSetupAndModesPanesFitTheirContent() throws {
        let windowController = try makeWindowController(report: readyReport)
        let generalSize = try contentSize(of: windowController)
        let topEdge = try windowTopEdge(of: windowController)
        try snapshot(windowController, name: "general")
        XCTAssertEqual(windowController.window?.title, "General")

        try selectPane(windowController, .setup)
        waitUntilIdle(windowController)
        let setupSize = try contentSize(of: windowController)
        try snapshot(windowController, name: "setup-ready")
        XCTAssertEqual(windowController.window?.title, "Setup")

        try selectPane(windowController, .modes)
        let modesSize = try contentSize(of: windowController)
        try snapshot(windowController, name: "modes")
        XCTAssertEqual(windowController.window?.title, "Modes")

        for size in [generalSize, setupSize, modesSize] {
            XCTAssertEqual(size.width, 720, accuracy: 0.5)
            XCTAssertLessThan(size.height, 620, "Panes must stay compact")
        }
        XCTAssertLessThan(generalSize.height, 300, "General must not reserve an empty canvas")
        XCTAssertGreaterThan(setupSize.height, generalSize.height + 40, "Heights must follow content")
        try XCTAssertEqual(windowTopEdge(of: windowController), topEdge, accuracy: 0.5)
    }

    @MainActor
    func testSetupPaneWithAllActionsPendingStaysCompact() throws {
        let windowController = try makeWindowController(report: needsActionReport)
        let topEdge = try windowTopEdge(of: windowController)
        try selectPane(windowController, .setup)
        waitUntilIdle(windowController)
        let setupSize = try contentSize(of: windowController)
        try snapshot(windowController, name: "setup-needs-action")
        XCTAssertLessThan(setupSize.height, 620, "Setup with five pending actions must stay compact")
        try XCTAssertEqual(windowTopEdge(of: windowController), topEdge, accuracy: 0.5)
    }

    @MainActor
    func testSetupPaneCheckingState() throws {
        let windowController = try makeWindowController(report: readyReport, reportDelay: 1.2)
        try selectPane(windowController, .setup)
        pumpRunLoop(seconds: 0.3)
        XCTAssertTrue(windowController.isBusy, "Expected to capture the in-flight checking state")
        try snapshot(windowController, name: "setup-checking")
        waitUntilIdle(windowController)
    }

    @MainActor
    func testDeveloperPaneStaysCompact() throws {
        let windowController = try makeWindowController(report: readyReport)
        windowController.show(pane: .developer, includeDeveloper: true)
        waitUntilIdle(windowController)
        let developerSize = try contentSize(of: windowController)
        try snapshot(windowController, name: "developer")
        XCTAssertEqual(windowController.window?.title, "Developer")
        XCTAssertLessThan(developerSize.height, 300, "Developer must stay compact")
    }

    @MainActor
    func testSelectedToolbarItemSurvivesAppearanceSwitch() throws {
        let windowController = try makeWindowController(report: readyReport)
        let lightToolbar = try XCTUnwrap(windowController.window?.toolbar)

        applyAppAppearance(named: .darkAqua)
        pumpRunLoop(seconds: 0.1)
        let darkToolbar = try XCTUnwrap(windowController.window?.toolbar)
        XCTAssertTrue(
            darkToolbar !== lightToolbar,
            "Toolbar must rebuild on appearance change so the selection capsule re-resolves"
        )
        XCTAssertEqual(darkToolbar.selectedItemIdentifier?.rawValue, "general")
        try applyWindowAppearance(named: .darkAqua, to: windowController)
        let darkCapture = try snapshot(windowController, name: "general-dark-after-switch")
        try XCTAssertLessThan(
            backgroundBrightness(ofPNG: darkCapture), 0.4,
            "Dark capture must contain real dark pixels"
        )
        try XCTAssertLessThan(
            selectedCapsuleBrightness(in: windowController, capture: darkCapture), 0.6,
            "Selected capsule must stay legible after a light-to-dark switch"
        )
        windowController.window?.appearance = nil

        applyAppAppearance(named: .aqua)
        pumpRunLoop(seconds: 0.1)
        let restoredToolbar = try XCTUnwrap(windowController.window?.toolbar)
        XCTAssertTrue(restoredToolbar !== darkToolbar, "Dark-to-light must rebuild as well")
        XCTAssertEqual(restoredToolbar.selectedItemIdentifier?.rawValue, "general")
        let lightCapture = try snapshot(windowController, name: "general-light-after-switch")
        try XCTAssertGreaterThan(
            backgroundBrightness(ofPNG: lightCapture), 0.6,
            "Light capture must contain real light pixels"
        )
        XCTAssertNotEqual(darkCapture, lightCapture, "Dark and light captures must differ")
    }

    @MainActor
    func testGeneralRefreshesLaunchAtLoginWhenWindowBecomesKey() throws {
        let launchManager = RenderStubLaunchManager()
        let windowController = try makeWindowController(
            report: readyReport,
            launchManager: launchManager
        )
        let checkbox = try XCTUnwrap(
            findLaunchAtLoginCheckbox(in: windowController),
            "General must contain the Launch at Login checkbox"
        )
        XCTAssertEqual(checkbox.state, .off)

        launchManager.isEnabled = true
        windowController.windowDidBecomeKey(
            Notification(name: NSWindow.didBecomeKeyNotification)
        )
        XCTAssertEqual(
            checkbox.state, .on,
            "General must reread Launch at Login when the window becomes key"
        )
    }

    /// Captures Setup and Modes in dark and proves the dark pixels are real:
    /// the window resolves dark before capture, the background rasterizes
    /// dark, and each dark capture differs byte-for-byte from a light capture
    /// of the same pane in the same window. Dark is applied to the window
    /// directly so the capture does not depend on when the window adopts the
    /// app-level appearance; the app-level path is covered by
    /// `testSelectedToolbarItemSurvivesAppearanceSwitch`.
    @MainActor
    func testDarkAppearanceUsesSemanticColors() throws {
        let windowController = try makeWindowController(report: needsActionReport)
        try selectPane(windowController, .setup)
        waitUntilIdle(windowController)
        let lightSetup = try captureWindowImage(windowController)
        try selectPane(windowController, .modes)
        let lightModes = try captureWindowImage(windowController)
        try XCTAssertGreaterThan(backgroundBrightness(ofPNG: lightSetup), 0.6)
        try XCTAssertGreaterThan(backgroundBrightness(ofPNG: lightModes), 0.6)

        try applyWindowAppearance(named: .darkAqua, to: windowController)
        try selectPane(windowController, .setup)
        waitUntilIdle(windowController)
        let darkSetup = try snapshot(windowController, name: "setup-needs-action-dark")
        try selectPane(windowController, .modes)
        let darkModes = try snapshot(windowController, name: "modes-dark")

        try XCTAssertLessThan(
            backgroundBrightness(ofPNG: darkSetup), 0.4,
            "Setup dark capture must contain real dark pixels"
        )
        try XCTAssertLessThan(
            backgroundBrightness(ofPNG: darkModes), 0.4,
            "Modes dark capture must contain real dark pixels"
        )
        XCTAssertNotEqual(darkSetup, lightSetup, "Setup dark PNG must differ from light")
        XCTAssertNotEqual(darkModes, lightModes, "Modes dark PNG must differ from light")
    }

    /// Proves the selected toolbar item stays legible in dark: the glass
    /// selection capsule must rasterize as dark glass, not as the opaque white
    /// block that `cacheDisplay` used to fake. The capsule is probed inside
    /// its left edge, away from the symbol and the label.
    @MainActor
    func testToolbarBuiltUnderDarkAppearance() throws {
        applyAppAppearance(named: .darkAqua)
        let windowController = try makeWindowController(report: readyReport)
        pumpRunLoop(seconds: 0.1)
        try applyWindowAppearance(named: .darkAqua, to: windowController)
        let capture = try snapshot(windowController, name: "general-built-dark")
        try XCTAssertLessThan(
            backgroundBrightness(ofPNG: capture), 0.4,
            "Built-under-dark capture must contain real dark pixels"
        )
        try XCTAssertLessThan(
            selectedCapsuleBrightness(in: windowController, capture: capture), 0.6,
            "Selected capsule must render as dark glass, not a white fallback"
        )
    }

    /// Simulates a system light/dark change the way it reaches this window in
    /// the real app: through the application appearance, not a per-window
    /// override. Restores the app to following the system after the test.
    @MainActor
    private func applyAppAppearance(named name: NSAppearance.Name) {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: name)
        addTeardownBlock { @MainActor in
            NSApp.appearance = nil
        }
    }

    // MARK: - Harness

    @MainActor
    private func makeWindowController(
        report: SetupReport,
        reportDelay: TimeInterval = 0,
        launchManager: RenderStubLaunchManager = RenderStubLaunchManager()
    ) throws -> SettingsWindowController {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RENDER_SETTINGS_PANES"] == "1",
            "Set RENDER_SETTINGS_PANES=1 to render settings pane evidence"
        )
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let windowController = SettingsWindowController(
            controller: RenderStubModeController(report: report, reportDelay: reportDelay),
            store: MemoryStore(),
            launchManager: launchManager
        )
        let window = try XCTUnwrap(windowController.window)
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.stationary, .ignoresCycle]
        window.orderFrontRegardless()
        addTeardownBlock { @MainActor in
            window.orderOut(nil)
        }
        pumpRunLoop(seconds: 0.1)
        return windowController
    }

    @MainActor
    private func findLaunchAtLoginCheckbox(
        in windowController: SettingsWindowController
    ) -> NSButton? {
        guard let contentView = windowController.window?.contentView else { return nil }
        var queue: [NSView] = [contentView]
        while let view = queue.popLast() {
            if let button = view as? NSButton, button.title == "Launch at Login" {
                return button
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    @MainActor
    private func selectPane(
        _ windowController: SettingsWindowController,
        _ pane: SettingsWindowController.Pane
    ) throws {
        let toolbar = try XCTUnwrap(windowController.window?.toolbar)
        let item = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier == pane.identifier })
        let action = try XCTUnwrap(item.action)
        NSApp.sendAction(action, to: item.target, from: item)
    }

    @MainActor
    private func waitUntilIdle(_ windowController: SettingsWindowController, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while windowController.isBusy, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(windowController.isBusy, "Setup refresh did not finish in time")
        pumpRunLoop(seconds: 0.1)
    }

    @MainActor
    private func pumpRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    @MainActor
    private func contentSize(of windowController: SettingsWindowController) throws -> NSSize {
        let window = try XCTUnwrap(windowController.window)
        return window.contentRect(forFrameRect: window.frame).size
    }

    @MainActor
    private func windowTopEdge(of windowController: SettingsWindowController) throws -> CGFloat {
        try XCTUnwrap(windowController.window).frame.maxY
    }

    @MainActor
    @discardableResult
    private func snapshot(_ windowController: SettingsWindowController, name: String) throws -> Data {
        let png = try captureWindowImage(windowController)
        let directory = outputDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        return png
    }

    /// Captures the composited window image from the WindowServer. This is the
    /// only path that rasterizes the glass selection capsule truthfully;
    /// `cacheDisplay` renders it as an opaque white block. The window is
    /// already ordered in below the desktop wallpaper, and capturing a window
    /// this process owns needs no Screen Recording permission.
    @MainActor
    private func captureWindowImage(_ windowController: SettingsWindowController) throws -> Data {
        let window = try XCTUnwrap(windowController.window)
        XCTAssertTrue(window.isVisible, "The window must stay ordered in for capture")
        window.layoutIfNeeded()
        pumpRunLoop(seconds: 0.1)
        let image = try XCTUnwrap(
            CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .bestResolution]
            ),
            "WindowServer refused the window capture; is a window server session available?"
        )
        let representation = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }

    /// Applies a temporary appearance directly to the test window so
    /// `cacheDisplay` rasterizes real pixels for it: a never-displayed window
    /// does not lazily adopt the app-level appearance before drawing. The
    /// override is restored in teardown, and the method asserts the window
    /// actually resolved the appearance before any capture relies on it.
    @MainActor
    private func applyWindowAppearance(
        named name: NSAppearance.Name,
        to windowController: SettingsWindowController
    ) throws {
        let window = try XCTUnwrap(windowController.window)
        window.appearance = NSAppearance(named: name)
        addTeardownBlock { @MainActor in
            window.appearance = nil
        }
        pumpRunLoop(seconds: 0.05)
        XCTAssertEqual(
            window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
            name,
            "Window must resolve the applied appearance before capture"
        )
    }

    /// Samples the selected toolbar item's glass capsule in a capture and
    /// returns its brightness. The selected item viewer is the only one whose
    /// glass selection view is visible; the probe sits just inside the
    /// capsule's left edge, above the label row and left of the symbol, so it
    /// reads pure capsule pixels.
    @MainActor
    private func selectedCapsuleBrightness(
        in windowController: SettingsWindowController,
        capture: Data
    ) throws -> CGFloat {
        let window = try XCTUnwrap(windowController.window)
        let frameView = try XCTUnwrap(window.contentView?.superview)
        var queue: [NSView] = [frameView]
        var selectedViewer: NSView?
        while let view = queue.popLast() {
            let isSelectionCapsuleViewer = String(describing: type(of: view))
                .contains("NSToolbarItemViewer")
                && view.subviews.contains {
                    String(describing: type(of: $0)).contains("Glass") && !$0.isHidden
                }
            if isSelectionCapsuleViewer {
                selectedViewer = view
                break
            }
            queue.append(contentsOf: view.subviews)
        }
        let viewer = try XCTUnwrap(selectedViewer, "No selected toolbar capsule found")
        let probe = viewer.convert(
            NSPoint(x: 8, y: viewer.bounds.height - 20),
            to: frameView
        )
        let representation = try XCTUnwrap(NSBitmapImageRep(data: capture))
        let scale = CGFloat(representation.pixelsWide) / frameView.bounds.width
        let color = try XCTUnwrap(
            representation.colorAt(
                x: Int(probe.x * scale),
                y: Int((frameView.bounds.height - probe.y) * scale)
            )
        )
        let rgb = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
        return rgb.brightnessComponent
    }

    /// Samples the pane background at bottom-center, safely inside the outer
    /// inset and away from the rounded corners, and returns its brightness.
    private func backgroundBrightness(ofPNG data: Data) throws -> CGFloat {
        let representation = try XCTUnwrap(NSBitmapImageRep(data: data))
        let color = try XCTUnwrap(
            representation.colorAt(
                x: representation.pixelsWide / 2,
                y: representation.pixelsHigh - 10
            )
        )
        let rgb = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
        return rgb.brightnessComponent
    }

    private func outputDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["RENDER_SETTINGS_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("caffeine-modes-settings-panes", isDirectory: true)
    }
}

private final class RenderStubModeController: ModeControlling {
    private let report: SetupReport
    private let reportDelay: TimeInterval

    init(report: SetupReport, reportDelay: TimeInterval) {
        self.report = report
        self.reportDelay = reportDelay
    }

    func setupReport() -> SetupReport {
        if reportDelay > 0 {
            Thread.sleep(forTimeInterval: reportDelay)
        }
        return report
    }

    func disableTriggers() throws {}
    func runClosedDisplayReadinessTest(authorizingSessionReplacement: Bool) throws {}

    func reconcile() -> ModeSnapshot { fatalError("not used while rendering") }
    func transition(to mode: OperatingMode, replacingActiveSession: Bool) throws -> ModeSnapshot {
        fatalError("not used while rendering")
    }
    func handleScreenUnlocked(expectedOwnershipID: UUID?) throws -> ModeSnapshot {
        fatalError("not used while rendering")
    }
    func resleepAwayModeIfLocked(expectedOwnershipID: UUID?) throws -> ModeSnapshot {
        fatalError("not used while rendering")
    }
    func hasActiveSessionForQuit() throws -> Bool { fatalError("not used while rendering") }
    func endActiveSessionForQuit() throws { fatalError("not used while rendering") }
}

private final class RenderStubLaunchManager: LaunchAtLoginManaging {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}
