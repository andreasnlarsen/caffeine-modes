import AppKit
import XCTest
@testable import CaffeineModesApp

final class CustomerFacingCopyTests: XCTestCase {
    @MainActor
    func testEveryModeGridCellNamesItsModeAndSetupForVoiceOver() {
        let expectations = [
            ("Work", "Laptop", "Mac and built-in display stay awake."),
            ("Work", "Open + external", "Mac and all displays stay awake."),
            ("Work", "Closed + external", "External display stays awake. Normal clamshell rules apply."),
            ("Night", "Laptop", "Display turns off. Mac locks and keeps working."),
            ("Night", "Open + external", "All displays turn off. Mac locks and keeps working."),
            ("Night", "Closed + external", "External display turns off. Mac locks and keeps working."),
            ("Travel", "Laptop", "Mac locks and keeps working until the timer ends. The display is not kept off."),
            ("Travel", "Open + external", "Mac locks and keeps working until the timer ends. Displays are not kept off."),
            ("Travel", "Closed + external", "Mac locks and keeps working until the timer ends. The lid can stay closed.")
        ]

        let rows = SettingsWindowController.modeGridRows()
        let labels = rows.dropFirst().flatMap { Array($0.dropFirst()) }
        XCTAssertEqual(labels.count, expectations.count)

        for (label, expectation) in zip(labels, expectations) {
            let (mode, setup, detail) = expectation
            XCTAssertEqual(label.stringValue, detail)
            XCTAssertEqual(
                label.accessibilityLabel(),
                "\(mode), \(setup). \(detail)"
            )
        }
    }

    func testAboutContainsThePermanentHeatWarning() {
        XCTAssertEqual(
            MenuBarCopy.aboutInformativeText,
            "Three clear Amphetamine modes for work, night, and short travel.\n\n"
                + "Night and Travel can make a closed Mac hot. "
                + "Do not run a closed Mac inside an enclosed bag."
        )
    }
}
