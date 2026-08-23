import CaffeineModesAppSupport
import CaffeineModesCore
import Foundation
import XCTest

@MainActor
final class ApplicationCoordinatorTests: XCTestCase {
    func testMainThreadExecutorRunsInlineOnMainThread() {
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(MainThreadExecutor.run { Thread.isMainThread })
    }

    func testMainThreadExecutorMarshalsWorkerOperationToMainThread() async {
        let ranOnMainThread = await Task.detached {
            MainThreadExecutor.run { Thread.isMainThread }
        }.value

        XCTAssertTrue(ranOnMainThread)
    }

    func testCompletedSetupCloseDeliversOnboardingOnce() {
        var coordinator = SetupCompletionCoordinator()
        coordinator.update(isComplete: true)

        XCTAssertTrue(coordinator.consumeCompletionForClose())
        XCTAssertFalse(coordinator.consumeCompletionForClose())
    }

    func testIncompleteSetupCloseDoesNotDeliverOnboarding() {
        var coordinator = SetupCompletionCoordinator()
        coordinator.update(isComplete: false)

        XCTAssertFalse(coordinator.consumeCompletionForClose())
    }

    func testSetupRefreshInvalidatesEarlierCompletionUntilFreshResultArrives() {
        var coordinator = SetupCompletionCoordinator()
        coordinator.update(isComplete: true)

        coordinator.beginRefresh()
        coordinator.noteCloseDuringRefresh()
        XCTAssertFalse(coordinator.consumeCompletionForClose())

        coordinator.update(isComplete: true)
        XCTAssertTrue(coordinator.consumeCompletionAfterRefresh())
        XCTAssertFalse(coordinator.consumeCompletionAfterRefresh())
    }

    func testIncompleteResultClearsPendingSetupCloseWithoutLaterDelivery() {
        var coordinator = SetupCompletionCoordinator()
        coordinator.beginRefresh()
        coordinator.noteCloseDuringRefresh()

        coordinator.update(isComplete: false)
        XCTAssertFalse(coordinator.consumeCompletionAfterRefresh())

        coordinator.update(isComplete: true)
        XCTAssertFalse(coordinator.consumeCompletionAfterRefresh())
    }

    func testStatusRefreshDisablesQuitButKeepsModeSelectionAvailable() {
        let activity = MenuActivityPolicy(
            setupIsBusy: false,
            transitionIsInProgress: false,
            refreshIsInProgress: true
        )

        XCTAssertTrue(activity.modesAreEnabled)
        XCTAssertFalse(activity.quitIsEnabled)
        XCTAssertTrue(activity.hasControllerWorkInProgress)
    }

    func testTransitionRejectsOlderRefreshResultsAndPreservesItsMenuStatus() {
        let activity = MenuActivityPolicy(
            setupIsBusy: false,
            transitionIsInProgress: true,
            refreshIsInProgress: true
        )

        XCTAssertFalse(activity.acceptsRefreshResults)
        XCTAssertEqual(activity.menuOpenBehavior, .preserveCurrentStatus)
    }

    func testSetupBusyUsesItsOwnMenuStatus() {
        let activity = MenuActivityPolicy(
            setupIsBusy: true,
            transitionIsInProgress: false,
            refreshIsInProgress: false
        )

        XCTAssertEqual(activity.menuOpenBehavior, .showSetupBusy)
        XCTAssertFalse(activity.acceptsRefreshResults)
    }

    func testDeferredStatusRefreshRetriesAfterBusyWorkFinishes() {
        var coordinator = RefreshRequestCoordinator()

        XCTAssertFalse(coordinator.request(blocked: true))
        XCTAssertTrue(coordinator.request(blocked: false))
        XCTAssertTrue(coordinator.isInProgress)
        XCTAssertFalse(coordinator.finish())

        XCTAssertTrue(coordinator.request(blocked: false))
        XCTAssertFalse(coordinator.request(blocked: false))
        XCTAssertTrue(coordinator.finish())
    }

    func testPostUnlockChoiceWaitsForBusyWorkThenPresentsOnce() {
        var state = PostUnlockChoiceState()
        let ownershipID = UUID()
        var preparationCount = 0

        state.request(for: ownershipID)

        XCTAssertEqual(state.activeOwnershipID, ownershipID)
        XCTAssertNil(
            state.presentationIfReady(
                isBusy: true,
                prepareForPresentation: { preparationCount += 1 }
            )
        )
        XCTAssertEqual(
            state.presentationIfReady(
                isBusy: false,
                prepareForPresentation: { preparationCount += 1 }
            ),
            ownershipID
        )
        XCTAssertNil(
            state.presentationIfReady(
                isBusy: false,
                prepareForPresentation: { preparationCount += 1 }
            )
        )
        XCTAssertEqual(preparationCount, 1)
    }

    func testPostUnlockChoiceClearsAfterCancelOrModeChange() {
        var state = PostUnlockChoiceState()
        let ownershipID = UUID()

        state.request(for: ownershipID)
        XCTAssertEqual(state.presentationIfReady(isBusy: false), ownershipID)
        state.cancelPresentation(for: ownershipID)
        XCTAssertNil(state.activeOwnershipID)

        state.request(for: ownershipID)
        state.modeDidChange(awayOwnershipID: UUID())
        XCTAssertNil(state.activeOwnershipID)
    }

    func testPostUnlockTransitionFailureKeepsWarningUntilAnotherEventRetries() {
        var state = PostUnlockChoiceState()
        let ownershipID = UUID()

        state.request(for: ownershipID)
        XCTAssertEqual(state.presentationIfReady(isBusy: false), ownershipID)

        state.transitionFailed(for: ownershipID)

        XCTAssertEqual(state.activeOwnershipID, ownershipID)
        XCTAssertNil(state.presentationIfReady(isBusy: false))

        state.request(for: ownershipID)
        XCTAssertEqual(state.presentationIfReady(isBusy: false), ownershipID)
    }

    func testPostUnlockPresentationWaitsForEveryModalSource() {
        XCTAssertFalse(
            PostUnlockPresentationPolicy.isBusy(
                setupIsBusy: false,
                transitionIsInProgress: false,
                modalWindowIsOpen: false
            )
        )
        XCTAssertTrue(
            PostUnlockPresentationPolicy.isBusy(
                setupIsBusy: true,
                transitionIsInProgress: false,
                modalWindowIsOpen: false
            )
        )
        XCTAssertTrue(
            PostUnlockPresentationPolicy.isBusy(
                setupIsBusy: false,
                transitionIsInProgress: true,
                modalWindowIsOpen: false
            )
        )
        XCTAssertTrue(
            PostUnlockPresentationPolicy.isBusy(
                setupIsBusy: false,
                transitionIsInProgress: false,
                modalWindowIsOpen: true
            )
        )
    }

    func testScreenLifecycleActivityRejectsOverlappingWorkAndReportsBusy() {
        var activity = ScreenLifecycleActivity()

        XCTAssertTrue(activity.begin())
        XCTAssertTrue(activity.isBusy)
        XCTAssertFalse(activity.begin())

        XCTAssertEqual(activity.finishOtherWork(awayModeIsActive: false), .none)
        XCTAssertFalse(activity.isBusy)
        XCTAssertTrue(activity.begin())
    }

    func testScreenLifecycleActivityQueuesUnlockCheckDuringOtherWork() {
        var activity = ScreenLifecycleActivity()

        XCTAssertTrue(activity.begin())
        XCTAssertFalse(activity.requestUnlockCheck())
        XCTAssertEqual(
            activity.finishOtherWork(awayModeIsActive: true),
            .checkUnlockNow
        )
        XCTAssertFalse(activity.isBusy)
        XCTAssertTrue(activity.requestUnlockCheck())
    }

    func testVerifiedUnlockClearsQueuedLifecycleWork() {
        var activity = ScreenLifecycleActivity()

        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertFalse(activity.requestUnlockCheck())
        XCTAssertFalse(activity.requestResleep())

        activity.verifiedUnlockObserved()

        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: true, awayModeIsActive: true),
            .none
        )
        XCTAssertFalse(activity.isBusy)
    }

    func testScreenLifecycleActivityQueuesResleepDuringUnlockCheck() {
        var activity = ScreenLifecycleActivity()

        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertFalse(activity.requestResleep())
        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: true, awayModeIsActive: true),
            .resleepNow
        )
        XCTAssertFalse(activity.isBusy)
        XCTAssertTrue(activity.requestResleep())
    }

    func testScreenLifecycleActivityRetriesFailedResleepOnlyOnce() {
        var activity = ScreenLifecycleActivity(maximumResleepRetries: 1)

        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .retryResleepAfterDelay
        )

        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .none
        )
    }

    func testScreenLifecycleActivityClearsResleepRetryWhenAwayModeEnds() {
        var activity = ScreenLifecycleActivity(maximumResleepRetries: 1)

        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .retryResleepAfterDelay
        )
        activity.modeDidChange(awayModeIsActive: false)

        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .retryResleepAfterDelay
        )
    }

    func testScreenLifecycleActivityClearsResleepRetryAfterSuccess() {
        var activity = ScreenLifecycleActivity(maximumResleepRetries: 1)

        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .retryResleepAfterDelay
        )
        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: true, awayModeIsActive: true),
            .none
        )

        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .retryResleepAfterDelay
        )
    }

    func testScreenLifecycleActivityResetsRetryBudgetsForNewDisplayEvent() {
        var activity = ScreenLifecycleActivity(
            maximumUnlockRetries: 1,
            maximumResleepRetries: 1
        )

        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: false, awayModeIsActive: true),
            .retryUnlockAfterDelay
        )
        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: false, awayModeIsActive: true),
            .none
        )
        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .retryResleepAfterDelay
        )
        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .none
        )

        activity.beginDisplayVisibilityEvent()

        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: false, awayModeIsActive: true),
            .retryUnlockAfterDelay
        )
        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .retryResleepAfterDelay
        )
    }

    func testScreenLifecycleActivityResetsOnlyUnlockBudgetForNewUnlockEvent() {
        var activity = ScreenLifecycleActivity(
            maximumUnlockRetries: 1,
            maximumResleepRetries: 1
        )

        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: false, awayModeIsActive: true),
            .retryUnlockAfterDelay
        )
        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: false, awayModeIsActive: true),
            .none
        )
        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .retryResleepAfterDelay
        )
        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .none
        )

        activity.beginUnlockEvent()

        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: false, awayModeIsActive: true),
            .retryUnlockAfterDelay
        )
        XCTAssertTrue(activity.requestResleep())
        XCTAssertEqual(
            activity.finishResleep(succeeded: false, awayModeIsActive: true),
            .none
        )
    }

    func testScreenLifecycleActivityBoundsFailedUnlockRetries() {
        var activity = ScreenLifecycleActivity(maximumUnlockRetries: 2)

        for _ in 0..<2 {
            XCTAssertTrue(activity.requestUnlockCheck())
            XCTAssertEqual(
                activity.finishUnlockCheck(succeeded: false, awayModeIsActive: true),
                .retryUnlockAfterDelay
            )
        }
        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: false, awayModeIsActive: true),
            .none
        )
    }

    func testScreenLifecycleActivityClearsQueuedUnlockWhenAwayModeEnds() {
        var activity = ScreenLifecycleActivity()

        XCTAssertTrue(activity.begin())
        XCTAssertFalse(activity.requestUnlockCheck())
        activity.modeDidChange(awayModeIsActive: false)

        XCTAssertEqual(activity.finishOtherWork(awayModeIsActive: false), .none)
    }

    func testScreenLifecycleActivityClearsQueuedResleepWhenAwayModeEnds() {
        var activity = ScreenLifecycleActivity()

        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertFalse(activity.requestResleep())
        activity.modeDidChange(awayModeIsActive: false)

        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: true, awayModeIsActive: false),
            .none
        )
    }

    func testScreenLifecycleActivityClearsOldQueuedWorkWhenAwayOwnershipChanges() {
        var activity = ScreenLifecycleActivity()

        XCTAssertTrue(activity.requestUnlockCheck())
        XCTAssertFalse(activity.requestResleep())
        activity.modeDidChange(awayModeIsActive: true, identityChanged: true)

        XCTAssertEqual(
            activity.finishUnlockCheck(succeeded: true, awayModeIsActive: true),
            .none
        )
    }

    func testLifecyclePolicyPreservesTransientFailuresAndRetiresConfirmedProjectionLoss() {
        let healthy = Self.snapshot(.night)
        let transientFailure = ModeSnapshot(
            requestedMode: .custom,
            observedState: nil,
            ownershipMarker: nil,
            health: .backendMismatch,
            detail: "Temporary read failure"
        )
        let confirmedProjectionLoss = ModeSnapshot(
            requestedMode: .custom,
            observedState: .inactive,
            ownershipMarker: nil,
            health: .conflicted,
            detail: "Amphetamine changed outside Caffeine Modes"
        )

        XCTAssertTrue(LifecycleObservationPolicy.accepts(healthy))
        XCTAssertFalse(LifecycleObservationPolicy.accepts(transientFailure))
        XCTAssertTrue(LifecycleObservationPolicy.accepts(confirmedProjectionLoss))
    }

    func testLifecycleErrorIsShownBeforeHealthyRefreshClearsIt() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state = LifecycleErrorState()
        state.record("Unlock failed", at: started)

        state.refresh(
            snapshot: Self.snapshot(.off),
            report: .empty,
            now: started.addingTimeInterval(30)
        )
        XCTAssertEqual(state.message, "Unlock failed")

        state.markPresented()
        state.refresh(
            snapshot: Self.snapshot(.off),
            report: .empty,
            now: started.addingTimeInterval(4)
        )
        XCTAssertEqual(state.message, "Unlock failed")

        state.refresh(
            snapshot: Self.snapshot(.off),
            report: .empty,
            now: started.addingTimeInterval(5)
        )
        XCTAssertNil(state.message)
    }

    func testSuccessfulLifecycleCompletionDoesNotClearRecentFailure() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state = LifecycleErrorState()
        state.recordFailure("Work could not start", at: started)

        state.recordFailure(nil, at: started.addingTimeInterval(1))

        XCTAssertEqual(state.message, "Work could not start")
    }

    func testLifecycleErrorStaysVisibleWhileAwayDisplayIsStillBlocked() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state = LifecycleErrorState()
        state.record("Display sleep is blocked", at: started)
        state.markPresented()

        state.refresh(
            snapshot: Self.snapshot(.night),
            report: PowerAssertionReport(displaySleepBlockingProcesses: ["Raycast"]),
            now: started.addingTimeInterval(30)
        )
        XCTAssertEqual(state.message, "Display sleep is blocked")

        state.refresh(
            snapshot: Self.snapshot(.night),
            report: .empty,
            now: started.addingTimeInterval(31)
        )
        XCTAssertNil(state.message)
    }

    func testLockStateErrorStaysVisibleUntilALifecycleCheckSucceeds() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state = LifecycleErrorState()
        state.record(
            "macOS did not return the current lock state.",
            at: started,
            requiresSuccessfulLifecycleCheck: true
        )
        state.markPresented()

        state.refresh(
            snapshot: Self.snapshot(.night),
            report: .empty,
            now: started.addingTimeInterval(30)
        )
        XCTAssertNotNil(state.message)

        state.noteSuccessfulLifecycleCheck()
        state.refresh(
            snapshot: Self.snapshot(.night),
            report: .empty,
            now: started.addingTimeInterval(31)
        )
        XCTAssertNil(state.message)
    }

    func testLockStateErrorRetiresAfterTravelExpiresToOff() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state = LifecycleErrorState()
        state.record(
            "macOS did not return the current lock state.",
            at: started,
            requiresSuccessfulLifecycleCheck: true
        )
        state.markPresented()

        state.refresh(
            snapshot: Self.snapshot(.off),
            report: .empty,
            now: started.addingTimeInterval(30)
        )

        XCTAssertNil(state.message)
    }

    func testResleepFailureStaysVisibleUntilResleepSucceeds() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state = LifecycleErrorState()
        state.record(
            "Display sleep is blocked",
            at: started,
            requiresSuccessfulResleep: true
        )
        state.markPresented()

        state.refresh(
            snapshot: Self.snapshot(.night),
            report: .empty,
            now: started.addingTimeInterval(30)
        )
        XCTAssertNotNil(state.message)

        state.noteSuccessfulLifecycleCheck()
        state.refresh(
            snapshot: Self.snapshot(.night),
            report: .empty,
            now: started.addingTimeInterval(31)
        )
        XCTAssertNotNil(state.message)

        state.noteSuccessfulResleep()
        state.refresh(
            snapshot: Self.snapshot(.night),
            report: .empty,
            now: started.addingTimeInterval(32)
        )
        XCTAssertNil(state.message)
    }

    func testLifecycleErrorRetiresAfterConfirmedOwnershipConflict() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        var state = LifecycleErrorState()
        state.record("Display sleep is blocked", at: started)
        state.markPresented()

        state.refresh(
            snapshot: ModeSnapshot(
                requestedMode: .custom,
                observedState: .inactive,
                ownershipMarker: nil,
                health: .conflicted,
                detail: "Amphetamine changed outside Caffeine Modes"
            ),
            report: .empty,
            now: started.addingTimeInterval(30)
        )

        XCTAssertNil(state.message)
    }

    func testStartConfirmationCancelDoesNotRetryTransition() async throws {
        var authorizations: [Bool] = []
        var confirmations: [ModeSelectionConfirmation] = []
        let coordinator = ModeSelectionCoordinator(
            transition: { _, authorization in
                authorizations.append(authorization)
                throw ModeControlError.sessionStartRequiresConfirmation
            },
            confirm: { reason in
                confirmations.append(reason)
                return false
            }
        )

        let result = try await coordinator.select(.work)
        XCTAssertNil(result)
        XCTAssertEqual(authorizations, [false])
        XCTAssertEqual(confirmations, [.start(.work)])
    }

    func testStartConfirmationAcceptRetriesWithAuthorization() async throws {
        var authorizations: [Bool] = []
        var confirmations: [ModeSelectionConfirmation] = []
        let coordinator = ModeSelectionCoordinator(
            transition: { mode, authorization in
                authorizations.append(authorization)
                if !authorization {
                    throw ModeControlError.sessionStartRequiresConfirmation
                }
                return Self.snapshot(mode)
            },
            confirm: { reason in
                confirmations.append(reason)
                return true
            }
        )

        let result = try await coordinator.select(.night)
        XCTAssertEqual(result, Self.snapshot(.night))
        XCTAssertEqual(authorizations, [false, true])
        XCTAssertEqual(confirmations, [.start(.night)])
    }

    func testActiveSessionReplacementCancelDoesNotRetryTransition() async throws {
        var authorizations: [Bool] = []
        let coordinator = ModeSelectionCoordinator(
            transition: { _, authorization in
                authorizations.append(authorization)
                throw ModeControlError.activeSessionRequiresConfirmation
            },
            confirm: { reason in
                XCTAssertEqual(reason, .replaceActiveSession(.off))
                return false
            }
        )

        let result = try await coordinator.select(.off)
        XCTAssertNil(result)
        XCTAssertEqual(authorizations, [false])
    }

    func testActiveSessionReplacementAcceptRetriesWithAuthorization() async throws {
        var authorizations: [Bool] = []
        let coordinator = ModeSelectionCoordinator(
            transition: { mode, authorization in
                authorizations.append(authorization)
                if !authorization {
                    throw ModeControlError.activeSessionRequiresConfirmation
                }
                return Self.snapshot(mode)
            },
            confirm: { reason in
                XCTAssertEqual(reason, .replaceActiveSession(.work))
                return true
            }
        )

        let result = try await coordinator.select(.work)
        XCTAssertEqual(result, Self.snapshot(.work))
        XCTAssertEqual(authorizations, [false, true])
    }

    func testReplacementConfirmationNamesTargetModeAndDisplaySleepEffect() {
        let night = ModeSelectionConfirmation.replaceActiveSession(.night).presentation
        XCTAssertTrue(night.title.contains("Night"))
        XCTAssertTrue(night.message.contains("Night"))
        XCTAssertTrue(night.message.contains("All connected displays will turn off now. Your Mac will lock."))
        XCTAssertEqual(night.confirmButtonTitle, "Start Night")

        let work = ModeSelectionConfirmation.replaceActiveSession(.work).presentation
        XCTAssertTrue(work.title.contains("Work"))
        XCTAssertTrue(work.message.contains("Work"))
        XCTAssertEqual(work.confirmButtonTitle, "Start Work")

    }

    func testTravelStartConfirmationNamesSelectedDuration() {
        let confirmation = ModeSelectionConfirmation.start(
            .travel(durationMinutes: 90, expiresAt: Date())
        ).presentation

        XCTAssertEqual(confirmation.title, "Start Travel for 90 Minutes?")
        XCTAssertTrue(confirmation.message.contains("All connected displays will turn off now. Your Mac will lock."))
        XCTAssertEqual(confirmation.confirmButtonTitle, "Start Travel for 90 Minutes")
    }

    func testTravelReplacementConfirmationNamesSelectedDuration() {
        let confirmation = ModeSelectionConfirmation.replaceActiveSession(
            .travel(durationMinutes: 30, expiresAt: Date())
        ).presentation

        XCTAssertEqual(
            confirmation.title,
            "Replace the Current Session and Start Travel for 30 Minutes?"
        )
        XCTAssertTrue(confirmation.message.contains("Travel for 30 Minutes"))
        XCTAssertTrue(confirmation.message.contains("All connected displays will turn off now. Your Mac will lock."))
        XCTAssertEqual(confirmation.confirmButtonTitle, "Start Travel for 30 Minutes")
    }

    func testUnexpectedModeErrorDoesNotAskForConfirmation() async {
        var confirmationCount = 0
        let coordinator = ModeSelectionCoordinator(
            transition: { _, _ in throw ModeControlError.automationDenied },
            confirm: { _ in
                confirmationCount += 1
                return true
            }
        )

        do {
            _ = try await coordinator.select(.work)
            XCTFail("Expected Automation denial")
        } catch {
            XCTAssertEqual(error as? ModeControlError, .automationDenied)
        }
        XCTAssertEqual(confirmationCount, 0)
    }

    func testQuitWithoutActiveSessionTerminatesWithoutPromptOrMutation() throws {
        var promptCount = 0
        var endCount = 0
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveSession: { false },
            endActiveSession: { endCount += 1 },
            choose: {
                promptCount += 1
                return .cancel
            }
        )

        XCTAssertEqual(try coordinator.decision(), .terminateNow)
        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(endCount, 0)
    }

    func testSystemTerminationBypassesReadPromptAndMutation() throws {
        var inspectionCount = 0
        var promptCount = 0
        var endCount = 0
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveSession: {
                inspectionCount += 1
                return true
            },
            endActiveSession: { endCount += 1 },
            choose: {
                promptCount += 1
                return .endAndQuit
            }
        )

        XCTAssertEqual(
            try coordinator.decision(for: .system),
            .terminateNow
        )
        XCTAssertEqual(inspectionCount, 0)
        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(endCount, 0)
    }

    func testExternalUserQuitUsesPromptedRoute() throws {
        var inspectionCount = 0
        var promptCount = 0
        let router = ApplicationTerminationRouter(
            coordinator: ApplicationTerminationCoordinator(
                hasActiveSession: {
                    inspectionCount += 1
                    return true
                },
                endActiveSession: {},
                choose: {
                    promptCount += 1
                    return .leaveRunning
                }
            )
        )

        XCTAssertEqual(try router.decision(), .terminateNow)
        XCTAssertEqual(inspectionCount, 1)
        XCTAssertEqual(promptCount, 1)
    }

    func testTerminationRouterBypassesPromptOnlyForSystemRequest() throws {
        var inspectionCount = 0
        var promptCount = 0
        let router = ApplicationTerminationRouter(
            coordinator: ApplicationTerminationCoordinator(
                hasActiveSession: {
                    inspectionCount += 1
                    return true
                },
                endActiveSession: {},
                choose: {
                    promptCount += 1
                    return .leaveRunning
                }
            )
        )

        XCTAssertEqual(try router.decision(for: .system), .terminateNow)
        XCTAssertEqual(inspectionCount, 0)
        XCTAssertEqual(promptCount, 0)
    }

    func testTerminationClassifierRecognizesOnlyLogoutRestartAndShutdown() {
        XCTAssertEqual(
            ApplicationTerminationClassifier.request(
                systemWillPowerOff: true,
                appleEventQuitReason: nil
            ),
            .system
        )
        for reason: UInt32 in [0x7368_7574, 0x7265_7374, 0x726c_676f] {
            XCTAssertEqual(
                ApplicationTerminationClassifier.request(
                    systemWillPowerOff: false,
                    appleEventQuitReason: reason
                ),
                .system
            )
        }
        XCTAssertEqual(
            ApplicationTerminationClassifier.request(
                systemWillPowerOff: false,
                appleEventQuitReason: nil
            ),
            .user
        )
        XCTAssertEqual(
            ApplicationTerminationClassifier.request(
                systemWillPowerOff: false,
                appleEventQuitReason: 0x7175_6961
            ),
            .user
        )
    }

    func testQuitConfirmationNamesOffInDestructiveChoice() {
        let presentation = ActiveSessionQuitConfirmationPresentation.activeSession

        XCTAssertTrue(presentation.message.contains("Off"))
        XCTAssertEqual(presentation.endButtonTitle, "Turn Off and Quit")
    }

    func testQuitInspectionFailurePresentationOffersOnlyNoMutationOrCancel() {
        let presentation = UninspectedSessionQuitConfirmationPresentation.inspectionFailed

        XCTAssertTrue(presentation.message.contains("without changing Amphetamine"))
        XCTAssertEqual(presentation.leaveButtonTitle, "Leave Amphetamine Unchanged and Quit")
        XCTAssertEqual(presentation.cancelButtonTitle, "Cancel")
    }

    func testUnsupportedAmphetamineQuitCanLeaveUnchangedWithoutMutation() throws {
        var activePromptCount = 0
        var failedInspectionPromptCount = 0
        var endCount = 0
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveSession: {
                throw ModeControlError.unsupportedVersion(found: "5.3.1")
            },
            endActiveSession: { endCount += 1 },
            choose: {
                activePromptCount += 1
                return .endAndQuit
            },
            chooseWhenInspectionFails: {
                failedInspectionPromptCount += 1
                return .leaveUnchangedAndQuit
            }
        )

        XCTAssertEqual(try coordinator.decision(), .terminateNow)
        XCTAssertEqual(activePromptCount, 0)
        XCTAssertEqual(failedInspectionPromptCount, 1)
        XCTAssertEqual(endCount, 0)
    }

    func testFailedReadQuitCanCancelWithoutMutation() throws {
        var activePromptCount = 0
        var endCount = 0
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveSession: { throw ModeControlError.automationDenied },
            endActiveSession: { endCount += 1 },
            choose: {
                activePromptCount += 1
                return .endAndQuit
            },
            chooseWhenInspectionFails: { .cancel }
        )

        XCTAssertEqual(try coordinator.decision(), .terminateCancel)
        XCTAssertEqual(activePromptCount, 0)
        XCTAssertEqual(endCount, 0)
    }

    func testEndSessionAndQuitEndsBeforeTermination() throws {
        var endCount = 0
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveSession: { true },
            endActiveSession: { endCount += 1 },
            choose: { .endAndQuit }
        )

        XCTAssertEqual(try coordinator.decision(), .terminateNow)
        XCTAssertEqual(endCount, 1)
    }

    func testLeaveSessionRunningQuitsWithoutEndingSession() throws {
        var endCount = 0
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveSession: { true },
            endActiveSession: { endCount += 1 },
            choose: { .leaveRunning }
        )

        XCTAssertEqual(try coordinator.decision(), .terminateNow)
        XCTAssertEqual(endCount, 0)
    }

    func testCancelQuitKeepsAppRunningWithoutEndingSession() throws {
        var endCount = 0
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveSession: { true },
            endActiveSession: { endCount += 1 },
            choose: { .cancel }
        )

        XCTAssertEqual(try coordinator.decision(), .terminateCancel)
        XCTAssertEqual(endCount, 0)
    }

    func testQuitEndFailurePreventsTermination() {
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveSession: { true },
            endActiveSession: { throw ModeControlError.verificationFailed("Still active") },
            choose: { .endAndQuit }
        )

        XCTAssertThrowsError(try coordinator.decision()) { error in
            XCTAssertEqual(
                error as? ModeControlError,
                .verificationFailed("Still active")
            )
        }
    }

    private static func snapshot(_ mode: OperatingMode) -> ModeSnapshot {
        ModeSnapshot(
            requestedMode: mode,
            observedState: nil,
            ownershipMarker: nil,
            health: .ready
        )
    }
}
