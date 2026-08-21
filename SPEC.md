# Caffeine Modes Product Specification

Status: Active implementation contract

Version: 1.0

Last updated: 2026-08-21

## 1. Goal

Caffeine Modes is a native macOS menu-bar app that gives Andreas and trusted friends three clear Amphetamine policies: Work, Night, and bounded Travel. It verifies the external state before it reports success or sleeps the display.

## 2. Non-goals

- NG-001: Caffeine Modes does not replace Amphetamine in version 1.
- NG-002: Caffeine Modes does not keep network connections alive while the Mac changes location or network.
- NG-003: Caffeine Modes does not make enclosed-bag use supported or thermally safe.
- NG-004: Version 1 has no Sparkle updater, Mac App Store build, public download site, analytics, or telemetry.
- NG-005: The app does not change another process, use Accessibility access, or install a privileged helper.

## 3. Target Users

- Primary: Andreas, who uses long-running local work, overnight processing, and short trips between work locations.
- Secondary: Trusted friends who already use, or can install, Amphetamine 5.3.2 or later.
- Environment: A portable Mac on macOS 13 or later.

## 4. User Stories / Behaviors

- As a user, I can select Off and restore normal macOS sleep behavior.
- As a user, I can select Work and keep the Mac and display awake while the lid follows normal behavior.
- As a user, I can select Night and let the display sleep while the Mac stays awake with the lid closed.
- As a user, I can select Travel for 30, 60, 90, or 120 minutes. The session ends in Amphetamine even if Caffeine Modes stops.
- As a user, I see Custom when Amphetamine has a session that Caffeine Modes does not own.
- As a user, I must confirm before Caffeine Modes replaces an unowned session.
- As a user, I see the process name when another app blocks display sleep.
- As a user, I can verify setup and control Launch at Login from the menu.
- As a user, Quit ends an owned session and stays open if Off cannot be verified.

## 5. Requirements

### P0

- REQ-001 — Repository and artifacts. Acceptance: The root contains one active `SPEC.md`, `DESIGN_SYSTEM.md`, `README.md`, SwiftPM app/core/test targets, release scripts, and a git repository on `main`.
- REQ-002 — Guided setup. Acceptance: Setup reports Amphetamine presence and version, Automation access, Trigger state, immediate screen-lock policy, and closed-display readiness as separate deterministic checks.
- REQ-003 — Mode reconciliation. Acceptance: Off, Work, Night, Travel, and Custom are mutually exclusive projections of Amphetamine state plus one stored ownership marker.
- REQ-004 — Night transition. Acceptance: Night blocks named external display assertions before mutation, applies its Amphetamine policy, verifies that policy, and only then requests display sleep.
- REQ-005 — Travel transition. Acceptance: Travel accepts only 30, 60, 90, or 120 minutes, stores its expiry, uses an Amphetamine timed session, and reconciles to Off when that session expires.
- REQ-006 — Ownership and failure. Acceptance: Relaunch, partial failure, manual Amphetamine changes, and Quit do not silently change an unowned session, and an unverifiable mutation appears as Custom with backend mismatch health.
- REQ-007 — Native menu app. Acceptance: The `NSStatusItem` menu, template icon, setup access, countdown, actual mode checkmark, and `SMAppService.mainApp` Launch at Login toggle reflect observed state.
- REQ-008 — Boundary limits. Acceptance: The repository contains no root helper, Accessibility request, direct Amphetamine preference edit, `osascript` process, `pmset disablesleep`, or external-process termination path.
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

- NFR-001: Idle CPU use is below 0.2% over 60 seconds on the owner’s Mac.
- NFR-002: Resident memory is below 50 MB during idle menu-bar operation.
- NFR-003: A verified transition finishes within two seconds or reports an explicit error.
- NFR-004: `CaffeineModesCore` line coverage is at least 90%.
- NFR-005: The app supports macOS 13 or later on arm64 and x86_64.
- NFR-006: Menu controls support keyboard navigation and every status symbol has an accessibility description.
- NFR-007: No user data leaves the Mac. Version 1 makes no network request.

## 8. Constraints

- Swift 6, SwiftPM, AppKit, Foundation, IOKit, and ServiceManagement are the implementation stack.
- Amphetamine 5.3.2 or later is the only power backend.
- `NSAppleScript` is the only Automation mechanism.
- `/usr/bin/pmset displaysleepnow` is the only display-sleep command.
- `/usr/sbin/sysadminctl -screenLock status` is the screen-lock policy query.
- Signing uses team `D79LWN85PJ` and bundle ID `com.andreaslar.caffeinemodes`.
- Version 1 uses a manually delivered notarized DMG.
- Architecture dependencies are mirrored in Constraints and Build vs Buy.

## 9. Build vs Buy Decisions

| Capability | Decision | Reason |
|---|---|---|
| Power session backend | Buy/use Amphetamine | It already owns the privileged closed-display setup and timed-session behavior. |
| Menu and setup UI | Build with AppKit | The interface is small and must reflect the product state model. |
| Login item | Use ServiceManagement | `SMAppService.mainApp` is the supported macOS API. |
| Power assertion inspection | Use IOKit | It provides a read-only process-level source for blockers. |
| Screen-lock policy | Use `sysadminctl` status | The product must fail closed when the policy is not immediate. |
| Updates | Manual DMG | A feed and update framework are deferred until distribution is proven. |
| Analytics | Do not build or buy | Version 1 has no telemetry requirement. |

## 10. Architecture & Tech Decisions

### Modules and boundaries

- `CaffeineModesCore` contains the domain, ownership rules, transition sequence, persistence interface, and tests.
- `CaffeineModesApp` contains the AppKit UI and macOS adapters.
- `AmphetamineControlling`, `PowerAssertionInspecting`, `ScreenLockPolicyChecking`, `DisplaySleeping`, and `ModeStateStoring` are narrow replaceable seams for verified external boundaries.
- The app does not add extension registries, backend factories, or alternate power logic in version 1.

### Domain vocabulary

- Requested mode: The last mode committed after verification.
- Observed state: The latest normalized Amphetamine values.
- Owned session: An active state that matches the stored owned-session signature.
- Custom: An active session without a matching ownership signature.
- Preflight: Read-only checks that run before a transition mutates Amphetamine.
- Verification: A fresh state query after all Amphetamine commands finish.

### Canonical owners

- Canonical owner: `ModeController` is the only mutator of operating-mode transitions.
- Amphetamine is the system of record for active power assertions.
- `UserDefaultsModeStore` is the system of record for onboarding flags, last requested mode, Travel expiry, and the ownership signature only.
- `LaunchAtLoginManager` is the one mutator for login-item registration.
- No business rule has two owners.

### Authority map

| Mutable state or side effect | Read authority | Authoritative mutator |
|---|---|---|
| Active Amphetamine session | Amphetamine query | `ModeController` through `AmphetamineControlling` |
| Requested mode and ownership | `ModeStateStoring` | `ModeController` after verification |
| Display-sleep request | macOS | `ModeController` through `DisplaySleeping` after verification |
| Launch at Login | `SMAppService.mainApp.status` | `LaunchAtLoginManager` |
| Setup readiness flag | `ModeStateStoring` | Closed-display readiness test only |

### Changeability and replacement strategy

Each system boundary is replaceable behind one protocol. A future standalone backend can replace `AmphetamineControlling` without changing menu actions or lifecycle rules. No speculative fallback is present; each error is visible and bounded to a verified failure mode.

## 11. Lifecycle / State Model

### States

- Off: No active Amphetamine session.
- Work: Infinite active session, display sleep prevented, closed-display mode disabled.
- Night: Infinite active session, display sleep allowed, closed-display mode enabled.
- Travel: Timed active session, display sleep allowed, closed-display mode enabled, expiry stored.
- Custom: Active Amphetamine state without matching ownership.

### Valid transitions and triggers

| From | Trigger | To | Finalizing path |
|---|---|---|---|
| Any owned state | User selects Off | Off | End, query, verify inactive, clear marker |
| Off or confirmed Custom | User selects Work | Work | Preflight, start, normalize closed-display policy, query, commit |
| Off or confirmed Custom | User selects Night | Night | Preflight, start, normalize, query, commit, sleep display |
| Off or confirmed Custom | User selects Travel duration | Travel | Preflight, start timed session, normalize, query, commit, sleep display |
| Travel | Amphetamine timer expires | Off | Reconcile observes inactive and clears marker |
| Owned active state | User or another tool changes Amphetamine | Custom | Reconcile invalidates marker |
| Owned active state | Quit | Off then terminate | End and verify; a failure cancels Quit |
| Custom | Quit | Custom then terminate | Do not mutate Amphetamine |

### Idempotency and recovery

- Reconcile is read-only except for correcting stored projections and stale ownership markers.
- Repeating a selection replaces the owned session with the same verified policy.
- Travel expiry is finalized by Amphetamine, so it survives an app crash.
- After a partial command failure, no display-sleep request runs. The app re-queries and reports Custom/backend mismatch.
- A relaunch reconstructs the projection from Amphetamine plus the stored signature.

### Forbidden transitions

- Custom cannot be selected as a command.
- An unowned Custom session cannot be replaced without an explicit user confirmation.
- Night or Travel cannot start with failed setup, a non-immediate lock policy, or a named external display blocker.
- Travel cannot be indefinite or use a duration outside 30, 60, 90, and 120 minutes.
- Quit cannot finish while an owned session remains active.

## 12. Data Model

```text
OperatingMode
  off | work | night | travel(durationMinutes, expiresAt) | custom

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

OwnedSessionSignature
  id
  mode
  startedAt
```

Only `OperatingMode`, `OwnedSessionSignature`, and onboarding flags persist. Observed state and health are live projections.

## 13. Integrations

- Amphetamine: Local Apple Events by bundle ID. Minimum version is 5.3.2.
- IOKit: Read-only `IOPMCopyAssertionsByProcess` inspection.
- macOS screen-lock policy: Read-only `sysadminctl -screenLock status` parsing. Unknown output fails closed.
- macOS display sleep: Fixed `pmset displaysleepnow` process invocation.
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

> **Codebase Health Scan**
> Greenfield — no existing code to scan.

## 16. Risks & Unknowns

| Risk | Effect | Mitigation |
|---|---|---|
| Amphetamine changes its scripting dictionary | Commands can fail after an update | Enforce the minimum version, use fixed commands, verify every transition, and report mismatch. |
| Automation is denied | State cannot be read or changed | Setup performs a read-only request and links to Automation settings. |
| Closed-display support needs Amphetamine setup | Night or Travel cannot meet the lid-close policy | Require an explicit bounded readiness test and show Amphetamine’s own prompts. |
| Another app holds a display assertion | Night or Travel leaves the display awake | Detect and name the process before mutation. |
| Display sleep does not lock due to policy | Screen contents remain visible | Require immediate policy and fail closed on unknown output. |
| Travel runs in an enclosed bag | Heat can rise | Limit duration and show a permanent warning in About and README. |
| Network changes during travel | A task can still lose connectivity | State this limitation; no network-continuity claim exists. |
| Signing certificate or notary profile is absent | REQ-009 cannot pass | The release scripts stop before packaging and name the missing prerequisite. |

## 17. Testing Strategy

- Framework: XCTest with fakes for every external boundary.
- Mandate: Write P0 behavior tests before changing the core transition implementation.
- Coverage: `CaffeineModesCore` line coverage must be at least 90%.
- Unit scope: Command order, normalized closed-display semantics, blockers, permission denial, missing and old Amphetamine, Triggers, lock policy, invalid Travel durations, partial failures, Custom ownership, relaunch, expiry, and Quit failure.
- Static scope: Verify AppKit, IOKit, entitlements, allowed commands, and forbidden mechanisms.
- Build scope: Build both architectures, create one app bundle, and verify the resulting Mach-O slices.
- Release scope: Verify Developer ID signature, team ID, hardened runtime, Gatekeeper, notarization, and staple ticket.
- Live scope: Real mode changes and display sleep are an owner-run acceptance check after the signed build is installed. Automated tests remain read-only.
- Performance scope: `Scripts/verify-performance.sh` samples CPU and resident memory for 60 seconds. Transition timing is checked during the owner-run acceptance pass.
