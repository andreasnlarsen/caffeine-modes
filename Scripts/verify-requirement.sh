#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
requirement="${1:-}"

case "$requirement" in
    REQ-001)
        test -f "$project_root/Package.swift"
        test -f "$project_root/SPEC.md"
        test -f "$project_root/DESIGN_SYSTEM.md"
        test -f "$project_root/README.md"
        "$project_root/Scripts/verify-spec.sh" >/dev/null 2>&1
        ;;
    REQ-002)
        rg -q 'final class SetupWindowController' "$project_root/Sources/CaffeineModesApp/SetupWindowController.swift"
        rg -q 'testMissingAmphetamineIsDeterministic' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testAutomationDenialIsReported' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        ;;
    REQ-003)
        rg -q 'testManualAmphetamineChangeInvalidatesOwnership' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'stateMatchesRequestedMode' "$project_root/Sources/CaffeineModesCore/ModeController.swift"
        ;;
    REQ-004)
        rg -q 'testNightChecksPolicyAndBlockersBeforeMutation' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testNightSleepsDisplayOnlyAfterAmphetamineVerification' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        ;;
    REQ-005)
        rg -q 'allowedTravelDurations = \[30, 60, 90, 120\]' "$project_root/Sources/CaffeineModesCore/Domain.swift"
        rg -q 'testTravelExpiryReconcilesToOffWhenAmphetamineExpires' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        ;;
    REQ-006)
        rg -q 'testQuitDoesNotEndUnownedCustomSession' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testPartialFailureDoesNotSleepDisplayAndReportsMismatch' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        ;;
    REQ-007)
        rg -q 'NSStatusBar.system.statusItem' "$project_root/Sources/CaffeineModesApp/MenuBarController.swift"
        rg -q 'SMAppService.mainApp' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
        "$project_root/Scripts/verify-app.sh" >/dev/null 2>&1
        ;;
    REQ-008)
        "$project_root/Scripts/verify-safety.sh" >/dev/null 2>&1
        ;;
    REQ-009)
        "$project_root/Scripts/verify-release.sh" >/dev/null 2>&1
        ;;
    *)
        print -u2 "Usage: Scripts/verify-requirement.sh REQ-001 through REQ-009"
        exit 64
        ;;
esac

printf 'PASS %s\n' "$requirement"
