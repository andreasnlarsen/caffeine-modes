# Caffeine Modes

Caffeine Modes is a small native macOS menu-bar controller for Amphetamine 5.3.2 or later.

It gives you three policies:

- Work keeps the Mac and all connected displays awake. The lid follows normal macOS behavior.
- Night turns off all connected displays and keeps the locked Mac working. After you unlock, choose Off or Work.
- Travel locks the Mac and keeps it working for 30, 60, 90, or 120 minutes. Displays can wake or reconnect without stopping Travel. After you unlock, choose Off or Work. Amphetamine's timer still ends Travel.

Battery protection is required by default at 15%. Night and Travel start only when Amphetamine is set to end sessions at 15%, without a prompt or power-adapter exception. Amphetamine owns the cutoff, so it still works if Caffeine Modes stops.

Starting Work turns off Amphetamine's closed-display mode, so the lid follows normal macOS behavior. That default stays off for sessions you start in Amphetamine yourself, until you enable it again in Amphetamine.

While the lid is closed, you can replace an active Night, Travel, or other closed-display session only when Caffeine Modes detects external power and an active external display. Normal macOS clamshell requirements still apply. Otherwise, open the lid before you start Work, Night, or Travel. Off always remains available.

Night and Travel can create heat when the Mac is closed. Do not run a Mac in an enclosed bag. A location or network change can still stop a network-dependent task.

Free and open source under the [MIT licence](LICENSE).

## Install

1. Install [Amphetamine from the Mac App Store](https://apps.apple.com/app/amphetamine/id937984704).
2. Open Amphetamine once.
3. Install Caffeine Modes with Homebrew: `brew install --cask andreasnlarsen/tap/caffeine-modes`. Homebrew 6 and later ask you to trust taps outside the official catalogue; if the install is refused with "untrusted tap", run `brew trust andreasnlarsen/tap` once and install again. Or download the notarized DMG from [Releases](https://github.com/andreasnlarsen/caffeine-modes/releases) and drag `Caffeine Modes.app` to Applications.
4. Open Caffeine Modes. It appears only in the menu bar.
5. Open Settings, then Setup.
6. Use the action beside each item that needs attention.
7. Grant Automation access when macOS asks.
8. Disable Amphetamine Triggers.
9. Set the macOS password requirement to Immediately.
10. On Apple Silicon, install Amphetamine Power Protect if Setup asks for it.
11. In Amphetamine > Settings > Session Defaults, enable `End session if charge (%) is below`, select 15%, turn off its prompt, and leave `Ignore charge (%) if power adapter is connected` off.
12. Enable Launch at Login if you want Caffeine Modes to start with your Mac.

Setup does not make you wait for a one-minute test. Night and Travel verify their required Amphetamine state when you start them. The optional one-minute diagnostic is in the hidden Developer tab. Hold Option while you open Settings to show it.

Caffeine Modes does not request Accessibility access. It has no analytics, telemetry, or network service.

## Daily use

- Select Off to restore normal sleep behavior. Confirm if Amphetamine has an active session.
- Select Work for normal desk work.
- Select Night before overnight work.
- Select Travel and a duration before a short move.
- Select Settings… when the menu reports an error.
- Select How Modes Work… to see the result for your screen setup.

In Settings > General, choose the battery protection that Night and Travel require. Setup tells you when Amphetamine matches. Changing this requirement does not change Amphetamine.

Confirm every Work, Night, or Travel start. Amphetamine does not provide a stable session identity. Your confirmation also allows the new mode to replace a session that appears between the safety check and the start command.

Caffeine Modes also asks before it ends or replaces an active session, even when the policy matches the selected mode. A replacement alert names the mode that will start. Night says that all connected displays will turn off and the Mac will lock. Travel says that the Mac will lock for the selected time and that displays can turn back on.

If a key press shows the lock screen during Night, stay locked. Night turns the displays off again after 30 seconds. Press Escape to turn them off sooner when macOS allows it. Travel does not turn a display off again after it wakes. When you unlock Night or Travel, Caffeine Modes suggests Off or Work. You must confirm before it changes Amphetamine. Change the suggestion in Settings.

When you quit Caffeine Modes with an active Amphetamine session, choose one action:

- Turn Off and Quit.
- Leave Session Running.
- Cancel.

If Caffeine Modes cannot check Amphetamine, you can leave Amphetamine unchanged and quit. You can also cancel and keep Caffeine Modes open. The app does not offer Turn Off when it cannot verify the session state.

Logout, restart, and shutdown do not show this prompt. Caffeine Modes exits without changing the Amphetamine session.

## What the power status means

Caffeine Modes keeps three macOS power facts separate:

- **Display stay-awake request** means a named process asked macOS to keep a display on. This does not prove that the display is visible. It never blocks Night or Travel.
- **Automatic sleep blocked** means a named process prevents idle system sleep. The display can still turn off. Night and Travel do not block on this fact because their purpose is to keep work running.
- **Disk idle sleep blocked** means a process keeps storage active. This does not mean that the display or Mac must stay awake. It appears only in the menu-bar tooltip.

Off reports these facts. It never stops another process. Temporary assertions owned by macOS system services are omitted from the Off summary. Night checks the real display result after its sleep request. Travel shows a display request in its start confirmation and tooltip because it can use more battery or create heat.

Codex can create an automatic-system-sleep assertion when **Prevent Sleep While Running** is on. **Keep Remote Control Awake While Plugged In** can use an automatic-system-sleep or network-client assertion during plugged-in remote work. Caffeine Modes reports both as **Automatic sleep blocked**. Claude and other developer tools can do the same. No process assertion makes Caffeine Modes stop or quit that process.

## Screen setups

| Mode | Laptop only | Open with external display | Closed with external display |
|---|---|---|---|
| Work | Mac and built-in display stay awake. | Mac and all displays stay awake. | External display stays awake. Normal macOS clamshell requirements apply. |
| Night | Built-in display turns off. The locked Mac keeps working. | All displays turn off. The locked Mac keeps working. | External display turns off. The locked Mac keeps working through Amphetamine. |
| Travel | Mac locks and keeps working until the timer ends. The display is not kept off. | Mac locks and keeps working until the timer ends. Displays are not kept off. | Mac locks and keeps working until the timer ends. The lid can stay closed. |

Caffeine Modes works with displays and docks that already work correctly with macOS and Amphetamine. It does not add display drivers or fix an unstable cable, dock, or display connection.

You can start Travel in any screen setup. You can then disconnect power and displays and move the closed Mac. Power Protect is required on Apple Silicon. When you reconnect an external display or open the lid, macOS can wake the display. Travel does not turn it off again. The Mac stays locked until you unlock it. Travel stays active until you confirm Off or Work, or its timer ends.

## FAQ

### What does the low-battery limit do?

The default requirement is On at 15%. Before Night or Travel starts, Caffeine Modes checks four Amphetamine Session Defaults:

- End the session on low battery is on.
- The limit matches the selected percentage.
- Prompt before ending is off.
- Ignore the limit while external power is connected is off.

Night and Travel stop before they change Amphetamine when any value does not match or cannot be read. Work and Off remain available.

Amphetamine owns the actual battery cutoff. Caffeine Modes does not watch the battery or send a second automatic end command. This prevents two controllers from racing and keeps the cutoff active if Caffeine Modes quits or crashes.

### Does Caffeine Modes change Amphetamine's battery settings?

No. Amphetamine does not expose a supported AppleScript command for these settings. Caffeine Modes reads the local Session Defaults and opens Amphetamine when they need attention. You make the change in Amphetamine.

The Amphetamine setting is global for non-Trigger sessions. It can also end Work and sessions that you start in Amphetamine. Turning off the Caffeine Modes requirement only stops the preflight check. It does not turn off Amphetamine's own battery limit.

### What if I unplug a separate charger but keep the display connected?

If the remaining display cable does not provide power, the Mac switches to battery. Night or Travel stays active. Amphetamine ends the session at its configured limit. Normal macOS sleep behavior then returns.

If the remaining display cable provides enough power, the battery stays above the limit. If it provides too little power, the battery can still drain. Amphetamine ends the session at the configured limit because `Ignore charge (%) if power adapter is connected` stays off.

### What if one USB-C cable carries power and the display signal?

Unplugging that cable removes both power and the external display. It can also remove Ethernet, external disks, audio, and other dock devices. Night or Travel can keep the closed Mac working through Amphetamine Power Protect. Amphetamine ends the session at its configured battery limit.

A task can still fail if it needs a removed disk, device, network adapter, or network connection. Caffeine Modes protects the power session. It does not preserve removed hardware or network continuity.

### How is Night different from Work plus Lock and Escape?

Work tells Amphetamine to keep the displays awake. It also restores normal macOS lid behavior. Lock and Escape can hide the screen, but Work is not the supported display-sleep policy.

Night allows display sleep, enables closed-display work, locks the Mac, and requests display sleep only after it verifies the full policy. If the lock screen appears again while Night stays locked, Caffeine Modes requests display sleep again after 30 seconds.

### What if an app asks to keep a display on during Travel?

Travel still starts. The confirmation names the app and warns about battery use and heat. Caffeine Modes then tries to lock the Mac once. It does not quit the app or keep fighting the display.

If the Mac does not lock, Travel and its timer stay active so the protected task keeps running. The menu shows `Mac did not lock` with `Try Lock Again` and `Turn Off Travel`.

### What if Night cannot turn every display off?

Night and its owned Amphetamine session stay active. The menu shows the real result and offers `Retry Display Sleep` and `Turn Off Night`. Caffeine Modes never reports ready Night until the Mac is locked and every online display is asleep.

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
APP_VERSION=1.2.1 BUILD_NUMBER=9 Scripts/release.sh
APP_VERSION=1.2.1 Scripts/verify-release.sh
```

Release artifacts stay under `dist/` and are ignored by Git.

## Publishing a release

The repository is public at `https://github.com/andreasnlarsen/caffeine-modes`. After the two commands above pass:

1. Tag the commit the DMG was built from as `v<version>` and push the tag.
2. Create the GitHub release for that tag and attach `dist/Caffeine-Modes-<version>.dmg`.
3. In `andreasnlarsen/homebrew-tap`, set `version` and `sha256` in `Casks/caffeine-modes.rb` to the new DMG and push.

To update an installed copy: `brew upgrade --cask caffeine-modes`. To remove it: `brew uninstall --cask caffeine-modes`. Turn the mode Off first, because removing the app does not end an Amphetamine session.

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

For each setup, start from Off. Verify that Work does not lock or turn off a display. Verify that Night turns off every connected display and keeps the locked Mac working. Show the lock screen without unlocking and verify that Night turns the displays off again. Verify that Travel locks the Mac and keeps working, but does not turn a display off again after it wakes. Then unlock. Verify that Caffeine Modes does not change Amphetamine until you confirm Off or Work.

For Travel, also disconnect the closed Mac, move it, and reconnect it at a new location. Verify both an external-display reconnect and opening the built-in display. Verify that the timer continues and the display can stay on. This check does not prove network continuity.

Check the closed-lid replacement rule separately:

1. Connect power and a working external display. Turn Off Amphetamine. Enable its closed-display default. Keep the Mac closed. Start Work. Verify that Work starts, the external display stays on, and Amphetamine's closed-display default turns off.
2. With power and the external display still connected, start Night. Switch to Travel, then Work. Verify that each confirmed switch succeeds and the Mac stays awake.
3. Start Night again. Remove power while the lid stays closed. Try Work, Night, and Travel. Verify that each choice names the current session, changes nothing, and asks you to open the lid.
4. Open the lid. Switch through Work, Night, Travel, and Off. Verify that every confirmed switch succeeds.

Automated tests cover missing displays, unknown hardware facts, same-mode restarts, every source-to-target pair, and a context change immediately before replacement. Do not disconnect the only display you use to control this manual check.

After the nine mode and screen-setup checks, select Off before you put the Mac in a bag. With the app idle, run `Scripts/verify-performance.sh`.

The performance check measures the app’s accumulated CPU time across a 60-second window. It uses macOS `footprint` for memory charged to the app. It does not use RSS because RSS also counts clean shared system-library pages.

Version 1 uses manual DMG updates.
