# Caffeine Modes Native Design System

## Product principles

- Show the current state before available actions.
- Report a result only after the app verifies it.
- Give every degraded state a way back without ending the protected task.
- Use standard macOS controls and behavior.
- Keep one clear selection per mode group.
- Put warnings only where a decision has a real risk.
- Keep setup and help separate from daily menu use.

## Night and Travel

Night and Travel make different promises. This section owns that difference. Every other section follows it and does not restate it.

### Night

- Night is for a locked Mac that must keep working with every display dark.
- Night turns off all connected displays, then checks the real display state.
- Night reports success only after it checks that the Mac is locked and every display is off.
- A named display request never stops Night. Night checks the result instead of trusting the request.
- While the Mac stays locked, a display that wakes or reconnects is turned off again.
- Night has no timer. It runs until the user changes the mode or Amphetamine reaches the battery limit.

### Travel

- Travel is for a locked Mac that must keep working for 30, 60, 90, or 120 minutes.
- Travel asks the display to sleep once, only to lock the Mac. It then checks that the Mac locked.
- Displays off is not a Travel result. Travel never turns a display off again.
- Travel always locks. No unlocked Travel option exists.
- A named display request never stops Travel. It appears only as a tooltip fact, never as a warning symbol or replacement for the verified lock status.
- Waking, unplugging, or reconnecting a display does not change Travel or its timer.
- Amphetamine owns the timer and the battery limit, so both survive if Caffeine Modes stops.

### Exact status strings

| State | Menu status line | Symbol |
|---|---|---|
| Night verified | `Night · Displays off · Mac working while locked` | `moon.fill` |
| Travel verified | `Travel · [time] left · Mac working while locked` | `car.fill` |
| Night found a display still on | `Night · Displays still on · Mac working while locked` | `exclamationmark.triangle.fill` |
| Night could not check the displays | `Night · Displays not checked · Mac working while locked` | `exclamationmark.triangle.fill` |
| Night found the Mac unlocked | `Night · Mac did not lock` | `exclamationmark.triangle.fill` |
| Night could not check the lock | `Night · Lock not checked` | `exclamationmark.triangle.fill` |
| Travel found the Mac unlocked | `Travel · [time] left · Mac did not lock` | `exclamationmark.triangle.fill` |
| Travel could not check the lock | `Travel · [time] left · Lock not checked` | `exclamationmark.triangle.fill` |

### Degraded states and recovery

Both degraded states keep the Amphetamine session running. Neither ends a mode by itself, and Travel keeps its timer. Each shows one cause line under the status line, then its two actions, before Off.

Night could not confirm that every display is off:

- Status line, when a display is still on: `Night · Displays still on · Mac working while locked`
- Status line, when the display state cannot be read: `Night · Displays not checked · Mac working while locked`
- Additional fact, when a process is named: `Display stay-awake request: [process].`
- Cause line otherwise: `Your screen may still be visible.`
- Actions, in this order: `Retry Display Sleep`, `Turn Off Night`.
- VoiceOver for a display issue: `Night needs attention. Your Mac is locked and working, but its displays are not confirmed off.`
- VoiceOver for a lock issue: `Night needs attention. The lock is not confirmed.`

Travel could not confirm the lock:

- Status line, when the Mac is unlocked: `Travel · [time] left · Mac did not lock`
- Status line, when the lock state cannot be read: `Travel · [time] left · Lock not checked`
- Cause line, when the Mac is unlocked: `Anyone at your Mac can use it.`
- Cause line, when the lock state cannot be read: `Your Mac may be unlocked.`
- Actions, in this order: `Try Lock Again`, `Turn Off Travel`.
- VoiceOver for the menu-bar item: `Travel needs attention. The lock is not confirmed. [time] left.`

### Confirmation consequences

Night start, and Night replacing a session, state: `All connected displays will turn off now. Your Mac will lock.`

Travel start, and Travel replacing a session, state: `Your Mac will lock and keep working for [duration] minutes. Displays can turn back on without stopping Travel.`

Travel adds one warning line when a process holds a display assertion: `[process] asked to keep a display on. That can use more battery or create heat. Travel still starts.`

That warning never blocks Travel, never changes the button titles, and never tells the user to quit or force-quit another app. Caffeine Modes never ends another app.

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
- The Finder icon uses an indigo, silver, amber, and mint palette. These colors do not enter the menu UI.

## Spacing and size

- Base grid: 4 points.
- Settings window outer inset: 24 points.
- Main vertical gap: 20 points between sections.
- Setup rows: 12 points between rows, 8 points between a group header and its rows.
- Settings window: 720 points wide. Its height fits the selected pane and keeps the top edge fixed when panes change. Panes do not scroll; every pane stays well under the smallest supported screen height, including enlarged text sizes.
- Menu items, alerts, buttons, and hit targets use native AppKit sizing.

## Menu structure

1. Disabled status line.
2. Degraded Night or Travel only: one disabled cause line, then the two recovery actions from Degraded states and recovery.
3. Off.
4. Work.
5. Night.
6. Travel submenu with 30, 60, 90, and 120 minutes.
7. Settings…
8. How Modes Work…
9. Launch at Login.
10. About Caffeine Modes.
11. Quit Caffeine Modes.

The selected mode uses one standard checkmark. Travel time appears in the disabled status line and tooltip. The countdown rounds up to a whole minute and uses hours plus minutes at 60 minutes or more. The menu-bar item does not use permanent text.

### Power status language

- Off with no external blocker: `Off · Follows macOS`.
- Off with a display blocker: `Off · Display kept on by [process]`.
- Off with an idle system blocker: `Off · Automatic sleep blocked by [process]`.
- Work: `Work · Mac and displays stay awake`.
- Night and Travel use the status strings in Exact status strings. No other section restates them.
- Do not use `Mac held awake`. That phrase hides which sleep behavior changed.
- A disk-idle blocker appears only in the tooltip. It never implies that display or system sleep is blocked.
- Temporary macOS service assertions do not appear in the Off summary. A macOS display assertion still appears, because it can keep a display on.
- During Night, a display that is still on shows the degraded Night state. It is not a separate warning.

### Tooltip facts

The tooltip repeats the status line, then lists each fact on its own line. Display sleep, automatic system sleep, and disk idle sleep stay three separate facts. One assertion type never implies another.

```
Caffeine Modes — [status line]
Display sleep: [fact].
Automatic sleep: [fact].
Disk idle sleep: [fact].
Lid: [fact].
Lock: [fact].
Displays: [fact].
```

- The display assertion line reads `[process] asked to keep a display on` or `no external stay-awake request detected`.
- During Travel, the display assertion is informational. The menu status still reports the verified lock and timer.
- Lid reads `closed-display mode is enabled.` during Night and Travel, and `normal macOS behavior.` otherwise.
- The Lock line appears only during Night and Travel. It reads `checked.` or `not checked.`
- The Displays line appears only during Night. It reads `all off.`, `still on.`, or `not checked.`
- When power assertions cannot be read, the tooltip replaces the three assertion lines with `Power assertion details are unavailable.` and keeps the Lid, Lock, and Displays lines.

## Symbols

| State | SF Symbol | VoiceOver description intent |
|---|---|---|
| Off | `cup.and.saucer` | Caffeine Modes is Off |
| Work | `cup.and.saucer.fill` | Work keeps Mac and displays awake |
| Night | `moon.fill` | Night is on. All displays are off and your Mac is locked |
| Travel | `car.fill` | Travel is on. Your Mac is locked, with time remaining |
| Custom or error | `exclamationmark.triangle.fill` | Setup, conflict, or backend needs attention |
| Setup complete | `checkmark.circle.fill` | Check is complete |
| Setup needs action | `exclamationmark.circle.fill` | Check needs the user's action |
| Setup not checked | `circle.dashed` | Check has not run or cannot run yet |
| Developer diagnostic active | `hourglass` | Optional diagnostic is active and ends automatically |

Degraded Night and degraded Travel use `exclamationmark.triangle.fill` with the exact VoiceOver descriptions in Degraded states and recovery.

Every symbol uses an accessibility description that names the same outcome the visible text names. No SF Symbol appears in the Finder icon or DMG artwork.

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
- The battery row states whether Amphetamine ends sessions at the required percentage. A mismatch says `In Session Defaults: end at 15%, no prompt, keep ‘Ignore charge’ off.` with the selected percentage and offers `Open Amphetamine`. Caffeine Modes never claims that it changed those settings.
- Each row shows a 16-point state symbol, a title, a per-row detail line, and at most one trailing action. Rows that pass show no action. A row that cannot run yet names its precondition instead of opening a confirmation.
- Every check uses one of three honest states: complete, needs action, or not checked. A check that has never run uses the not-checked symbol, never a warning.
- Setup never requires a one-minute test. It reports readiness in a few seconds.
- Long checks and the optional Developer diagnostic run on a serial worker queue. The bounded AppleScript boundary uses the main thread because macOS requires it. The row or footer shows a small spinner with progress text, and conflicting controls are disabled while work runs.
- Menu status and mode orchestration also run on a serial worker queue, with only the bounded AppleScript boundary on the main thread. The menu disables conflicting mode and Quit actions while a change is active.
- Setup shows one short summary and a secondary Check Again button.
- The window refreshes automatically, with a short debounce, when it becomes key again. Check Again stays as the manual fallback.
- Escape and Command-W close the window. The key-view loop follows the visible controls in reading order.
- VoiceOver hears each row as title, state, detail, and then its action, and the updated summary is announced after checks complete.
- Developer explains that its optional diagnostic verifies Amphetamine in a few seconds and leaves a temporary one-minute session to end automatically. The user can keep the lid open.

### Modes pane

Modes uses a 3 by 3 matrix with the column headers `Mode`, `Laptop`, `Open + external`, and `Closed + external`. Each cell states the result for that setup in one or two short sentences. VoiceOver reads each cell with its mode and column.

| Mode | Laptop | Open + external | Closed + external |
|---|---|---|---|
| Work | `Mac and built-in display stay awake.` | `Mac and all displays stay awake.` | `External display stays awake. Normal clamshell rules apply.` |
| Night | `Built-in display turns off. Mac locks and keeps working.` | `All displays turn off. Mac locks and keeps working.` | `External display turns off. Mac locks and keeps working.` |
| Travel | `Mac locks and keeps working until the timer ends. The display is not kept off.` | `Mac locks and keeps working until the timer ends. Displays are not kept off.` | `Mac locks and keeps working until the timer ends. The lid can stay closed.` |

Seven short notes follow the matrix, in this order:

1. `Night keeps all connected displays off. Travel does not.`
2. `If a display turns on while your Mac is locked, Night turns it off again. Travel does nothing.`
3. `Unplugging or reconnecting a display does not stop Travel or its timer.`
4. `When you require battery protection, Amphetamine ends Night and Travel at that battery level.`
5. `No mode keeps your network connected.`
6. `Works with displays and docks that already work normally with macOS and Amphetamine.`
7. `Night and Travel can make a closed Mac hot. Do not run a closed Mac inside an enclosed bag.`

Note 7 is the one fact that appears twice, because About is its permanent home. Both places use that exact string. Every other fact appears once.

## Alerts and confirmation

- End or replace active session: warning alert with Off or the target mode, the selected Travel duration when applicable, the exact action, and Cancel. Night and Travel add the consequences in Confirmation consequences.
- Start Work, Night, or Travel: warning alert with the exact mode, selected Travel duration, and Cancel. The text states that the start can replace a session that appears after preflight. Night and Travel add the consequences in Confirmation consequences.
- Quit with active session: warning alert with Turn Off and Quit, Leave Session Running, and Cancel. The destructive choice names Off.
- Quit when session inspection fails: warning alert with Leave Amphetamine Unchanged and Quit and Cancel. No destructive action appears.
- System termination: no alert. Logout, restart, and shutdown continue without an Amphetamine read or mutation.
- Disable Triggers: explicit confirmation before the setting changes.
- Developer diagnostic: explicit confirmation, the one-minute bounded-session explanation with automatic expiry, and a warning that the timed start can replace a session that appears after the Off check. The confirmation never appears when the app already knows an active session prevents the diagnostic; the row states the Off precondition instead.
- A failed Disable Triggers action or Developer diagnostic shows its exact failure reason in the row, not in a modal alert.
- Transition error: native error alert with the exact blocking reason.
- No display request opens this alert. A named process is information in the tooltip and the Travel confirmation.
- Degraded Night and degraded Travel never open an alert. They stay in the menu with their cause line and recovery actions, so the protected task is never interrupted by a modal.
- Closed-lid replacement stop: when Work, Night, or Travel cannot safely replace an active closed-display session, the error names the current session and selected mode, then tells the user to open the lid. A closed Mac can switch directly when the app detects external power and an active external display. Normal macOS clamshell requirements still apply. Off stays available. Turning off an inactive closed-display default shows no alert.
- About: names the three modes, then states `Night and Travel can make a closed Mac hot. Do not run a closed Mac inside an enclosed bag.` Enclosed-bag use is unsupported.

## Application icon

The icon is supplied artwork, `Resources/AppIcon.png`: a closed silver Mac with one mint status light, under an amber crescent moon, on an indigo tile. It says what Night and Travel do: the Mac keeps working while it is closed. `Scripts/generate-icon.sh` makes the required `.icns` sizes from that 1024-pixel master. Until 1.2.0 the icon was a drawn coffee cup with three steam paths.

## Accessibility and input

- Use native menu keyboard behavior.
- Do not encode state by color alone.
- Include visible text beside every Setup icon.
- Every accessibility name states the same outcome as the visible text. A degraded state never sounds normal.
- Recovery actions keep their visible titles as their accessibility names.
- Use full process names in conflict messages.
- Do not request Accessibility permission.

## Content rules

- Name the mode first.
- State the result in one short clause.
- State one fact once. The closed-Mac heat warning is the only intended repeat, and both places use the same string.
- Assume the reader has no product context. Use everyday words.
- Name a blocking condition and the action the user must take. Describe process assertions as requests, not proven causes.
- Say what a mode does, never what a mode is like. Never describe Travel as behaving like Night.
- Do not claim network continuity or thermal protection.
- Never tell the user to quit another app, and never end another app.
- Use “closed-display mode” for Amphetamine’s keep-awake-with-lid-closed behavior.
- Use short user terms in daily UI. Keep backend terms in Setup details and technical documentation.
