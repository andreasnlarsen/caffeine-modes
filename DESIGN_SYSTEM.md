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
- Body and controls: system control size.
- Secondary detail: system size with `secondaryLabelColor`.
- Do not use custom fonts or text embedded in icons.

## Color

- Use `labelColor`, `secondaryLabelColor`, `windowBackgroundColor`, and other semantic AppKit colors.
- The running menu-bar symbols are template images. macOS controls their color.
- Passed setup checks use the semantic system accent through native symbol rendering.
- Errors use native `NSAlert` warning treatment.
- The Finder icon may use an original navy, cream, amber, blue, and mint palette. These colors do not enter the menu UI.

## Spacing and size

- Base grid: 4 points.
- Setup window outer inset: 24 points.
- Main vertical gap: 16 points.
- Checklist gap: 8 points.
- Related button gap: 8 points.
- Setup window: 520 × 430 points.
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

The selected mode uses one standard checkmark. Travel time appears in the disabled status line and tooltip. The menu-bar item does not use permanent text.

## Symbols

| State | SF Symbol | VoiceOver description intent |
|---|---|---|
| Off | `cup.and.saucer` | Caffeine Modes is Off |
| Work | `cup.and.saucer.fill` | Work keeps Mac and displays awake |
| Night | `moon.fill` | Night keeps the Mac awake with the display asleep |
| Travel | `car.fill` | Travel is active with time remaining |
| Custom or error | `exclamationmark.triangle.fill` | Setup, conflict, or backend needs attention |
| Setup passed | `checkmark.circle.fill` | Check passed |
| Setup incomplete | `exclamationmark.circle` | Check needs attention |

Every symbol uses an accessibility description. No SF Symbol appears in the Finder icon or DMG artwork.

## Setup window

- The app stays Dockless through `LSUIElement` and `.accessory` activation policy.
- Opening Setup Status may activate the setup window for keyboard input.
- The checklist presents one line per dependency.
- Actions appear only as native buttons and links.
- The default Check Again button supports Return.
- Tab order follows the visual order.
- The readiness test explains that it starts and ends a bounded Amphetamine session.

## Alerts and confirmation

- Replace Custom: warning alert with Replace and Cancel.
- Disable Triggers: explicit confirmation before the setting changes.
- Closed-display test: explicit confirmation and bounded-session explanation.
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
