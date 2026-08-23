# Caffeine Modes

Caffeine Modes is a small native macOS menu-bar controller for Amphetamine 5.3.2 or later.

It gives you three policies:

- Work keeps the Mac and all connected displays awake. The lid follows normal macOS behavior.
- Night turns off all connected displays and keeps the locked Mac working. After you unlock, choose Off or Work.
- Travel does the same for 30, 60, 90, or 120 minutes. After you unlock, choose Off or Work. Amphetamine's timer still ends Travel.

Night and Travel can create heat when the Mac is closed. Do not run a Mac in an enclosed bag. A location or network change can still stop a network-dependent task.

## Install for a friend

1. Install [Amphetamine from the Mac App Store](https://apps.apple.com/app/amphetamine/id937984704).
2. Open Amphetamine once.
3. Install `Caffeine Modes.app` from the notarized DMG in Applications.
4. Open Caffeine Modes. It appears only in the menu bar.
5. Open Settings, then Setup.
6. Use the action beside each item that needs attention.
7. Grant Automation access when macOS asks.
8. Disable Amphetamine Triggers.
9. Set the macOS password requirement to Immediately.
10. On Apple Silicon, install Amphetamine Power Protect if Setup asks for it.
11. Enable Launch at Login if you want Caffeine Modes to start with your Mac.

Setup does not make you wait for a one-minute test. Night and Travel verify their required Amphetamine state when you start them. The optional one-minute diagnostic is in the hidden Developer tab. Hold Option while you open Settings to show it.

Caffeine Modes does not request Accessibility access. It has no analytics, telemetry, or network service.

## Daily use

- Select Off to restore normal sleep behavior. Confirm if Amphetamine has an active session.
- Select Work for normal desk work.
- Select Night before overnight work.
- Select Travel and a duration before a short move.
- Select Settings… when the menu reports an error.
- Select How Modes Work… to see the result for your screen setup.

Confirm every Work, Night, or Travel start. Amphetamine does not provide a stable session identity. Your confirmation also allows the new mode to replace a session that appears between the safety check and the start command.

Caffeine Modes also asks before it ends or replaces an active session, even when the policy matches the selected mode. A replacement alert names the mode that will start. Night and Travel warn that all connected displays will turn off and the Mac will lock.

If a key press shows the lock screen during Night or Travel, stay locked. The displays turn off again after 30 seconds. Press Escape to turn them off sooner when macOS allows it. When you unlock, Caffeine Modes suggests Off or Work. You must confirm before it changes Amphetamine. Change the suggestion in Settings.

When you quit Caffeine Modes with an active Amphetamine session, choose one action:

- Turn Off and Quit.
- Leave Session Running.
- Cancel.

If Caffeine Modes cannot check Amphetamine, you can leave Amphetamine unchanged and quit. You can also cancel and keep Caffeine Modes open. The app does not offer Turn Off when it cannot verify the session state.

Logout, restart, and shutdown do not show this prompt. Caffeine Modes exits without changing the Amphetamine session.

## What the power status means

Caffeine Modes keeps three macOS power facts separate:

- **Display kept on** means a named process prevents the screen from sleeping. Night and Travel stop before they change Amphetamine when this is true.
- **Automatic sleep blocked** means a named process prevents idle system sleep. The display can still turn off. Night and Travel do not block on this fact because their purpose is to keep work running.
- **Disk idle sleep blocked** means a process keeps storage active. This does not mean that the display or Mac must stay awake. It appears only in the menu-bar tooltip.

Off reports these facts. It never stops another process. Temporary assertions owned by macOS system services are omitted from the Off summary. Display blockers remain visible because they can stop Night or Travel from sleeping the screen.

Codex can create an automatic-system-sleep assertion when **Prevent Sleep While Running** is on. **Keep Remote Control Awake While Plugged In** can use an automatic-system-sleep or network-client assertion during plugged-in remote work. Caffeine Modes reports both as **Automatic sleep blocked**. Claude and other developer tools can do the same. These assertions do not block Night or Travel unless the process also creates a display-sleep assertion.

## Screen setups

| Mode | Laptop only | Open with external display | Closed with external display |
|---|---|---|---|
| Work | Mac and built-in display stay awake. | Mac and all displays stay awake. | External display stays awake. Normal macOS clamshell requirements apply. |
| Night | Built-in display turns off. The locked Mac keeps working. | All displays turn off. The locked Mac keeps working. | External display turns off. The locked Mac keeps working through Amphetamine. |
| Travel | Built-in display turns off. The locked Mac keeps working until the timer ends. | All displays turn off. The locked Mac keeps working until the timer ends. | External display turns off. The locked Mac keeps working through Amphetamine until the timer ends. |

Caffeine Modes works with displays and docks that already work correctly with macOS and Amphetamine. It does not add display drivers or fix an unstable cable, dock, or display connection.

You can start Travel in any screen setup. You can then disconnect power and displays and move the closed Mac. Power Protect is required on Apple Silicon. When you reconnect an external display or open the lid, macOS can wake the display. Stay locked and Caffeine Modes turns it off again after 30 seconds. If you unlock, confirm Off or Work. Travel stays active until you confirm or its timer ends.

## Development

Requirements:

- macOS 13 or later.
- Xcode with Swift 6.
- Amphetamine 5.3.2 or later for live acceptance tests.

Run the read-only test and build gates:

```sh
swift test --enable-code-coverage
Scripts/verify-coverage.sh
Scripts/verify-app.sh
Scripts/verify-safety.sh
```

`Scripts/verify-app.sh` rebuilds an ad-hoc signed universal app before verification. It does not start the app or change a power mode.

Run one requirement gate:

```sh
Scripts/verify-requirement.sh REQ-004
```

Success prints exactly `PASS REQ-004`.

## Release credentials

The release needs a valid `Developer ID Application: LEAD MEDIA AS (D79LWN85PJ)` identity in the login Keychain. Create or install it through Xcode’s Accounts settings.

The scripts reuse the existing LEAD MEDIA AS Keychain profile `notchfocus-notary`. If that profile is removed, create it again in your own visible Terminal. Do not put the app-specific password in this repository or in shell history:

```sh
xcrun notarytool store-credentials "notchfocus-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "D79LWN85PJ"
```

The command asks for the app-specific password through its prompt. Then verify the local prerequisites:

```sh
Scripts/check-release-prerequisites.sh
```

Build, sign, package, notarize, staple, and verify:

```sh
APP_VERSION=1.1.0 BUILD_NUMBER=4 Scripts/release.sh
APP_VERSION=1.1.0 Scripts/verify-release.sh
```

Release artifacts stay under `dist/` and are ignored by Git.

## Private GitHub backup

The intended private remote is `https://github.com/andreasnlarsen/caffeine-modes.git`.

If GitHub CLI needs authentication, complete this command in your own visible Terminal:

```sh
gh auth login -h github.com -p https -w
```

Then create and push the private backup:

```sh
gh repo create andreasnlarsen/caffeine-modes --private --source=. --remote=origin --push
```

## Repository structure

- `Sources/CaffeineModesCore`: Domain and transition authority.
- `Sources/CaffeineModesAppSupport`: Testable setup, power-status, menu, and Quit presentation and coordinators.
- `Sources/CaffeineModesApp`: AppKit UI and macOS adapters.
- `Tests/CaffeineModesCoreTests`: Fake-backed P0 tests.
- `Resources`: App metadata and entitlements.
- `Scripts`: Build, requirement, performance, and release gates.
- `SPEC.md`: The one active implementation contract.
- `archive/specs`: Superseded contracts only.

## Live acceptance check

Real Night and Travel tests lock the screen and change power behavior. Run them only after you install the signed app.

Test Work, Night, and Travel in these screen setups:

1. Laptop only.
2. Open laptop with an external display.
3. Closed laptop with an external display.

For each setup, start from Off. Verify that Work does not lock or turn off a display. Verify that Night and Travel turn off every connected display and keep the locked Mac working. Show the lock screen without unlocking and verify that the displays turn off again. Then unlock. Verify that Caffeine Modes does not change Amphetamine until you confirm Off or Work.

For Travel, also disconnect the closed Mac, move it, and reconnect it at a new location. Verify both an external-display reconnect and opening the built-in display. This check does not prove network continuity.

After the nine mode and screen-setup checks, select Off before you put the Mac in a bag. With the app idle, run `Scripts/verify-performance.sh`.

The performance check measures the app’s accumulated CPU time across a 60-second window. It uses macOS `footprint` for memory charged to the app. It does not use RSS because RSS also counts clean shared system-library pages.

Version 1 uses manual DMG updates.
