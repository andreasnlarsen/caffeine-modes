import Foundation

public final class ModeController: ModeControlling {
    private let amphetamine: AmphetamineControlling
    private let assertions: PowerAssertionInspecting
    private let screenLock: ScreenLockPolicyChecking
    private let display: DisplaySleeping
    private let store: ModeStateStoring
    private let clock: TimeProviding
    private let monotonicClock: MonotonicTimeProviding
    private let operationTimeout: TimeInterval
    private let readinessTimeout: TimeInterval
    private let mutationRecoveryReserve: TimeInterval = 0.5
    private var lastMutationFailure: String?
    // Serializes every public entry point so the setup window can run its
    // checks and the bounded readiness action off the main thread without
    // racing menu-driven calls. No public method calls another public method.
    private let entryLock = NSLock()

    public init(
        amphetamine: AmphetamineControlling,
        assertions: PowerAssertionInspecting,
        screenLock: ScreenLockPolicyChecking,
        display: DisplaySleeping,
        store: ModeStateStoring,
        clock: TimeProviding = SystemTimeProvider(),
        monotonicClock: MonotonicTimeProviding = SystemMonotonicTimeProvider(),
        operationTimeout: TimeInterval = 2,
        readinessTimeout: TimeInterval = 45
    ) {
        self.amphetamine = amphetamine
        self.assertions = assertions
        self.screenLock = screenLock
        self.display = display
        self.store = store
        self.clock = clock
        self.monotonicClock = monotonicClock
        self.operationTimeout = operationTimeout
        self.readinessTimeout = readinessTimeout
    }

    public func reconcile() -> ModeSnapshot {
        entryLock.lock()
        defer { entryLock.unlock() }
        return reconcile(deadline: makeDeadline())
    }

    private func reconcile(deadline: OperationDeadline) -> ModeSnapshot {
        guard amphetamine.isInstalled else {
            return snapshot(.off, nil, .amphetamineMissing, detail: ModeControlError.amphetamineMissing.localizedDescription)
        }
        guard VersionSupport.isSupported(amphetamine.installedVersion) else {
            let error = ModeControlError.unsupportedVersion(found: amphetamine.installedVersion)
            return snapshot(.off, nil, .unsupportedVersion, detail: error.localizedDescription)
        }

        do {
            let state = try readAmphetamineState(deadline: deadline)
            if !state.sessionIsActive {
                store.ownedSessionSignature = nil
                store.lastRequestedMode = .off
                lastMutationFailure = nil
                return snapshot(.off, state, .ready)
            }
            if let lastMutationFailure {
                if let signature = store.ownedSessionSignature,
                   !stateMatchesOwnedSignature(state, signature: signature) {
                    store.ownedSessionSignature = nil
                }
                store.lastRequestedMode = .custom
                return snapshot(.custom, state, .backendMismatch, detail: lastMutationFailure)
            }

            guard var signature = store.ownedSessionSignature else {
                store.ownedSessionSignature = nil
                store.lastRequestedMode = .custom
                return snapshot(.custom, state, .conflicted, detail: "The active Amphetamine session does not match a stored Caffeine Modes projection.")
            }

            if let migratedSignature = migratedLegacyTravelSignature(signature, observed: state) {
                signature = migratedSignature
                store.ownedSessionSignature = migratedSignature
            }

            if case .pendingCleanup = signature.purpose {
                guard stateMatchesOwnedSignature(state, signature: signature) else {
                    store.ownedSessionSignature = nil
                    store.lastRequestedMode = .custom
                    return snapshot(.custom, state, .conflicted, detail: "The active Amphetamine session does not match a stored Caffeine Modes projection.")
                }
                store.lastRequestedMode = .custom
                return snapshot(
                    .custom,
                    state,
                    .backendMismatch,
                    detail: "Caffeine Modes must clean up a session from an incomplete operation.",
                    marker: signature
                )
            }

            if case .readinessTest = signature.purpose {
                if case let .travel(_, expiresAt) = signature.mode,
                   expiresAt.addingTimeInterval(5) < clock.now {
                    store.ownedSessionSignature = nil
                    store.lastRequestedMode = .custom
                    return snapshot(.custom, state, .backendMismatch, detail: "The readiness-test session is active after its expected expiry.")
                }
                guard stateMatchesOwnedSignature(state, signature: signature) else {
                    store.ownedSessionSignature = nil
                    store.lastRequestedMode = .custom
                    return snapshot(.custom, state, .conflicted, detail: "The Amphetamine readiness-test session changed outside Caffeine Modes.")
                }
                store.lastRequestedMode = .custom
                return snapshot(
                    .custom,
                    state,
                    .ready,
                    detail: "Closed-display readiness test is active and will end automatically.",
                    marker: signature
                )
            }

            if case let .travel(_, expiresAt) = signature.mode,
               expiresAt.addingTimeInterval(5) < clock.now {
                store.ownedSessionSignature = nil
                store.lastRequestedMode = .custom
                return snapshot(.custom, state, .backendMismatch, detail: "The Travel session is active after its expected expiry.")
            }

            guard stateMatchesOwnedSignature(state, signature: signature) else {
                store.ownedSessionSignature = nil
                store.lastRequestedMode = .custom
                return snapshot(.custom, state, .conflicted, detail: "The active Amphetamine session does not match a stored Caffeine Modes projection.")
            }

            store.lastRequestedMode = signature.mode
            return snapshot(signature.mode, state, .ready, marker: signature)
        } catch {
            return snapshotFrom(error: error)
        }
    }

    public func transition(
        to mode: OperatingMode,
        replacingActiveSession: Bool = false
    ) throws -> ModeSnapshot {
        entryLock.lock()
        defer { entryLock.unlock() }
        let deadline = makeDeadline()
        try validate(mode)
        let before = reconcile(deadline: deadline)
        let preflightState = try preflight(mode, deadline: deadline)
        let preflightMatchesStoredSignature = before.ownershipMarker.map {
            stateMatchesOwnedSignature(preflightState, signature: $0)
        } ?? false
        if preflightState.sessionIsActive, !replacingActiveSession {
            throw ModeControlError.activeSessionRequiresConfirmation
        }
        if mode != .off, !replacingActiveSession {
            throw ModeControlError.sessionStartRequiresConfirmation
        }
        let targetMode = mode
        let signatureBeforeMutation = preflightMatchesStoredSignature ? before.ownershipMarker : nil
        var sessionStartWasAttempted = false
        var sessionStartCompleted = false
        var fallbackCleanupSignature: OwnedSessionSignature?
        var pendingCleanupWasPersisted = false

        do {
            switch targetMode {
            case .off:
                if preflightState.sessionIsActive {
                    try endAmphetamineSession(deadline: deadline)
                }
            case .work:
                sessionStartWasAttempted = true
                try amphetamine.startInfiniteSession(
                    displaySleepAllowed: false,
                    timeout: try remainingMutationTime(deadline)
                )
                sessionStartCompleted = true
                let startedMode = modeAnchoredAfterConfirmedStart(targetMode)
                fallbackCleanupSignature = persistProvisionalCleanupSignature(
                    for: startedMode,
                    preflightState: preflightState
                )
                try checkDeadline(deadline)
                try amphetamine.setClosedDisplayMode(
                    enabled: false,
                    timeout: try remainingMutationTime(deadline)
                )
                fallbackCleanupSignature = persistProvisionalCleanupSignature(
                    for: startedMode,
                    preflightState: preflightState,
                    closedDisplayModeEnabled: false
                )
                try checkDeadline(deadline)
            case .night:
                sessionStartWasAttempted = true
                try amphetamine.startInfiniteSession(
                    displaySleepAllowed: true,
                    timeout: try remainingMutationTime(deadline)
                )
                sessionStartCompleted = true
                let startedMode = modeAnchoredAfterConfirmedStart(targetMode)
                fallbackCleanupSignature = persistProvisionalCleanupSignature(
                    for: startedMode,
                    preflightState: preflightState
                )
                try checkDeadline(deadline)
                try amphetamine.setClosedDisplayMode(
                    enabled: true,
                    timeout: try remainingMutationTime(deadline)
                )
                fallbackCleanupSignature = persistProvisionalCleanupSignature(
                    for: startedMode,
                    preflightState: preflightState,
                    closedDisplayModeEnabled: true
                )
                try checkDeadline(deadline)
            case let .travel(durationMinutes, _):
                sessionStartWasAttempted = true
                try amphetamine.startTimedSession(
                    minutes: durationMinutes,
                    displaySleepAllowed: true,
                    timeout: try remainingMutationTime(deadline)
                )
                sessionStartCompleted = true
                let startedMode = modeAnchoredAfterConfirmedStart(targetMode)
                fallbackCleanupSignature = persistProvisionalCleanupSignature(
                    for: startedMode,
                    preflightState: preflightState
                )
                try checkDeadline(deadline)
                try amphetamine.setClosedDisplayMode(
                    enabled: true,
                    timeout: try remainingMutationTime(deadline)
                )
                fallbackCleanupSignature = persistProvisionalCleanupSignature(
                    for: startedMode,
                    preflightState: preflightState,
                    closedDisplayModeEnabled: true
                )
                try checkDeadline(deadline)
            case .custom:
                throw ModeControlError.verificationFailed("Custom is an observed state and cannot be selected.")
            }

            let observed = try readAmphetamineState(deadline: deadline)
            let committedMode = modeAnchoredToObservedTimer(targetMode, observed: observed)
            guard stateMatchesRequestedMode(observed, mode: committedMode),
                  observedTravelDurationMatchesRequest(observed, mode: targetMode)
            else {
                throw ModeControlError.verificationFailed("Amphetamine did not reach the requested \(mode.displayName) state.")
            }

            let marker: OwnedSessionSignature?
            if committedMode == .off {
                marker = nil
            } else {
                marker = OwnedSessionSignature(mode: committedMode, startedAt: clock.now)
            }
            lastMutationFailure = nil

            if committedMode.requiresDisplaySleep, let marker {
                store.lastRequestedMode = .custom
                store.ownedSessionSignature = cleanupSignature(
                    id: marker.id,
                    mode: marker.mode,
                    startedAt: marker.startedAt,
                    observed: observed
                )
                pendingCleanupWasPersisted = true
                try display.sleepDisplay(timeout: try remainingTime(deadline))
                try checkDeadline(deadline)
            }

            store.lastRequestedMode = committedMode
            store.ownedSessionSignature = marker

            return snapshot(committedMode, observed, .ready, marker: marker)
        } catch {
            if !pendingCleanupWasPersisted {
                if targetMode == .off {
                    store.ownedSessionSignature = verifiedSignatureAfterFailedOff(
                        signatureBeforeMutation,
                        deadline: deadline
                    )
                } else if sessionStartWasAttempted {
                    store.ownedSessionSignature = signatureAfterFailedSessionStart(
                        targetMode,
                        priorSignature: signatureBeforeMutation,
                        startCompleted: sessionStartCompleted,
                        fallbackSignature: fallbackCleanupSignature,
                        deadline: deadline
                    )
                } else {
                    store.ownedSessionSignature = signatureBeforeMutation
                }
            }
            store.lastRequestedMode = .custom
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastMutationFailure = detail
            throw ModeControlError.backend(detail)
        }
    }

    public func setupReport() -> SetupReport {
        entryLock.lock()
        defer { entryLock.unlock() }
        let installed = amphetamine.isInstalled
        let version = amphetamine.installedVersion
        let supported = VersionSupport.isSupported(version)

        var automation = SetupCheckState.unchecked(reason: nil)
        var triggers = SetupCheckState.unchecked(reason: nil)
        var sessionIsActive: Bool?

        if installed, supported {
            do {
                let state = try readAmphetamineState(deadline: makeDeadline())
                automation = .passed
                triggers = state.triggersEnabled ? .needsAction : .passed
                sessionIsActive = state.sessionIsActive
            } catch ModeControlError.automationDenied {
                automation = .needsAction
            } catch {
                automation = .unchecked(reason: error.localizedDescription)
            }
        }

        var screenLockState = SetupCheckState.unchecked(reason: nil)
        do {
            let screenLockDeadline = makeDeadline()
            let immediate = try screenLock.hasImmediateScreenLock(
                timeout: try remainingTime(screenLockDeadline)
            )
            try checkDeadline(screenLockDeadline)
            screenLockState = immediate ? .passed : .needsAction
        } catch {
            screenLockState = .unchecked(reason: error.localizedDescription)
        }

        return SetupReport(
            amphetamineInstalled: installed,
            supportedVersion: supported,
            detectedVersion: version,
            automation: automation,
            triggers: triggers,
            screenLock: screenLockState,
            closedDisplayReady: store.closedDisplayReadinessPassed,
            amphetamineSessionIsActive: sessionIsActive
        )
    }

    public func disableTriggers() throws {
        entryLock.lock()
        defer { entryLock.unlock() }
        let deadline = makeDeadline()
        try requireAmphetamine()
        do {
            try setTriggers(enabled: false, deadline: deadline)
            guard try !readAmphetamineState(deadline: deadline).triggersEnabled else {
                throw ModeControlError.verificationFailed("Amphetamine Triggers are still enabled.")
            }
        } catch {
            if let recovered = readStateForCleanup(deadline: deadline),
               !recovered.triggersEnabled {
                return
            }
            throw error
        }
    }

    public func runClosedDisplayReadinessTest(
        authorizingSessionReplacement: Bool
    ) throws {
        entryLock.lock()
        defer { entryLock.unlock() }
        let preflightDeadline = makeDeadline()
        let preflightState = try preflight(
            .work,
            requireClosedDisplayReadiness: false,
            deadline: preflightDeadline
        )
        let current = reconcile(deadline: preflightDeadline)
        guard current.requestedMode == .off else {
            throw ModeControlError.verificationFailed("Turn the current session Off before the readiness test.")
        }
        guard authorizingSessionReplacement else {
            throw ModeControlError.sessionStartRequiresConfirmation
        }

        let deadline = makeDeadline(timeout: readinessTimeout)
        let targetMode = OperatingMode.travel(
            durationMinutes: 1,
            expiresAt: clock.now.addingTimeInterval(60)
        )
        var fallbackSignature: OwnedSessionSignature?
        do {
            try amphetamine.startTimedSession(
                minutes: 1,
                displaySleepAllowed: true,
                timeout: try remainingMutationTime(deadline)
            )
            fallbackSignature = persistProvisionalCleanupSignature(
                for: targetMode,
                preflightState: preflightState
            )
            try checkDeadline(deadline)
            try amphetamine.setClosedDisplayMode(
                enabled: true,
                timeout: try remainingMutationTime(deadline)
            )
            fallbackSignature = persistProvisionalCleanupSignature(
                for: targetMode,
                preflightState: preflightState,
                closedDisplayModeEnabled: true
            )
            try checkDeadline(deadline)
            let state = try readAmphetamineState(deadline: deadline)
            let committedMode = modeAnchoredToObservedTimer(targetMode, observed: state)
            guard observedReadinessDurationMatchesRequest(state, mode: targetMode),
                  stateMatchesReadinessSession(state, mode: committedMode)
            else {
                throw ModeControlError.verificationFailed("Amphetamine did not confirm closed-display mode.")
            }
            fallbackSignature = OwnedSessionSignature(
                mode: committedMode,
                startedAt: clock.now,
                purpose: .readinessTest,
                expectedState: state
            )
            store.lastRequestedMode = .custom
            store.ownedSessionSignature = fallbackSignature
            store.closedDisplayReadinessPassed = true
            lastMutationFailure = nil
        } catch {
            store.closedDisplayReadinessPassed = false
            store.lastRequestedMode = .custom
            store.ownedSessionSignature = readinessCleanupSignature(
                fallbackSignature,
                targetMode: targetMode,
                deadline: deadline
            )
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastMutationFailure = detail
            throw error
        }
    }

    public func hasActiveSessionForQuit() throws -> Bool {
        entryLock.lock()
        defer { entryLock.unlock() }
        let deadline = makeDeadline()
        guard amphetamine.isInstalled else {
            store.ownedSessionSignature = nil
            store.lastRequestedMode = .off
            lastMutationFailure = nil
            return false
        }
        try requireAmphetamine()
        let before = try readAmphetamineState(deadline: deadline)
        if !before.sessionIsActive {
            store.ownedSessionSignature = nil
            store.lastRequestedMode = .off
            lastMutationFailure = nil
            return false
        }
        return true
    }

    public func endActiveSessionForQuit() throws {
        entryLock.lock()
        defer { entryLock.unlock() }
        let deadline = makeDeadline()
        try requireAmphetamine()
        let before = try readAmphetamineState(deadline: deadline)
        guard before.sessionIsActive else {
            store.ownedSessionSignature = nil
            store.lastRequestedMode = .off
            lastMutationFailure = nil
            return
        }

        let priorSignature = store.ownedSessionSignature.flatMap { signature in
            stateMatchesOwnedSignature(before, signature: signature) ? signature : nil
        }
        do {
            try endAmphetamineSession(deadline: deadline)
            let observed = try readAmphetamineState(deadline: deadline)
            guard !observed.sessionIsActive else {
                throw ModeControlError.verificationFailed("Caffeine Modes could not verify Off, so it will remain open.")
            }
            finalizeVerifiedOff()
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let recovered = readStateForCleanup(deadline: deadline) {
                if !recovered.sessionIsActive {
                    finalizeVerifiedOff()
                    return
                }
                store.ownedSessionSignature = failedQuitCleanupSignature(
                    priorSignature,
                    observed: recovered
                )
            } else {
                store.ownedSessionSignature = failedQuitCleanupSignature(
                    priorSignature,
                    observed: before
                )
            }
            store.lastRequestedMode = .custom
            lastMutationFailure = detail
            throw ModeControlError.backend(detail)
        }
    }

    private func finalizeVerifiedOff() {
        store.ownedSessionSignature = nil
        store.lastRequestedMode = .off
        lastMutationFailure = nil
    }

    private func failedQuitCleanupSignature(
        _ priorSignature: OwnedSessionSignature?,
        observed: AmphetamineState
    ) -> OwnedSessionSignature? {
        guard let priorSignature,
              stateMatchesOwnedSignature(observed, signature: priorSignature)
        else { return nil }
        let recoveredMode = modeAnchoredToObservedTimer(
            priorSignature.mode,
            observed: observed
        )
        return cleanupSignature(
            id: priorSignature.id,
            mode: recoveredMode,
            startedAt: priorSignature.startedAt,
            observed: observed
        )
    }

    private func preflight(
        _ mode: OperatingMode,
        requireClosedDisplayReadiness: Bool = true,
        deadline: OperationDeadline
    ) throws -> AmphetamineState {
        try requireAmphetamine()
        let state: AmphetamineState
        do {
            state = try readAmphetamineState(deadline: deadline)
        } catch let error as ModeControlError {
            throw error
        } catch {
            throw ModeControlError.backend(error.localizedDescription)
        }

        if mode != .off {
            guard !state.triggersEnabled else { throw ModeControlError.triggersEnabled }
        }

        if mode.requiresDisplaySleep {
            guard try screenLock.hasImmediateScreenLock(timeout: try remainingTime(deadline)) else {
                throw ModeControlError.screenLockNotImmediate
            }
            try checkDeadline(deadline)
            if requireClosedDisplayReadiness, !store.closedDisplayReadinessPassed {
                throw ModeControlError.verificationFailed("Complete the closed-display readiness test first.")
            }
            let blockers = try assertions.inspect(timeout: try remainingTime(deadline))
                .displaySleepBlockingProcesses
            try checkDeadline(deadline)
            guard blockers.isEmpty else {
                throw ModeControlError.displaySleepBlocked(blockers)
            }
        }
        return state
    }

    private func makeDeadline(timeout: TimeInterval? = nil) -> OperationDeadline {
        OperationDeadline(expiresAt: monotonicClock.now + (timeout ?? operationTimeout))
    }

    private func remainingTime(_ deadline: OperationDeadline) throws -> TimeInterval {
        let remaining = deadline.expiresAt - monotonicClock.now
        guard remaining > 0 else { throw ModeControlError.operationTimedOut }
        return remaining
    }

    private func checkDeadline(_ deadline: OperationDeadline) throws {
        _ = try remainingTime(deadline)
    }

    private func remainingMutationTime(_ deadline: OperationDeadline) throws -> TimeInterval {
        let mutationTime = try remainingTime(deadline) - mutationRecoveryReserve
        guard mutationTime > 0 else { throw ModeControlError.operationTimedOut }
        return mutationTime
    }

    private func readAmphetamineState(deadline: OperationDeadline) throws -> AmphetamineState {
        let state = try amphetamine.readState(timeout: try remainingTime(deadline))
        try checkDeadline(deadline)
        return state
    }

    private func endAmphetamineSession(deadline: OperationDeadline) throws {
        try amphetamine.endSession(timeout: try remainingMutationTime(deadline))
        try checkDeadline(deadline)
    }

    private func setTriggers(enabled: Bool, deadline: OperationDeadline) throws {
        try amphetamine.setTriggers(enabled: enabled, timeout: try remainingMutationTime(deadline))
        try checkDeadline(deadline)
    }

    private func signatureAfterFailedSessionStart(
        _ targetMode: OperatingMode,
        priorSignature: OwnedSessionSignature?,
        startCompleted: Bool,
        fallbackSignature: OwnedSessionSignature?,
        deadline: OperationDeadline
    ) -> OwnedSessionSignature? {
        guard let observed = readStateForCleanup(deadline: deadline) else {
            return startCompleted ? fallbackSignature : nil
        }
        guard observed.sessionIsActive else { return nil }

        guard startCompleted else { return nil }

        if let priorSignature,
           !sameModePolicy(targetMode, priorSignature.mode),
           stateMatchesOwnedSignature(observed, signature: priorSignature) {
            return priorSignature
        }

        guard stateMatchesStartedSession(observed, targetMode: targetMode) else { return nil }

        let cleanupMode = modeAnchoredToObservedTimer(targetMode, observed: observed)
        return cleanupSignature(mode: cleanupMode, observed: observed)
    }

    private func sameModePolicy(_ lhs: OperatingMode, _ rhs: OperatingMode) -> Bool {
        switch (lhs, rhs) {
        case (.work, .work), (.night, .night):
            return true
        case let (.travel(lhsDuration, _), .travel(rhsDuration, _)):
            return lhsDuration == rhsDuration
        default:
            return false
        }
    }

    private func verifiedSignatureAfterFailedOff(
        _ priorSignature: OwnedSessionSignature?,
        deadline: OperationDeadline
    ) -> OwnedSessionSignature? {
        guard let priorSignature,
              let observed = readStateForCleanup(deadline: deadline),
              stateMatchesOwnedSignature(observed, signature: priorSignature)
        else { return nil }
        return priorSignature
    }

    private func readStateForCleanup(deadline: OperationDeadline) -> AmphetamineState? {
        try? readAmphetamineState(deadline: deadline)
    }

    private func readinessCleanupSignature(
        _ signature: OwnedSessionSignature?,
        targetMode: OperatingMode,
        deadline: OperationDeadline
    ) -> OwnedSessionSignature? {
        guard let observed = readStateForCleanup(deadline: deadline),
              let signature
        else { return nil }
        let recoveredMode = modeAnchoredToObservedTimer(targetMode, observed: observed)
        guard observedReadinessDurationMatchesRequest(observed, mode: targetMode),
              stateMatchesRecoverableReadinessSession(observed, mode: recoveredMode)
        else { return nil }
        return cleanupSignature(
            id: signature.id,
            mode: recoveredMode,
            startedAt: signature.startedAt,
            observed: observed
        )
    }

    @discardableResult
    private func persistProvisionalCleanupSignature(
        for targetMode: OperatingMode,
        preflightState: AmphetamineState,
        closedDisplayModeEnabled: Bool? = nil
    ) -> OwnedSessionSignature {
        let remainingSeconds: Int
        if case let .travel(_, expiresAt) = targetMode {
            remainingSeconds = max(1, Int(expiresAt.timeIntervalSince(clock.now).rounded(.up)))
        } else {
            remainingSeconds = 0
        }
        let expectedState = AmphetamineState(
            sessionIsActive: true,
            displaySleepAllowed: targetMode != .work,
            closedDisplayModeEnabled: closedDisplayModeEnabled
                ?? preflightState.closedDisplayModeEnabled,
            triggersEnabled: false,
            sessionTimeRemainingSeconds: remainingSeconds
        )
        let signature = cleanupSignature(
            mode: targetMode,
            observed: expectedState
        )
        store.lastRequestedMode = .custom
        store.ownedSessionSignature = signature
        return signature
    }

    private func stateMatchesStartedSession(
        _ state: AmphetamineState,
        targetMode: OperatingMode
    ) -> Bool {
        guard state.sessionIsActive else { return false }
        switch targetMode {
        case .work:
            return !state.displaySleepAllowed && state.sessionTimeRemainingSeconds == 0
        case .night:
            return state.displaySleepAllowed && state.sessionTimeRemainingSeconds == 0
        case let .travel(durationMinutes, _):
            let requestedSeconds = durationMinutes * 60
            return state.displaySleepAllowed
                && state.sessionTimeRemainingSeconds > 0
                && state.sessionTimeRemainingSeconds <= requestedSeconds
                && state.sessionTimeRemainingSeconds >= requestedSeconds - 30
        case .off, .custom:
            return false
        }
    }

    private func stateMatchesReadinessSession(
        _ state: AmphetamineState,
        mode: OperatingMode
    ) -> Bool {
        guard case let .travel(_, expiresAt) = mode,
              state.sessionIsActive,
              state.displaySleepAllowed,
              state.closedDisplayModeEnabled,
              state.sessionTimeRemainingSeconds > 0
        else { return false }
        let expectedRemaining = Int(expiresAt.timeIntervalSince(clock.now).rounded(.up))
        return expectedRemaining > 0
            && abs(state.sessionTimeRemainingSeconds - expectedRemaining) <= 5
    }

    private func stateMatchesRecoverableReadinessSession(
        _ state: AmphetamineState,
        mode: OperatingMode
    ) -> Bool {
        guard case let .travel(_, expiresAt) = mode,
              state.sessionIsActive,
              state.displaySleepAllowed,
              !state.triggersEnabled,
              state.sessionTimeRemainingSeconds > 0
        else { return false }
        let expectedRemaining = Int(expiresAt.timeIntervalSince(clock.now).rounded(.up))
        return expectedRemaining > 0
            && abs(state.sessionTimeRemainingSeconds - expectedRemaining) <= 5
    }

    private func observedReadinessDurationMatchesRequest(
        _ state: AmphetamineState,
        mode: OperatingMode
    ) -> Bool {
        guard case let .travel(durationMinutes, _) = mode else { return false }
        return state.sessionTimeRemainingSeconds > 0
            && state.sessionTimeRemainingSeconds <= durationMinutes * 60
    }

    private func cleanupSignature(
        id: UUID = UUID(),
        mode: OperatingMode,
        startedAt: Date? = nil,
        observed: AmphetamineState
    ) -> OwnedSessionSignature {
        OwnedSessionSignature(
            id: id,
            mode: mode,
            startedAt: startedAt ?? clock.now,
            purpose: .pendingCleanup,
            expectedState: observed
        )
    }

    private func requireAmphetamine() throws {
        guard amphetamine.isInstalled else { throw ModeControlError.amphetamineMissing }
        guard VersionSupport.isSupported(amphetamine.installedVersion) else {
            throw ModeControlError.unsupportedVersion(found: amphetamine.installedVersion)
        }
    }

    private func validate(_ mode: OperatingMode) throws {
        if case let .travel(durationMinutes, _) = mode,
           !OperatingMode.allowedTravelDurations.contains(durationMinutes) {
            throw ModeControlError.invalidTravelDuration(durationMinutes)
        }
    }

    private func modeAnchoredToObservedTimer(
        _ mode: OperatingMode,
        observed: AmphetamineState
    ) -> OperatingMode {
        guard case let .travel(durationMinutes, _) = mode,
              observed.sessionTimeRemainingSeconds > 0
        else { return mode }
        return .travel(
            durationMinutes: durationMinutes,
            expiresAt: clock.now.addingTimeInterval(TimeInterval(observed.sessionTimeRemainingSeconds))
        )
    }

    private func modeAnchoredAfterConfirmedStart(_ mode: OperatingMode) -> OperatingMode {
        guard case let .travel(durationMinutes, _) = mode else { return mode }
        return .travel(
            durationMinutes: durationMinutes,
            expiresAt: clock.now.addingTimeInterval(TimeInterval(durationMinutes * 60))
        )
    }

    private func observedTravelDurationMatchesRequest(
        _ state: AmphetamineState,
        mode: OperatingMode
    ) -> Bool {
        guard case let .travel(durationMinutes, _) = mode else { return true }
        let requestedSeconds = durationMinutes * 60
        return state.sessionTimeRemainingSeconds <= requestedSeconds
            && state.sessionTimeRemainingSeconds >= requestedSeconds - 30
    }

    private func stateMatchesOwnedSignature(
        _ state: AmphetamineState,
        signature: OwnedSessionSignature
    ) -> Bool {
        guard signature.purpose != .activeMode else {
            return stateMatchesRequestedMode(state, mode: signature.mode)
        }
        guard let expected = signature.expectedState else { return false }
        return state.sessionIsActive == expected.sessionIsActive
            && state.displaySleepAllowed == expected.displaySleepAllowed
            && state.closedDisplayModeEnabled == expected.closedDisplayModeEnabled
            && cleanupTimerMatches(state, expected: expected, mode: signature.mode)
    }

    private func migratedLegacyTravelSignature(
        _ signature: OwnedSessionSignature,
        observed state: AmphetamineState
    ) -> OwnedSessionSignature? {
        guard signature.usesLegacyProjectionFormat,
              signature.purpose == .activeMode,
              case let .travel(durationMinutes, _) = signature.mode,
              state.sessionIsActive,
              state.displaySleepAllowed,
              state.closedDisplayModeEnabled,
              state.sessionTimeRemainingSeconds > 0,
              state.sessionTimeRemainingSeconds <= durationMinutes * 60
        else { return nil }

        let migratedMode = OperatingMode.travel(
            durationMinutes: durationMinutes,
            expiresAt: clock.now.addingTimeInterval(TimeInterval(state.sessionTimeRemainingSeconds))
        )
        return OwnedSessionSignature(
            id: signature.id,
            mode: migratedMode,
            startedAt: signature.startedAt
        )
    }

    private func cleanupTimerMatches(
        _ state: AmphetamineState,
        expected: AmphetamineState,
        mode: OperatingMode
    ) -> Bool {
        guard expected.sessionTimeRemainingSeconds > 0 else {
            return state.sessionTimeRemainingSeconds == expected.sessionTimeRemainingSeconds
        }
        guard case let .travel(_, expiresAt) = mode,
              state.sessionTimeRemainingSeconds > 0
        else { return false }
        let expectedRemaining = Int(expiresAt.timeIntervalSince(clock.now).rounded(.up))
        return expectedRemaining > 0
            && abs(state.sessionTimeRemainingSeconds - expectedRemaining) <= 5
    }

    private func stateMatchesRequestedMode(_ state: AmphetamineState, mode: OperatingMode) -> Bool {
        switch mode {
        case .off:
            return !state.sessionIsActive
        case .work:
            return state.sessionIsActive
                && !state.displaySleepAllowed
                && !state.closedDisplayModeEnabled
                && state.sessionTimeRemainingSeconds == 0
        case .night:
            return state.sessionIsActive
                && state.displaySleepAllowed
                && state.closedDisplayModeEnabled
                && state.sessionTimeRemainingSeconds == 0
        case let .travel(_, expiresAt):
            guard state.sessionIsActive,
                  state.displaySleepAllowed,
                  state.closedDisplayModeEnabled,
                  state.sessionTimeRemainingSeconds > 0
            else { return false }
            let expectedRemaining = Int(expiresAt.timeIntervalSince(clock.now).rounded(.up))
            return abs(state.sessionTimeRemainingSeconds - expectedRemaining) <= 5
        case .custom:
            return false
        }
    }

    private func snapshot(
        _ mode: OperatingMode,
        _ state: AmphetamineState?,
        _ health: ControlHealth,
        detail: String? = nil,
        marker: OwnedSessionSignature? = nil
    ) -> ModeSnapshot {
        ModeSnapshot(
            requestedMode: mode,
            observedState: state,
            ownershipMarker: marker ?? store.ownedSessionSignature,
            health: health,
            detail: detail
        )
    }

    private func snapshotFrom(error: Error) -> ModeSnapshot {
        let controlError = error as? ModeControlError
        let health: ControlHealth
        switch controlError {
        case .automationDenied: health = .automationDenied
        case .amphetamineMissing: health = .amphetamineMissing
        case .unsupportedVersion: health = .unsupportedVersion
        default: health = .backendMismatch
        }
        return snapshot(.custom, nil, health, detail: error.localizedDescription)
    }
}

private struct OperationDeadline {
    let expiresAt: TimeInterval
}

private extension OperatingMode {
    var requiresDisplaySleep: Bool {
        switch self {
        case .night, .travel: true
        default: false
        }
    }
}
