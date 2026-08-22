# Caffeine Modes Native Design System

## Product principles

- Show the current state before available actions.
- Use standard macOS controls and behavior.
- Keep one clear selection per mode group.
- Put warnings only where a decision has a real risk.
- Keep setup separate from daily menu use.

## Typography

- Use San Francisco through `NSFont.systemFont`.
- Setup title: 22 pt semibold.
- Setup group headers: 11 pt semibold with `secondaryLabelColor`.
- Setup row titles: 13 pt medium.
- Setup row details: 11 pt with `secondaryLabelColor`.
- Body and controls: system control size.
- Do not use custom fonts or text embedded in icons.

## Color

- Use `labelColor`, `secondaryLabelColor`, `windowBackgroundColor`, and other semantic AppKit colors.
- The running menu-bar symbols are template images. macOS controls their color.
- Setup check symbols use semantic tints: `systemGreen` for complete, `systemOrange` for needs action, and `secondaryLabelColor` for not checked. Each state also uses a distinct symbol shape and a VoiceOver state description, so state never depends on color alone.
- Errors use native `NSAlert` treatment.
- The Finder icon may use an original navy, cream, amber, blue, and mint palette. These colors do not enter the menu UI.

## Spacing and size

- Base grid: 4 points.
- Setup window outer inset: 24 points.
- Main vertical gap: 20 points between setup sections.
- Setup rows: 14 points between rows, 8 points between a group header and its rows.
- Setup window: 520 points wide; height fits the rendered content. Button widths never resize the window.
- Menu items, alerts, buttons, and hit targets use native AppKit sizing.

## Menu structure

1. Disabled status line.
2. Off.
3. Work.
4. Night.
5. Travel submenu with 30, 60, 90, and 120 minutes.
6. Setup Status…
7. Launch at Login.
8. About Caffeine Modes.
9. Quit Caffeine Modes.

The selected mode uses one standard checkmark. Travel time appears in the disabled status line and tooltip. The countdown rounds up to a whole minute and uses hours plus minutes at 60 minutes or more. The menu-bar item does not use permanent text.

### Power status language

- Off with no external blocker: `Off · Display and automatic sleep follow macOS settings`.
- Display blocker: `Display kept on by [process]`.
- Idle system blocker: `Automatic sleep blocked by [process]`.
- Do not use `Mac held awake`. That phrase hides which sleep behavior changed.
- A disk-idle blocker appears only in the tooltip. It never implies that display or system sleep is blocked.
- The tooltip lists display sleep, automatic system sleep, disk idle sleep, and lid behavior as separate lines.
- Temporary macOS service assertions do not appear in the Off summary. A macOS display assertion still appears because it can block Night or Travel.
- Work: `Work · Display stays on · Normal lid behavior`.
- Night: `Night · Display sleeps · Runs with lid closed`.
- Travel: show the countdown, display policy, and closed-lid policy.
- If a display blocker appears after Night or Travel starts, replace the normal symbol with the warning symbol and name the process.

## Symbols

| State | SF Symbol | VoiceOver description intent |
|---|---|---|
| Off | `cup.and.saucer` | Caffeine Modes is Off |
| Work | `cup.and.saucer.fill` | Work keeps Mac and displays awake |
| Night | `moon.fill` | Night keeps the Mac awake with the display asleep |
| Travel | `car.fill` | Travel is active with time remaining |
| Custom or error | `exclamationmark.triangle.fill` | Setup, conflict, or backend needs attention |
| Setup complete | `checkmark.circle.fill` | Check is complete |
| Setup needs action | `exclamationmark.circle.fill` | Check needs the user's action |
| Setup not checked | `circle.dashed` | Check has not run or cannot run yet |

Every symbol uses an accessibility description. No SF Symbol appears in the Finder icon or DMG artwork.

## Setup window

- The app stays Dockless through `LSUIElement` and `.accessory` activation policy.
- Opening Setup Status may activate the setup window for keyboard input.
- The intro states which checks Work needs and which additional checks Night and Travel need.
- Checks appear as five self-contained rows in two groups: "Needed for Work, Night, and Travel" and "Needed for Night and Travel".
- Each row shows a 16-point state symbol, a title, a per-row detail line, and at most one trailing action. Rows that pass show no action. A row that cannot run yet names its precondition instead of opening a confirmation.
- Every check uses one of three honest states: complete, needs action, or not checked. A check that has never run uses the not-checked symbol, never a warning.
- Long checks and the closed-lid setup orchestration run on a serial worker queue. The bounded AppleScript boundary uses the main thread because macOS requires it. The row or footer shows a small spinner with progress text, and conflicting controls are disabled while work runs.
- Menu status and mode orchestration also run on a serial worker queue, with only the bounded AppleScript boundary on the main thread. The menu disables conflicting mode and Quit actions while a change is active.
- The footer shows the progress summary on the leading side, a small secondary Check Again button, and a default Done button that appears only when setup is complete.
- The window refreshes automatically, with a short debounce, when it becomes key again. Check Again stays as the manual fallback.
- Escape and Command-W close the window. The key-view loop runs through the visible row actions, then Check Again, then Done.
- VoiceOver hears each row as title, state, detail, and then its action, and the updated summary is announced after checks complete.
- The closed-lid setup check explains that it starts a one-minute Amphetamine session, that the user does not need to close the lid, and that the session ends on its own.

## Alerts and confirmation

- End or replace active session: warning alert with Off or the target mode, the selected Travel duration when applicable, the exact action, and Cancel. Night and Travel state that the display will sleep and the Mac will lock after verification.
- Start Work, Night, or Travel: warning alert with the exact mode, selected Travel duration, and Cancel. The text states that the start can replace a session that appears after preflight. Night and Travel also state that the display will sleep and the Mac will lock after verification.
- Quit with active session: warning alert with Turn Off and Quit, Leave Session Running, and Cancel. The destructive choice names Off.
- Quit when session inspection fails: warning alert with Leave Amphetamine Unchanged and Quit and Cancel. No destructive action appears.
- System termination: no alert. Logout, restart, and shutdown continue without an Amphetamine read or mutation.
- Disable Triggers: explicit confirmation before the setting changes.
- Closed-lid setup check: explicit confirmation, the one-minute bounded-session explanation with automatic expiry, and a warning that the timed start can replace a session that appears after the Off check. The confirmation never appears when the app already knows an active session prevents the check; the row states the Off precondition instead.
- A failed Disable Triggers or closed-lid check shows its exact failure reason in the row, not in a modal alert.
- Transition error: native error alert with the exact blocking reason.
- About: includes the Travel enclosed-bag warning.

## Application icon

The icon is generated from original vector-style drawing commands. It shows a cream coffee cup with three distinct steam paths on a navy field. The three paths represent Work, Night, and Travel. The source generator produces a 1024-pixel master and the required `.icns` sizes.

## Accessibility and input

- Use native menu keyboard behavior.
- Do not encode state by color alone.
- Include visible text beside every setup icon.
- Use full process names in conflict messages.
- Do not request Accessibility permission.

## Content rules

- Name the mode first.
- State the result in one short clause.
- Name a blocker and the action the user must take.
- Do not claim network continuity or thermal protection.
- Use “closed-display mode” for Amphetamine’s keep-awake-with-lid-closed behavior.
