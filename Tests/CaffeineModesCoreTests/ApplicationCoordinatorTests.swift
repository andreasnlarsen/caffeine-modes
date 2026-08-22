import CaffeineModesAppSupport
import CaffeineModesCore
import Foundation
import XCTest

@MainActor
final class ApplicationCoordinatorTests: XCTestCase {
    func testStartConfirmationCancelDoesNotRetryTransition() throws {
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

        XCTAssertNil(try coordinator.select(.work))
        XCTAssertEqual(authorizations, [false])
        XCTAssertEqual(confirmations, [.start(.work)])
    }

    func testStartConfirmationAcceptRetriesWithAuthorization() throws {
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

        XCTAssertEqual(try coordinator.select(.night), Self.snapshot(.night))
        XCTAssertEqual(authorizations, [false, true])
        XCTAssertEqual(confirmations, [.start(.night)])
    }

    func testActiveSessionReplacementCancelDoesNotRetryTransition() throws {
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

        XCTAssertNil(try coordinator.select(.off))
        XCTAssertEqual(authorizations, [false])
    }

    func testActiveSessionReplacementAcceptRetriesWithAuthorization() throws {
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

        XCTAssertEqual(try coordinator.select(.work), Self.snapshot(.work))
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

    func testUnexpectedModeErrorDoesNotAskForConfirmation() {
        var confirmationCount = 0
        let coordinator = ModeSelectionCoordinator(
            transition: { _, _ in throw ModeControlError.automationDenied },
            confirm: { _ in
                confirmationCount += 1
                return true
            }
        )

        XCTAssertThrowsError(try coordinator.select(.work)) { error in
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
