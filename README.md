# Caffeine Modes

Caffeine Modes is a small native macOS menu-bar controller for Amphetamine 5.3.2 or later.

It gives you three policies:

- Work keeps the Mac and display awake. Closing the lid works normally.
- Night lets the display sleep and keeps the Mac awake with the lid closed. It stays active until you select Off.
- Travel does the same for 30, 60, 90, or 120 minutes. Amphetamine owns the timer.

Travel does not protect a Mac from heat. Do not run a Mac in an enclosed bag. A location or network change can still stop a network-dependent task.

## Install for a friend

1. Install [Amphetamine from the Mac App Store](https://apps.apple.com/app/amphetamine/id937984704).
2. Open Amphetamine once.
3. Install `Caffeine Modes.app` from the notarized DMG in Applications.
4. Open Caffeine Modes. It appears only in the menu bar.
5. Open Setup Status.
6. Grant Automation access when macOS asks. If it was denied, use the Automation Settings link.
7. Disable Amphetamine Triggers from the setup window.
8. Set the macOS Lock Screen password requirement to Immediately.
9. Run the Closed-Display Test. Follow any Power Protect instructions shown by Amphetamine.
10. Enable Launch at Login when asked.

Caffeine Modes does not request Accessibility access. It has no analytics, telemetry, or network service.

## Daily use

- Select Off to end a Caffeine Modes-owned session.
- Select Work for normal desk work.
- Select Night before overnight work.
- Select Travel and a duration before a short move.
- Select Setup Status… when the menu reports an error.

If Amphetamine has a session that Caffeine Modes did not create, the menu reports Custom. You must confirm before Caffeine Modes replaces it. Quit leaves an unowned Custom session unchanged.

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

`Scripts/verify-app.sh` creates an ad-hoc signed universal app when no build exists. It does not start the app or change a power mode.

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
APP_VERSION=1.0.0 BUILD_NUMBER=1 Scripts/release.sh
APP_VERSION=1.0.0 Scripts/verify-release.sh
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
- `Sources/CaffeineModesApp`: AppKit UI and macOS adapters.
- `Tests/CaffeineModesCoreTests`: Fake-backed P0 tests.
- `Resources`: App metadata and entitlements.
- `Scripts`: Build, requirement, performance, and release gates.
- `SPEC.md`: The one active implementation contract.
- `archive/specs`: Superseded contracts only.

## Live acceptance check

Real Night and Travel tests can lock the screen and change power behavior. Run them only after you install the signed app:

1. Confirm Off.
2. Select Work and confirm the display remains awake.
3. Select Night and confirm the screen locks after display sleep.
4. Select Off.
5. Select Travel 30 Minutes and confirm the countdown.
6. Select Off before you put the Mac in a bag.
7. With the app idle, run `Scripts/verify-performance.sh`.

Version 1 uses manual DMG updates.
