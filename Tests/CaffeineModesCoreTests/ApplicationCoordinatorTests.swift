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
        XCTAssertTrue(night.message.contains("display will sleep"))
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
        XCTAssertTrue(confirmation.message.contains("Travel for 90 Minutes"))
        XCTAssertTrue(confirmation.message.contains("display will sleep"))
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
        XCTAssertTrue(confirmation.message.contains("display will sleep"))
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
