# Caffeine Modes Native Design System

## Product principles

- Show the current state before available actions.
- Use standard macOS controls and behavior.
- Keep one clear selection per mode group.
- Put warnings only where a decision has a real risk.
- Keep setup and help separate from daily menu use.

## Typography

- Use San Francisco through `NSFont.systemFont`.
- Settings title: 22 pt semibold where a tab needs a page heading.
- Settings group headers: 11 pt semibold with `secondaryLabelColor`.
- Settings row titles: 13 pt medium.
- Settings row details: 11 pt with `secondaryLabelColor`.
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
- Settings window outer inset: 24 points.
- Main vertical gap: 20 points between sections.
- Setup rows: 12 points between rows, 8 points between a group header and its rows.
- Settings window: 720 points wide. Its height fits the selected pane and keeps the top edge fixed when panes change. Panes do not scroll; every pane stays well under the smallest supported screen height, including enlarged text sizes.
- Menu items, alerts, buttons, and hit targets use native AppKit sizing.

## Menu structure

1. Disabled status line.
2. Off.
3. Work.
4. Night.
5. Travel submenu with 30, 60, 90, and 120 minutes.
6. Settings…
7. How Modes Work…
8. Launch at Login.
9. About Caffeine Modes.
10. Quit Caffeine Modes.

The selected mode uses one standard checkmark. Travel time appears in the disabled status line and tooltip. The countdown rounds up to a whole minute and uses hours plus minutes at 60 minutes or more. The menu-bar item does not use permanent text.

### Power status language

- Off with no external blocker: `Off · Follows macOS`.
- Display blocker: `Display kept on by [process]`.
- Idle system blocker: `Automatic sleep blocked by [process]`.
- Do not use `Mac held awake`. That phrase hides which sleep behavior changed.
- A disk-idle blocker appears only in the tooltip. It never implies that display or system sleep is blocked.
- The tooltip lists display sleep, automatic system sleep, disk idle sleep, and lid behavior as separate lines.
- Temporary macOS service assertions do not appear in the Off summary. A macOS display assertion still appears because it can block Night or Travel.
- Work: `Work · Mac and displays stay awake`.
- Night: `Night · Mac working while locked`.
- Travel: `[time] left · Mac working while locked`.
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
| Developer diagnostic active | `hourglass` | Optional diagnostic is active and ends automatically |

Every symbol uses an accessibility description. No SF Symbol appears in the Finder icon or DMG artwork.

## Settings window

- The app stays Dockless through `LSUIElement` and `.accessory` activation policy.
- Opening Settings may activate the window for keyboard input.
- A native selectable toolbar contains General, Setup, and Modes. The window title names the selected pane.
- Each pane ends one outer inset below its final control or note. The window does not reserve an empty fixed-height canvas.
- Developer appears only when the user holds Option while opening Settings.
- General contains Launch at Login, the Off-or-Work suggestion shown after Night or Travel unlocks, and one battery-protection requirement. The user must confirm unlock suggestions before the app changes Amphetamine.
- The battery row uses one native checkbox followed by one compact pop-up. Its exact title is `Require battery protection for Night and Travel at:`. Values are 5%, 10%, 15%, 20%, 25%, and 30%; 15% is the default. When disabled, the pop-up keeps the selected value and becomes inactive. The short footnote says `Night and Travel will not start until Amphetamine matches.` Turning the requirement off needs one native confirmation. No slider, card, decorative icon, or custom color appears.
- General states once, as a short footnote, that starting Work turns off Amphetamine’s closed-display mode and that this includes sessions the user starts in Amphetamine. No other pane repeats this fact.
- Setup contains Amphetamine, Automation, Triggers, immediate lock, Power Protect, and Amphetamine battery protection as six self-contained rows.
- The battery row states whether Amphetamine ends sessions at the required percentage on battery power. A mismatch says `In Session Defaults: end at 15%, no prompt, ignore on power.` with the selected percentage and offers `Open Amphetamine`. Caffeine Modes never claims that it changed those settings.
- Each row shows a 16-point state symbol, a title, a per-row detail line, and at most one trailing action. Rows that pass show no action. A row that cannot run yet names its precondition instead of opening a confirmation.
- Every check uses one of three honest states: complete, needs action, or not checked. A check that has never run uses the not-checked symbol, never a warning.
- Setup never requires a one-minute test. It reports readiness in a few seconds.
- Long checks and the optional Developer diagnostic run on a serial worker queue. The bounded AppleScript boundary uses the main thread because macOS requires it. The row or footer shows a small spinner with progress text, and conflicting controls are disabled while work runs.
- Menu status and mode orchestration also run on a serial worker queue, with only the bounded AppleScript boundary on the main thread. The menu disables conflicting mode and Quit actions while a change is active.
- Setup shows one short summary and a secondary Check Again button.
- The window refreshes automatically, with a short debounce, when it becomes key again. Check Again stays as the manual fallback.
- Escape and Command-W close the window. The key-view loop follows the visible controls in reading order.
- VoiceOver hears each row as title, state, detail, and then its action, and the updated summary is announced after checks complete.
- Modes contains a 3 by 3 matrix for laptop only, open laptop with an external display, and closed laptop with an external display. It states what Work, Night, and Travel do in each setup.
- Modes states that Caffeine Modes works with displays that already work correctly with macOS and Amphetamine.
- Developer explains that its optional diagnostic verifies Amphetamine in a few seconds and leaves a temporary one-minute session to end automatically. The user can keep the lid open.

## Alerts and confirmation

- End or replace active session: warning alert with Off or the target mode, the selected Travel duration when applicable, the exact action, and Cancel. Night and Travel state: `All connected displays will turn off now. Your Mac will lock.`
- Start Work, Night, or Travel: warning alert with the exact mode, selected Travel duration, and Cancel. The text states that the start can replace a session that appears after preflight. Night and Travel state: `All connected displays will turn off now. Your Mac will lock.`
- Quit with active session: warning alert with Turn Off and Quit, Leave Session Running, and Cancel. The destructive choice names Off.
- Quit when session inspection fails: warning alert with Leave Amphetamine Unchanged and Quit and Cancel. No destructive action appears.
- System termination: no alert. Logout, restart, and shutdown continue without an Amphetamine read or mutation.
- Disable Triggers: explicit confirmation before the setting changes.
- Developer diagnostic: explicit confirmation, the one-minute bounded-session explanation with automatic expiry, and a warning that the timed start can replace a session that appears after the Off check. The confirmation never appears when the app already knows an active session prevents the diagnostic; the row states the Off precondition instead.
- A failed Disable Triggers action or Developer diagnostic shows its exact failure reason in the row, not in a modal alert.
- Transition error: native error alert with the exact blocking reason.
- Closed-lid replacement stop: when Work, Night, or Travel cannot safely replace an active closed-display session, the error names the current session and selected mode, then tells the user to open the lid. A closed Mac can switch directly when the app detects external power and an active external display. Normal macOS clamshell requirements still apply. Off stays available. Turning off an inactive closed-display default shows no alert.
- About: warns that Night and Travel can create heat when the Mac is closed. Enclosed-bag use is unsupported.

## Application icon

The icon is generated from original vector-style drawing commands. It shows a cream coffee cup with three distinct steam paths on a navy field. The three paths represent Work, Night, and Travel. The source generator produces a 1024-pixel master and the required `.icns` sizes.

## Accessibility and input

- Use native menu keyboard behavior.
- Do not encode state by color alone.
- Include visible text beside every Setup icon.
- Use full process names in conflict messages.
- Do not request Accessibility permission.

## Content rules

- Name the mode first.
- State the result in one short clause.
- Name a blocker and the action the user must take.
- Do not claim network continuity or thermal protection.
- Use “closed-display mode” for Amphetamine’s keep-awake-with-lid-closed behavior.
- Use short user terms in daily UI. Keep backend terms in Setup details and technical documentation.
