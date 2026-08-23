#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
requirement="${1:-}"

run_tests() {
    local filter="$1"
    swift test --disable-sandbox --package-path "$project_root" --filter "$filter" >/dev/null 2>&1
}

case "$requirement" in
    REQ-001)
        test -f "$project_root/Package.swift"
        test -f "$project_root/SPEC.md"
        test -f "$project_root/DESIGN_SYSTEM.md"
        test -f "$project_root/README.md"
        test -d "$project_root/Sources/CaffeineModesCore"
        test -d "$project_root/Sources/CaffeineModesApp"
        test -d "$project_root/Tests/CaffeineModesCoreTests"
        rg -q '\.target\(' "$project_root/Package.swift"
        rg -q '\.executableTarget\(' "$project_root/Package.swift"
        rg -q '\.testTarget\(' "$project_root/Package.swift"
        test -x "$project_root/Scripts/build-app.sh"
        test -x "$project_root/Scripts/release.sh"
        test -x "$project_root/Scripts/verify-release.sh"
        test "$(git -C "$project_root" rev-parse --is-inside-work-tree)" = "true"
        test "$(git -C "$project_root" branch --show-current)" = "main"
        "$project_root/Scripts/verify-spec.sh" >/dev/null 2>&1
        ;;
    REQ-002)
        rg -q 'final class SettingsWindowController' "$project_root/Sources/CaffeineModesApp/SetupWindowController.swift"
        rg -q 'testEverySetupProblemKeepsItsActionOnTheSameRow' "$project_root/Tests/CaffeineModesCoreTests/SetupStatusPresentationTests.swift"
        rg -q 'testDeveloperDiagnosticNeverBlocksSetup' "$project_root/Tests/CaffeineModesCoreTests/SetupStatusPresentationTests.swift"
        rg -q 'testSetupRequiresPowerProtectOnlyWhenTheMacNeedsIt' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testMissingAmphetamineIsDeterministic' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testAutomationDenialIsReported' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testCompletedSetupCloseDeliversOnboardingOnce' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testSetupChecksUseIndependentDeadlines' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testPositiveDeviceGracePeriodIsNotImmediate' "$project_root/Tests/CaffeineModesCoreTests/ScreenLockStatusParserTests.swift"
        rg -q 'testReadinessClosedDisplayPostMutationErrorRetainsObservedCleanupProjection' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testClosedDisplayReadinessAnchorsExpiryAfterDelayedSessionCreation' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testReadinessActivePastExpectedExpiryIsBackendMismatch' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testQuitInspectionRejectsUnsupportedAmphetamineBeforeRead' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testQuitEndRejectsUnsupportedAmphetamineBeforeMutation' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testReadinessClosedDisplayPostMutationErrorRetainsObservedCleanupProjection' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        rg -q 'testDisableTriggersRecoversPostMutationTimeoutWithinOriginalDeadline' "$project_root/Tests/CaffeineModesCoreTests/SetupAndVersionTests.swift"
        run_tests 'SetupAndVersionTests|SetupStatusPresentationTests|ScreenLockStatusParserTests|ApplicationCoordinatorTests/test.*SetupClose'
        run_tests 'ModeControllerTests/testQuit.*UnsupportedAmphetamine'
        ;;
    REQ-003)
        rg -q 'testManualAmphetamineChangeInvalidatesOwnership' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testCustomDetailDescribesProjectionMismatchWithoutOwnershipClaim' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testLegacyTravelProjectionMigratesToObservedBackendTimer' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testDecodesPre101SignatureAsActiveMode' "$project_root/Tests/CaffeineModesCoreTests/UserDefaultsModeStoreTests.swift"
        rg -q 'stateMatchesRequestedMode' "$project_root/Sources/CaffeineModesCore/ModeController.swift"
        run_tests 'ModeControllerTests|UserDefaultsModeStoreTests'
        ;;
    REQ-004)
        rg -q 'testNightChecksPolicyAndBlockersBeforeMutation' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testNightDoesNotBlockOnSystemOrDiskAssertions' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testClassifierSeparatesDisplaySystemAndDiskAssertions' "$project_root/Tests/CaffeineModesCoreTests/PowerStatusPresentationTests.swift"
        rg -q 'testNightSleepsDisplayOnlyAfterAmphetamineVerification' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testJoinedCallerUsesFreshResultWithinOriginalDeadline' "$project_root/Tests/CaffeineModesCoreTests/FreshSingleFlightTests.swift"
        rg -q 'testWakeInNightChecksLockAndArmsThirtySecondResleep' "$project_root/Tests/CaffeineModesCoreTests/AwayModeWakeStateMachineTests.swift"
        rg -q 'testDisplayConfigurationChangeInNightChecksLockAndArmsResleep' "$project_root/Tests/CaffeineModesCoreTests/AwayModeWakeStateMachineTests.swift"
        rg -q 'testLockStateErrorStaysVisibleUntilALifecycleCheckSucceeds' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testResleepFailureStaysVisibleUntilResleepSucceeds' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testLockedNightResleepsAfterFreshVerification' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testUnlockRequiresExplicitChoiceAndDoesNotMutateNight' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testUnlockNeverEndsAnIdenticalReplacementSession' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        run_tests 'ModeControllerTests|AwayModeWakeStateMachineTests|FreshSingleFlightTests|PowerStatusPresentationTests|ApplicationCoordinatorTests/test(LockStateErrorStaysVisibleUntilALifecycleCheckSucceeds|ResleepFailureStaysVisibleUntilResleepSucceeds)'
        ;;
    REQ-005)
        rg -q 'allowedTravelDurations = \[30, 60, 90, 120\]' "$project_root/Sources/CaffeineModesCore/Domain.swift"
        rg -q 'testTravelExpiryReconcilesToOffWhenAmphetamineExpires' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testPostUnlockWorkPreferenceStillRequiresExplicitChoice' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        run_tests 'ModeControllerTests|TravelCountdownFormatterTests'
        ;;
    REQ-006)
        rg -q 'testQuitInspectionReportsActiveWithoutEndingIt' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testPartialFailureDoesNotSleepDisplayAndReportsMismatch' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testStartConfirmationCancelDoesNotRetryTransition' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testActiveSessionReplacementAcceptRetriesWithAuthorization' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testReplacementConfirmationNamesTargetModeAndDisplaySleepEffect' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testTravelStartConfirmationNamesSelectedDuration' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testTravelReplacementConfirmationNamesSelectedDuration' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testEndSessionAndQuitEndsBeforeTermination' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testLeaveSessionRunningQuitsWithoutEndingSession' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testCancelQuitKeepsAppRunningWithoutEndingSession' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testSystemTerminationBypassesReadPromptAndMutation' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testExternalUserQuitUsesPromptedRoute' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testTerminationRouterBypassesPromptOnlyForSystemRequest' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testTerminationClassifierRecognizesOnlyLogoutRestartAndShutdown' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testQuitConfirmationNamesOffInDestructiveChoice' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testUnsupportedAmphetamineQuitCanLeaveUnchangedWithoutMutation' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'testFailedReadQuitCanCancelWithoutMutation' "$project_root/Tests/CaffeineModesCoreTests/ApplicationCoordinatorTests.swift"
        rg -q 'confirmQuitWithoutInspection' "$project_root/Sources/CaffeineModesApp/MenuBarController.swift"
        rg -q 'testQuitInspectionRejectsUnsupportedAmphetamineBeforeRead' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testQuitEndRejectsUnsupportedAmphetamineBeforeMutation' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testQuitRecoversPostMutationTimeoutAndFinalizesVerifiedOff' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'MenuControllerRunner' "$project_root/Sources/CaffeineModesApp/MenuBarController.swift"
        rg -q 'requestQuit()' "$project_root/Sources/CaffeineModesApp/MenuBarController.swift"
        rg -q 'ApplicationTerminationCoordinator' "$project_root/Sources/CaffeineModesApp/main.swift"
        rg -q 'ApplicationTerminationRouter' "$project_root/Sources/CaffeineModesApp/main.swift"
        rg -q 'NSWorkspace.willPowerOffNotification' "$project_root/Sources/CaffeineModesApp/main.swift"
        rg -q 'kAEQuitReason' "$project_root/Sources/CaffeineModesApp/main.swift"
        rg -q 'applicationShouldTerminate' "$project_root/Sources/CaffeineModesApp/main.swift"
        rg -q 'operationTimeout: TimeInterval = 2' "$project_root/Sources/CaffeineModesCore/ModeController.swift"
        rg -q 'mutationRecoveryReserve: TimeInterval = 0.5' "$project_root/Sources/CaffeineModesCore/ModeController.swift"
        rg -q 'testWorkNeverChangesClosedDisplayModeAfterSessionStart' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testWorkBlocksUnsafeClosedLidNormalizationBeforeMutation' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -q 'testUnlockNeverMutatesUnownedCustomSession' "$project_root/Tests/CaffeineModesCoreTests/ModeControllerTests.swift"
        rg -Fq 'with timeout of \(timeoutLiteral) seconds' "$project_root/Sources/CaffeineModesApp/AmphetamineClient.swift"
        run_tests 'ModeControllerTests|ApplicationCoordinatorTests|SetupAndVersionTests/testReadiness.*Mutation'
        ;;
    REQ-007)
        rg -q 'NSStatusBar.system.statusItem' "$project_root/Sources/CaffeineModesApp/MenuBarController.swift"
        rg -q 'SMAppService.mainApp' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
        rg -q 'testOffDistinguishesDisplayAndAutomaticSleepBlockers' "$project_root/Tests/CaffeineModesCoreTests/PowerStatusPresentationTests.swift"
        rg -q 'Settings…' "$project_root/Sources/CaffeineModesApp/MenuBarController.swift"
        rg -q 'How Modes Work…' "$project_root/Sources/CaffeineModesApp/MenuBarController.swift"
        rg -q 'case developer' "$project_root/Sources/CaffeineModesApp/SetupWindowController.swift"
        rg -Fq 'Open + external' "$project_root/Sources/CaffeineModesApp/SetupWindowController.swift"
        run_tests 'PowerStatusPresentationTests|SetupStatusPresentationTests'
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
