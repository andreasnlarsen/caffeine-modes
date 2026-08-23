# Caffeine Modes Product Specification

Status: Active implementation contract

Version: 1.1.1

Last updated: 2026-08-23

## 1. Goal

Caffeine Modes is a native macOS menu-bar app that gives Andreas and trusted friends three clear Amphetamine policies: Work, Night, and bounded Travel. It verifies the external state before it reports success or sleeps the display.

## 2. Non-goals

- NG-001: Caffeine Modes does not replace Amphetamine in version 1.
- NG-002: Caffeine Modes does not keep network connections alive while the Mac changes location or network.
- NG-003: Caffeine Modes does not make enclosed-bag use supported or thermally safe.
- NG-004: Version 1 has no Sparkle updater, Mac App Store build, public download site, analytics, or telemetry.
- NG-005: The app does not terminate a pre-existing or unrelated process, use Accessibility access, or install a privileged helper.

## 3. Target Users

- Primary: Andreas, who uses long-running local work, overnight processing, and short trips between work locations.
- Secondary: Trusted friends who already use, or can install, Amphetamine 5.3.2 or later.
- Environment: A portable Mac on macOS 13 or later.

## 4. User Stories / Behaviors

- As a user, I can select Off and restore normal macOS sleep behavior.
- As a user, I can select Work and keep the Mac and all connected displays awake while the lid follows normal macOS behavior.
- As a user, I can select Night and turn off all displays while the locked Mac keeps working. After I unlock, Caffeine Modes asks before it changes the active session.
- As a user, I can select Travel for 30, 60, 90, or 120 minutes. It behaves like Night and expires through Amphetamine if Caffeine Modes stops. After I unlock, Caffeine Modes asks before it changes the active session.
- As a user, a key press can show the lock screen without ending Night or Travel. If I stay locked, Caffeine Modes turns the displays off again after 30 seconds.
- As a user, I see a diagnostic status for an incomplete operation, an optional developer diagnostic, or an active Amphetamine policy that does not match the stored Caffeine Modes projection.
- As a user, I must confirm before Caffeine Modes ends or replaces any active Amphetamine session.
- As a user, I must confirm every Work, Night, or Travel start. This confirmation also authorizes replacement if another Amphetamine session appears after the preflight check.
- As a user, I see the process name when another app blocks display sleep.
- As a user, I can tell whether a process blocks display sleep, automatic system sleep, or disk idle sleep. These facts are never reduced to the phrase "Mac held awake."
- As a user, Settings gives me General, Setup, and Modes tabs. A hidden Developer tab contains the optional one-minute diagnostic.
- As a user, I can choose Off or Work as the suggested action after I unlock Night or Travel. Off is the default. I still confirm the change.
- As a user, Quit lets me end the active session or leave it running. If I choose to end it, the app stays open when Off cannot be verified.
- As a user, logout, restart, and shutdown do not wait for a Caffeine Modes prompt or Amphetamine command.

## 5. Requirements

### P0

- REQ-001 — Repository and artifacts. Acceptance: The root contains one active `SPEC.md`, `DESIGN_SYSTEM.md`, `README.md`, SwiftPM core, app-support, app, and test targets, release scripts, and a git repository on `main`.
- REQ-002 — Guided setup. Acceptance: Setup reports Amphetamine presence and version, Automation access, Trigger state, immediate screen-lock policy, and Power Protect availability as separate deterministic results. Every problem row includes its matching action. The Amphetamine read and screen-lock query each use an independent bounded deadline. No one-minute session blocks normal use. The optional Developer diagnostic expires through Amphetamine and never counts toward Setup readiness.
- REQ-003 — Mode reconciliation. Acceptance: Off, Work, Night, Travel, and Custom are mutually exclusive projections of Amphetamine state plus one stored diagnostic session signature.
- REQ-004 — Night transition and wake lifecycle. Acceptance: Night blocks named external display assertions before mutation, applies its Amphetamine policy, verifies that policy, and only then requests display sleep. A screen wake while still locked keeps Night active and causes one verified re-sleep request after 30 seconds. Each new screen-visibility event gets at most one bounded retry after another 30 seconds if that re-sleep fails. A verified unlock performs no Amphetamine mutation. It asks the user to confirm the saved Off or Work suggestion. Automatic-system-sleep and disk-idle assertions remain observational.
- REQ-005 — Travel transition. Acceptance: Travel accepts only 30, 60, 90, or 120 minutes, stores its expiry, uses an Amphetamine timed session, follows the same wake and unlock lifecycle as Night, and reconciles to Off when its backend timer expires.
- REQ-006 — Session and clamshell safety. Acceptance: A stored signature never authorizes a destructive user action. Every manual Work, Night, or Travel start and active-session replacement needs an explicit user choice. An unlock signal is read-only. The saved post-unlock setting selects which confirmation appears first, but it never authorizes a mutation. A new active mode starts only after any replaced session is ended and Off is verified. Work never disables closed-display mode after its session starts. Work normalizes an inactive closed-display default to normal macOS lid behavior without a lid check, because no session is keeping a closed Mac awake; the normalized Amphetamine default also applies to later manual Amphetamine sessions. When an active closed-display session keeps the Mac awake and the lid is not verified open, Work stops before mutation and its error names the mode holding the Mac awake. Relaunch, partial failure, user Quit, and automatic lifecycle handling never silently mutate an unowned session.
- REQ-007 — Native menu and Settings app. Acceptance: The `NSStatusItem` menu, template icon, Settings access, How Modes Work access, countdown, actual mode checkmark, and `SMAppService.mainApp` Launch at Login toggle reflect observed state. Settings uses General, Setup, and Modes toolbar tabs. Developer appears only when Settings opens with Option held. Off reports display and system-sleep blockers as distinct facts; disk-idle blockers appear only in the tooltip. Controller work runs on serial worker queues.
- REQ-008 — Boundary limits. Acceptance: The repository contains no root helper, Accessibility request, direct Amphetamine preference edit, `osascript` process, `pmset disablesleep`, or unrelated external-process termination path.
- REQ-009 — Release artifact. Acceptance: The DMG contains an arm64 and x86_64 app with hardened runtime, LEAD MEDIA AS Developer ID signing, accepted notarization, a staple ticket, and passing Gatekeeper assessment.

### P1

- P1-001: Add thermal state warnings after a supported product contract is defined.
- P1-002: Add a signed update feed after version 1 distribution is proven.

### P2

- P2-001: Evaluate a standalone IOKit backend.
- P2-002: Evaluate task leases for local automation tools.
- P2-003: Evaluate public source and Mac App Store distribution.

## 6. Quality Gates

| Requirement | Command | Exact expected output |
|---|---|---|
| REQ-001 | `Scripts/verify-requirement.sh REQ-001` | `PASS REQ-001` |
| REQ-002 | `Scripts/verify-requirement.sh REQ-002` | `PASS REQ-002` |
| REQ-003 | `Scripts/verify-requirement.sh REQ-003` | `PASS REQ-003` |
| REQ-004 | `Scripts/verify-requirement.sh REQ-004` | `PASS REQ-004` |
| REQ-005 | `Scripts/verify-requirement.sh REQ-005` | `PASS REQ-005` |
| REQ-006 | `Scripts/verify-requirement.sh REQ-006` | `PASS REQ-006` |
| REQ-007 | `Scripts/verify-requirement.sh REQ-007` | `PASS REQ-007` |
| REQ-008 | `Scripts/verify-requirement.sh REQ-008` | `PASS REQ-008` |
| REQ-009 | `Scripts/verify-requirement.sh REQ-009` | `PASS REQ-009` |

Aggregate gates:

```text
swift test --enable-code-coverage
Scripts/verify-coverage.sh
Scripts/verify-app.sh
Scripts/release.sh
Scripts/verify-release.sh
```

## 7. Non-Functional Requirements

- NFR-001: Idle CPU use is below 0.2% over 60 seconds on the owner’s Mac, measured from the change in accumulated user and system CPU time across the measurement window.
- NFR-002: Physical memory footprint is below 50 MB during idle menu-bar operation, measured with macOS `footprint`. RSS is not used because it counts clean shared system-library pages as if every page were private to the app.
- NFR-003: A verified transition finishes within two seconds or reports an explicit error. Every Amphetamine mutation reserves 0.5 seconds of that same deadline for a required verification or recovery read.
- NFR-004: `CaffeineModesCore` line coverage is at least 90%.
- NFR-005: The app supports macOS 13 or later on arm64 and x86_64.
- NFR-006: Menu controls support keyboard navigation and every status symbol has an accessibility description.
- NFR-007: No user data leaves the Mac. Version 1 makes no network request.
- NFR-008: A timed child process reserves cleanup time inside its original deadline. Termination and kill cleanup cannot extend that deadline.
- NFR-009: At most one IOKit assertion inspection can be in flight. A caller joins an existing inspection within its own deadline. If that inspection finishes in time, the joined caller then obtains a fresh snapshot within the same deadline.
- NFR-010: Setup checks, status reads, and mode-transition orchestration execute on serial worker queues. The bounded `NSAppleScript` creation, execution, and reply parsing execute on the main thread because Apple marks that class main-thread-only. No AppleScript descriptor crosses the thread boundary. IOKit inspection, device-policy reads, and fixed process invocations remain off the main thread.
- NFR-011: Screen lifecycle handling is event-driven. It has no idle polling loop. A screen-wake timer covers the 30-second locked-screen window. Each new screen-visibility event can add one 30-second timer after a failed re-sleep. That timer never repeats.

## 8. Constraints

- Swift 6, SwiftPM, AppKit, Foundation, IOKit, and ServiceManagement are the implementation stack.
- Amphetamine 5.3.2 or later is the only power backend.
- `NSAppleScript` is the only Automation mechanism.
- `/usr/bin/pmset displaysleepnow` is the only display-sleep command.
- The current device grace period is the primary screen-lock policy source. On macOS 26 and later, the app reads the same local MobileKeyBag value as Lock Screen settings because `sysadminctl` can report a stale legacy value. Missing or malformed data fails closed. On older systems only, `sysadminctl -screenLock status` is the bounded fallback.
- Signing uses team `D79LWN85PJ` and bundle ID `com.andreaslar.caffeinemodes`.
- Version 1 uses a manually delivered notarized DMG.
- Apple Silicon Night and Travel require Amphetamine Power Protect. The app checks the two documented local installation files without modifying them.
- Architecture dependencies are mirrored in Constraints and Build vs Buy.

## 9. Build vs Buy Decisions

| Capability | Decision | Reason |
|---|---|---|
| Power session backend | Buy/use Amphetamine | It already owns the privileged closed-display setup and timed-session behavior. |
| Menu and Settings UI | Build with AppKit | The interface is small and must reflect the product state model. |
| Login item | Use ServiceManagement | `SMAppService.mainApp` is the supported macOS API. |
| Power assertion inspection | Use IOKit | It provides a read-only process-level source for blockers. |
| Screen-lock policy | Read the local device grace period; use `sysadminctl` only as a pre-macOS-26 fallback | The product must match current Lock Screen settings and fail closed when the policy is not immediate. |
| Updates | Manual DMG | A feed and update framework are deferred until distribution is proven. |
| Analytics | Do not build or buy | Version 1 has no telemetry requirement. |

## 10. Architecture & Tech Decisions

### Modules and boundaries

- `CaffeineModesCore` contains the domain, session-safety rules, transition sequence, and persistence interface. `CaffeineModesCoreTests` tests both core and app-support behavior.
- `CaffeineModesAppSupport` contains testable setup, power-status, menu-selection, and application-termination presentation logic. It has no AppKit dependency.
- `CaffeineModesApp` contains the AppKit UI and macOS adapters.
- `AmphetamineControlling`, `PowerAssertionInspecting`, `ScreenLockPolicyChecking`, `ScreenLockStateInspecting`, `PowerProtectInspecting`, `LidStateInspecting`, `DisplaySleeping`, and `ModeStateStoring` are narrow replaceable seams for verified external boundaries.
- The app does not add extension registries, backend factories, or alternate power logic in version 1.

### Domain vocabulary

- Requested mode: The last mode committed after verification.
- Observed state: The latest normalized Amphetamine values.
- Projected session: An active policy and timer that match the stored session signature. This match is diagnostic. It does not prove session identity.
- Custom: An active session without a matching stored projection.
- Preflight: Read-only checks that run before a transition mutates Amphetamine.
- Verification: A fresh state query after all Amphetamine commands finish.
- Owned command child: A fixed legacy `sysadminctl` or current `pmset` process started with `posix_spawn`. Caffeine Modes keeps exclusive `waitpid` ownership until timeout signaling ends, so the PID cannot be reused. It cannot target any existing process.

### Canonical owners

- Canonical owner: `ModeController` is the only mutator of operating-mode transitions.
- Amphetamine is the system of record for active power assertions.
- `UserDefaultsModeStore` is the system of record for onboarding flags, post-unlock preference, last requested mode, Travel expiry, and the diagnostic session signature only.
- `LaunchAtLoginManager` is the one mutator for login-item registration.
- No business rule has two owners.

### Authority map

| Mutable state or side effect | Read authority | Authoritative mutator |
|---|---|---|
| Active Amphetamine session | Amphetamine query | `ModeController` through `AmphetamineControlling` |
| Requested mode and diagnostic projection | `ModeStateStoring` | `ModeController` after verification |
| Display-sleep request | macOS | `ModeController` through `DisplaySleeping` after verification |
| Launch at Login | `SMAppService.mainApp.status` | `LaunchAtLoginManager` |
| Suggested post-unlock action | `ModeStateStoring` | Settings General tab |
| Developer diagnostic flag | `ModeStateStoring` | Optional closed-lid diagnostic only |

### Changeability and replacement strategy

Each system boundary is replaceable behind one protocol. A future standalone backend can replace `AmphetamineControlling` without changing menu actions or lifecycle rules. No speculative fallback is present; each error is visible and bounded to a verified failure mode.

## 11. Lifecycle / State Model

### States

- Off: No active Amphetamine session.
- Work: Infinite active session, display sleep prevented, closed-display mode disabled.
- Night: Infinite active session, display sleep allowed, closed-display mode enabled.
- Travel: Timed active session, display sleep allowed, closed-display mode enabled, expiry stored.
- Custom: An optional developer diagnostic, an incomplete operation, an unverified state, or an active Amphetamine session without a matching committed Work, Night, or Travel projection.

### Valid transitions and triggers

| From | Trigger | To | Finalizing path |
|---|---|---|---|
| Any active state | User confirms Off | Off | End, query, verify inactive, clear marker |
| Off or active state | User confirms Work | Work | Preflight, verify an open lid before replacing an active closed-display session, end and verify any replaced session, normalize the inactive closed-display default, start, query, commit |
| Off or active state | User confirms Night | Night | Preflight, end and verify any replaced session, start, enable closed-display mode, query, commit, sleep all displays |
| Off or active state | User confirms Travel duration | Travel | Preflight, end and verify any replaced session, timed start, enable closed-display mode, query, commit, sleep all displays |
| Night or Travel | Display wakes but Mac remains locked | Same mode | Arm a 30-second deadline, re-verify mode, ownership, lock state, and display blockers, then request display sleep |
| Night or Travel | Mac unlocks | Same mode until confirmation | Verify unlocked state without mutation, then ask the user to confirm the saved Off or Work suggestion |
| Night or Travel after unlock | User confirms Off or Work | Off or Work | Use the normal confirmed transition path; end and verify the current session before any new session starts |
| Off | User confirms optional Developer diagnostic | Custom with ready health | Verify Off, authorized one-minute start, enable closed-display mode, query, store diagnostic signature |
| Developer diagnostic | Amphetamine timer expires | Off | Reconcile observes inactive and clears marker |
| Travel | Amphetamine timer expires | Off | Reconcile observes inactive and clears marker |
| Projected active state | An observable policy or timer changes | Custom | Reconcile invalidates the projection |
| Any active state | Quit and choose Turn Off and Quit | Off then terminate | End and verify; a failure cancels Quit |
| Any active state | Quit and choose Leave Session Running | Active then terminate | Do not mutate Amphetamine |
| Amphetamine state cannot be inspected | Quit and choose Leave Amphetamine Unchanged and Quit | Unknown then terminate | Do not mutate Amphetamine |
| Amphetamine state cannot be inspected | Quit and choose Cancel | Unknown and app stays open | Do not mutate Amphetamine |
| Any state | Logout, restart, or shutdown | System termination | Exit without reading or mutating Amphetamine and without a prompt |

### Idempotency and recovery

- Reconcile is read-only except for correcting stored projections and stale diagnostic markers.
- Every Work, Night, and Travel selection asks for confirmation before its start command. This authorization remains valid if an Amphetamine session appears between the read-only preflight and the start command.
- Repeating a selection uses the same confirmation, then replaces the active session with the same verified policy.
- A replacement ends the prior session and verifies Off before it starts the new session.
- Work starts only from a verified inactive state whose closed-display default is off. Work never sends a closed-display disable command after its session starts.
- Travel expiry is finalized by Amphetamine, so it survives an app crash.
- After a partial command failure, no display-sleep request runs. The app re-queries and reports Custom/backend mismatch.
- Before a Night or Travel display-sleep request, the app persists a pending-cleanup marker with the observed display policy, closed-display policy, and timer. It promotes that marker only after display sleep succeeds.
- A cleanup projection remains valid only while the display policy, closed-display policy, and expected timer match the stored observation. A mismatch invalidates the projection.
- After a failed Amphetamine session-start, session-end, closed-display, or Trigger command, the app attempts a fresh observation inside the original deadline because an error can follow a partial mutation. Every mutation receives a timeout that reserves 0.5 seconds inside that deadline for verification or recovery. If that reserve is unavailable, the mutation does not start. An unconfirmed start never creates or restores a projection.
- After a start command returns successfully, the app persists a pending-cleanup signature before any later fallible command. A same-deadline recovery observation replaces it only when the state is compatible with the requested start policy.
- Transition recovery uses the original two-second deadline. It never starts a second recovery budget.
- Failed-start and diagnostic recovery use one fresh-observation attempt inside the original deadline. A confirmed start retains a compatible observed pending-cleanup projection when recovery succeeds. If the recovery read cannot finish, it retains the bounded provisional projection written after the confirmed start. An unconfirmed start remains unprojected. The optional diagnostic uses a one-minute Amphetamine timer and leaves it to expire. Its projection anchors expiry to the freshly observed remaining timer after start. It never gates Setup, Night, or Travel.
- A failed user-authorized Quit end command uses the original deadline to re-observe Amphetamine. Verified Off completes Quit. Any active or unobservable result keeps the app open and reports Custom/backend mismatch.
- The Developer diagnostic confirmation states that its timed start may replace an Amphetamine session that appears after the Off check.
- Amphetamine 5.3.2 exposes policy and timer values but no stable session identifier. A stored signature is never destructive authority. Even a matching active state needs confirmation before it can be ended or replaced.
- A relaunch reconstructs the projection from Amphetamine plus the stored signature.

### Forbidden transitions

- Custom cannot be selected as a command.
- Work, Night, Travel, and the Developer diagnostic cannot start without explicit user authorization. No mode starts or ends automatically after unlock.
- No active session can be ended or replaced without an explicit user confirmation.
- Night or Travel cannot start with failed setup, missing required Power Protect, a non-immediate lock policy, or a named external display blocker.
- Work cannot end an active closed-display session that keeps the Mac awake while the lid is not verified open. The user must open the lid first.
- Travel cannot be indefinite or use a duration outside 30, 60, 90, and 120 minutes.
- Quit can leave an active session running. If the user chooses Turn Off and Quit, Quit cannot finish until Off is verified. If session inspection fails, Quit offers only a no-mutation leave-and-quit choice or Cancel.
- Normal termination requests, including external user Quit requests, use the user Quit flow. A power-off notification or an Apple Event reason for logout, restart, or shutdown selects the system route. The system route cannot open a prompt, read Amphetamine, or block logout, restart, or shutdown.

## 12. Data Model

```text
OperatingMode
  off | work | night | travel(durationMinutes, expiresAt) | custom

PostUnlockMode
  off | work

ControlHealth
  ready | amphetamineMissing | unsupportedVersion | automationDenied
  setupIncomplete | conflicted | backendMismatch

ModeSnapshot
  requestedMode
  observedState
  ownershipMarker
  health
  blockingProcesses
  detail
  requiresPostUnlockChoice

PowerAssertionReport
  displaySleepBlockingProcesses
  systemSleepBlockingProcesses
  diskIdleBlockingProcesses

PowerProtectStatus
  isRequired
  isInstalled

OwnedSessionSignature
  id
  mode
  startedAt
  purpose: activeMode | pendingCleanup | readinessTest
  expectedState
  schemaVersion
```

Only `OperatingMode`, `PostUnlockMode`, the diagnostic `OwnedSessionSignature`, and onboarding flags persist. `PostUnlockMode` defaults to Off and selects the suggested confirmed action after unlock. Observed state, health, and `requiresPostUnlockChoice` are live projections. A signature written by version 1.0.0 has no purpose or schema-version field and decodes as a legacy `activeMode`. A matching legacy Travel projection is re-anchored once to Amphetamine's observed remaining timer, then stored in the current format. The migration requires the expected Travel policy and a positive timer no longer than the selected duration. Despite its legacy type name, the signature does not prove identity or authorize an end command.

## 13. Integrations

- Amphetamine: Local Apple Events by bundle ID. Minimum version is 5.3.2.
- Amphetamine Power Protect: Detect Apple Silicon from the runtime host capability, including when the universal app runs through Rosetta. An unreadable capability fails closed and requires Power Protect. Then use read-only local presence checks for the two files documented by Amphetamine. Missing support blocks Night and Travel and links to the official installer project.
- IOKit: Read-only `IOPMCopyAssertionsByProcess` inspection behind the shared transition deadline. Assertion types are classified as display sleep, automatic system sleep, or disk idle. Automatic system sleep includes network-client assertions used for active remote connections. Night and Travel consult only the display list. Off reports non-macOS process names for system and disk assertions and omits temporary macOS service assertions. Display assertions remain visible regardless of owner because they can block the requested screen sleep. One shared in-flight operation prevents worker accumulation after a timeout. A safety-critical caller that receives a joined operation's result then uses a new snapshot taken within the same deadline.
- macOS screen-lock policy: Read-only local device-grace-period query through the Apple-signed MobileKeyBag framework. Zero seconds means immediate. Positive, negative, missing, or malformed values are not accepted as immediate. On macOS 26 and later, the app never trusts `sysadminctl` because its legacy output can disagree with Lock Screen settings. Earlier macOS versions may use bounded, fail-closed `sysadminctl -screenLock status` parsing only when the device-grace-period symbol is unavailable. The private read is acceptable for the Developer ID build but must be reassessed before any Mac App Store work.
- macOS display sleep: Fixed `pmset displaysleepnow` process invocation.
- macOS display and lock lifecycle: `NSWorkspace` screen notifications plus the current `CGSessionCopyCurrentDictionary` lock state. The distributed unlock event starts a read-only verification. The app then asks for explicit confirmation before it uses the normal Off or Work transition.
- ServiceManagement: `SMAppService.mainApp` registration and status.
- GitHub: Private backup repository at `andreasnlarsen/caffeine-modes` after local GitHub CLI authentication.
- Apple notarization: The existing Keychain-backed LEAD MEDIA AS `notarytool` profile named `notchfocus-notary` by default.

## 14. Design System

The native UI follows [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md). It uses San Francisco, semantic macOS colors, a 4-point spacing grid, standard menu and alert controls, template SF Symbols in the running app, and an original Finder icon. Tailwind does not apply to this AppKit product.

## 15. MVP Scope & Milestones

MVP contains REQ-001 through REQ-009 only.

1. Contract and scaffold: REQ-001.
2. Test-first state owner and setup model: REQ-002 through REQ-006.
3. Native UI and boundary verification: REQ-007 and REQ-008.
4. Universal notarized DMG: REQ-009.

## 16. Risks & Unknowns

| Risk | Effect | Mitigation |
|---|---|---|
| Amphetamine changes its scripting dictionary | Commands can fail after an update | Enforce the minimum version, use fixed commands, verify every transition, and report mismatch. |
| Amphetamine does not expose a stable session identifier | A stored policy signature cannot prove which session is active, and a session can appear after preflight | Require confirmation before every start, active-session end, or replacement. Use signatures only for projection and diagnostics. |
| Automation is denied | State cannot be read or changed | Setup performs a read-only request and links to Automation settings. |
| Power Protect is missing on Apple Silicon | Night or Travel can fail after display or power changes with the lid closed | Block Night and Travel, name the missing support, and link to Amphetamine’s official installer project. |
| Another app holds a display assertion | Night or Travel leaves the display awake | Detect and name the process before mutation. |
| IOKit inspection stalls | Repeated refreshes can accumulate blocked workers or a safety transition can inherit an old snapshot | Reuse one in-flight inspection until it completes, then require a joined caller to use a fresh snapshot within its original deadline. |
| Display sleep does not lock due to policy | Screen contents remain visible | Require immediate policy and fail closed on unknown output. |
| Travel runs in an enclosed bag | Heat can rise | Limit duration and show a permanent warning in About and README. |
| Network changes during travel | A task can still lose connectivity | State this limitation; no network-continuity claim exists. |
| Signing certificate or notary profile is absent | REQ-009 cannot pass | The release scripts stop before packaging and name the missing prerequisite. |

## 17. Testing Strategy

- Framework: XCTest with fakes for every external boundary.
- Mandate: Write P0 behavior tests before changing the core transition implementation.
- Coverage: `CaffeineModesCore` line coverage must be at least 90%.
- Unit scope: Command order, safe inactive closed-display normalization, lid-state blocking, Power Protect checks, bounded and fresh blocker inspection, permission denial, missing and old Amphetamine, independent setup deadlines, Triggers, lock policy, invalid Travel durations, Travel countdown rounding, partial failures, optional Developer-diagnostic projection, Custom projection, legacy signature decoding and Travel timer migration, relaunch, expiry, screen wake, read-only unlock handling, identical replacement-session safety, post-unlock Off or Work confirmation, target-specific start and replacement confirmations, user-versus-system termination routing, explicit Quit choices, failed-inspection Quit choices, and Quit failure.
- Static scope: Verify AppKit, IOKit, entitlements, allowed commands, and forbidden mechanisms across every executable project input, including test sources. PATH-resolved and absolute `osascript` calls are rejected. Direct `defaults` executable calls are rejected even when the executable and arguments span multiple lines. Forbidden power arguments are detected across line boundaries. External-process termination spellings are rejected. The only allowed matches are the app's own terminate request and the two exact signals used to stop the child process owned by the bounded runner.
- Build scope: Build both architectures, create one app bundle, and verify the resulting Mach-O slices.
- Release scope: Verify Developer ID signature, team ID, hardened runtime, Gatekeeper, notarization, and staple ticket.
- Live scope: Real mode changes and display sleep are an owner-run acceptance check after the signed build is installed. Automated tests remain read-only.
- Performance scope: `Scripts/verify-performance.sh` measures accumulated CPU time and samples macOS physical memory footprint for 60 seconds. Transition timing is checked during the owner-run acceptance pass.
