import Foundation

public final class ModeController: ModeControlling {
    private let amphetamine: AmphetamineControlling
    private let assertions: PowerAssertionInspecting
    private let screenLock: ScreenLockPolicyChecking
    private let display: DisplaySleeping
    private let store: ModeStateStoring
    private let clock: TimeProviding
    private var lastMutationFailure: String?

    public init(
        amphetamine: AmphetamineControlling,
        assertions: PowerAssertionInspecting,
        screenLock: ScreenLockPolicyChecking,
        display: DisplaySleeping,
        store: ModeStateStoring,
        clock: TimeProviding = SystemTimeProvider()
    ) {
        self.amphetamine = amphetamine
        self.assertions = assertions
        self.screenLock = screenLock
        self.display = display
        self.store = store
        self.clock = clock
    }

    public func reconcile() -> ModeSnapshot {
        guard amphetamine.isInstalled else {
            return snapshot(.off, nil, .amphetamineMissing, detail: ModeControlError.amphetamineMissing.localizedDescription)
        }
        guard VersionSupport.isSupported(amphetamine.installedVersion) else {
            let error = ModeControlError.unsupportedVersion(found: amphetamine.installedVersion)
            return snapshot(.off, nil, .unsupportedVersion, detail: error.localizedDescription)
        }

        do {
            let state = try amphetamine.readState()
            if let lastMutationFailure {
                return snapshot(.custom, state, .backendMismatch, detail: lastMutationFailure)
            }
            if !state.sessionIsActive {
                store.ownedSessionSignature = nil
                store.lastRequestedMode = .off
                return snapshot(.off, state, .ready)
            }

            guard let signature = store.ownedSessionSignature,
                  stateMatchesOwnedMode(state, mode: signature.mode)
            else {
                store.ownedSessionSignature = nil
                store.lastRequestedMode = .custom
                return snapshot(.custom, state, .conflicted, detail: "Amphetamine has a session that Caffeine Modes does not own.")
            }

            if case let .travel(_, expiresAt) = signature.mode, expiresAt <= clock.now {
                store.ownedSessionSignature = nil
                store.lastRequestedMode = .custom
                return snapshot(.custom, state, .backendMismatch, detail: "The Travel session is active after its expected expiry.")
            }

            store.lastRequestedMode = signature.mode
            return snapshot(signature.mode, state, .ready, marker: signature)
        } catch {
            return snapshotFrom(error: error)
        }
    }

    public func transition(
        to mode: OperatingMode,
        replacingUnownedSession: Bool = false
    ) throws -> ModeSnapshot {
        try validate(mode)
        let before = reconcile()

        if before.requestedMode == .custom, !replacingUnownedSession {
            throw ModeControlError.unownedSessionRequiresConfirmation
        }

        try preflight(mode)

        do {
            switch mode {
            case .off:
                if before.observedState?.sessionIsActive == true {
                    try amphetamine.endSession()
                }
            case .work:
                try amphetamine.startInfiniteSession(displaySleepAllowed: false)
                try amphetamine.setClosedDisplayMode(enabled: false)
            case .night:
                try amphetamine.startInfiniteSession(displaySleepAllowed: true)
                try amphetamine.setClosedDisplayMode(enabled: true)
            case let .travel(durationMinutes, _):
                try amphetamine.startTimedSession(minutes: durationMinutes, displaySleepAllowed: true)
                try amphetamine.setClosedDisplayMode(enabled: true)
            case .custom:
                throw ModeControlError.verificationFailed("Custom is an observed state and cannot be selected.")
            }

            let observed = try amphetamine.readState()
            guard stateMatchesRequestedMode(observed, mode: mode) else {
                throw ModeControlError.verificationFailed("Amphetamine did not reach the requested \(mode.displayName) state.")
            }

            let committedMode = normalized(mode)
            let marker: OwnedSessionSignature?
            if committedMode == .off {
                marker = nil
            } else {
                marker = OwnedSessionSignature(mode: committedMode, startedAt: clock.now)
            }
            store.lastRequestedMode = committedMode
            store.ownedSessionSignature = marker
            lastMutationFailure = nil

            if committedMode.requiresDisplaySleep {
                try display.sleepDisplay()
            }

            return snapshot(committedMode, observed, .ready, marker: marker)
        } catch {
            store.ownedSessionSignature = nil
            store.lastRequestedMode = .custom
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            _ = try? amphetamine.readState()
            lastMutationFailure = detail
            throw ModeControlError.backend(detail)
        }
    }

    public func setupReport() -> SetupReport {
        let installed = amphetamine.isInstalled
        let supported = VersionSupport.isSupported(amphetamine.installedVersion)
        var authorized = false
        var triggersDisabled = false
        var immediateLock = false
        var detail: String?

        if installed, supported {
            do {
                let state = try amphetamine.readState()
                authorized = true
                triggersDisabled = !state.triggersEnabled
            } catch {
                detail = error.localizedDescription
            }
        }

        do {
            immediateLock = try screenLock.hasImmediateScreenLock()
        } catch {
            detail = detail ?? error.localizedDescription
        }

        return SetupReport(
            amphetamineInstalled: installed,
            supportedVersion: supported,
            automationAuthorized: authorized,
            triggersDisabled: triggersDisabled,
            immediateScreenLock: immediateLock,
            closedDisplayReady: store.closedDisplayReadinessPassed,
            detectedVersion: amphetamine.installedVersion,
            detail: detail
        )
    }

    public func disableTriggers() throws {
        try requireAmphetamine()
        try amphetamine.setTriggers(enabled: false)
        guard try !amphetamine.readState().triggersEnabled else {
            throw ModeControlError.verificationFailed("Amphetamine Triggers are still enabled.")
        }
    }

    public func runClosedDisplayReadinessTest() throws {
        try preflight(.work, requireClosedDisplayReadiness: false)
        let current = reconcile()
        guard current.requestedMode == .off else {
            throw ModeControlError.verificationFailed("Turn the current session Off before the readiness test.")
        }

        do {
            try amphetamine.startTimedSession(minutes: 1, displaySleepAllowed: true)
            try amphetamine.setClosedDisplayMode(enabled: true)
            let state = try amphetamine.readState()
            guard state.sessionIsActive, state.displaySleepAllowed, state.closedDisplayModeEnabled else {
                throw ModeControlError.verificationFailed("Amphetamine did not confirm closed-display mode.")
            }
            try amphetamine.endSession()
            guard try !amphetamine.readState().sessionIsActive else {
                throw ModeControlError.verificationFailed("The readiness test session did not end.")
            }
            store.closedDisplayReadinessPassed = true
            store.lastRequestedMode = .off
            store.ownedSessionSignature = nil
        } catch {
            try? amphetamine.endSession()
            store.closedDisplayReadinessPassed = false
            throw error
        }
    }

    public func prepareToQuit() throws {
        let current = reconcile()
        if current.requestedMode == .custom || current.requestedMode == .off {
            return
        }

        try amphetamine.endSession()
        let observed = try amphetamine.readState()
        guard !observed.sessionIsActive else {
            throw ModeControlError.verificationFailed("Caffeine Modes could not verify Off, so it will remain open.")
        }
        store.ownedSessionSignature = nil
        store.lastRequestedMode = .off
        lastMutationFailure = nil
    }

    private func preflight(
        _ mode: OperatingMode,
        requireClosedDisplayReadiness: Bool = true
    ) throws {
        try requireAmphetamine()
        let state: AmphetamineState
        do {
            state = try amphetamine.readState()
        } catch let error as ModeControlError {
            throw error
        } catch {
            throw ModeControlError.backend(error.localizedDescription)
        }

        if mode != .off {
            guard !state.triggersEnabled else { throw ModeControlError.triggersEnabled }
        }

        if mode.requiresDisplaySleep {
            guard try screenLock.hasImmediateScreenLock() else {
                throw ModeControlError.screenLockNotImmediate
            }
            if requireClosedDisplayReadiness, !store.closedDisplayReadinessPassed {
                throw ModeControlError.verificationFailed("Complete the closed-display readiness test first.")
            }
            let blockers = try assertions.displaySleepBlockingProcesses()
            guard blockers.isEmpty else {
                throw ModeControlError.displaySleepBlocked(blockers)
            }
        }
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

    private func normalized(_ mode: OperatingMode) -> OperatingMode {
        guard case let .travel(durationMinutes, _) = mode else { return mode }
        return .travel(
            durationMinutes: durationMinutes,
            expiresAt: clock.now.addingTimeInterval(TimeInterval(durationMinutes * 60))
        )
    }

    private func stateMatchesOwnedMode(_ state: AmphetamineState, mode: OperatingMode) -> Bool {
        stateMatchesRequestedMode(state, mode: mode)
    }

    private func stateMatchesRequestedMode(_ state: AmphetamineState, mode: OperatingMode) -> Bool {
        switch mode {
        case .off:
            !state.sessionIsActive
        case .work:
            state.sessionIsActive && !state.displaySleepAllowed && !state.closedDisplayModeEnabled
        case .night, .travel:
            state.sessionIsActive && state.displaySleepAllowed && state.closedDisplayModeEnabled
        case .custom:
            false
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

private extension OperatingMode {
    var requiresDisplaySleep: Bool {
        switch self {
        case .night, .travel: true
        default: false
        }
    }
}
