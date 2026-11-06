import Foundation

// Surfaces a direct-mode proxy backup record that could not be verified and routes the user to
// the existing manual restore.

extension MainContentCoordinator {
    /// Re-reads whether a direct-mode proxy watchdog refused its backup record. The manager clears
    /// that when a new watchdog is armed or the session's watchers are retired, so every call that
    /// can do either re-syncs through the wrappers below and the banner leaves with the condition.
    func syncDirectWatchdogRefusal() {
        let refused = directWatchdogRefusalProbe()
        if isDirectProxyRecordUnverified != refused {
            isDirectProxyRecordUnverified = refused
        }
    }

    /// The banner's recovery. While capture is running this is the manual Stop path, which restores
    /// the Mac's proxy settings and then stops the listener. With no listener there is nothing to
    /// stop, so it goes straight to the same restore that "Switch Off" uses. The closures let tests
    /// count which route ran without touching live proxy settings.
    @discardableResult
    func restoreProxySettingsAfterUnverifiedRecord(
        stopCapture: (() -> Task<Void, Never>?)? = nil,
        switchOffRouting: (() -> Task<Void, Never>)? = nil
    )
        -> Task<Void, Never>?
    {
        if isProxyRunning {
            return (stopCapture ?? { self.stopProxy() })()
        }
        return (switchOffRouting ?? { self.switchOffSystemProxyOverride() })()
    }

    /// A refusal can arrive while Rockxy sits in the background, and the only record of it is
    /// launchd's retained exit status, which nothing pushes to the app. Returning to the window is
    /// when the banner has to be truthful, so activation re-runs the ownership check that reads it.
    /// Skipped when no listener runs and no override is known, where there is nothing to restore.
    /// `reconcile` is injectable so tests can count the call without reading live proxy state.
    @discardableResult
    func refreshProxyOverrideStatusOnActivation(
        reconcile: (() async -> Void)? = nil
    )
        -> Task<Void, Never>?
    {
        guard isProxyRunning || isProxyOverridden else {
            return nil
        }
        return Task { @MainActor in
            if let reconcile {
                await reconcile()
            } else {
                _ = await reconcileProxyOverrideStatus()
            }
        }
    }

    func effectiveOverrideOwnerSyncingRefusal() async -> ProxyOverrideOwner {
        let owner = await SystemProxyManager.shared.effectiveOverrideOwner()
        syncDirectWatchdogRefusal()
        return owner
    }

    func disableSystemProxySyncingRefusal() async throws -> SystemProxyRestoreReport {
        defer { syncDirectWatchdogRefusal() }
        return try await SystemProxyManager.shared.disableSystemProxy()
    }

    func enableSystemProxySyncingRefusal(port: Int) async throws {
        defer { syncDirectWatchdogRefusal() }
        try await SystemProxyManager.shared.enableSystemProxy(port: port)
    }
}
