import Foundation

extension MainContentCoordinator {
    func configureBabylonCaptureIntake() {
        let manager = sessionManager
        Task {
            await manager.setOnBatchReady { [weak self] batch, generation in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    self.processBatch(batch, generation: generation)
                }
            }
            await manager.setOnClientAppEnriched { [weak self] enrichedIDs in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    self.handleClientAppEnrichment(enrichedIDs)
                }
            }
            let settings = AppSettingsStorage.load()
            await manager.setMaxBufferSize(min(settings.maxBufferSize, policy.maxLiveHistoryEntries))
            await manager.setProxyPort(activeProxyPort)
            await manager.startBatchTimer()
        }
    }

    func receiveBabylonTransaction(_ transaction: HTTPTransaction) async {
        await sessionManager.addTransaction(transaction)
    }

    func registerBabylonCapture(identity: BabylonCaptureIdentity) {
        guard BabylonCaptureWorkspaceRegistry.shared.register(identity) else {
            return
        }
        var filter = FilterCriteria.empty
        filter.sidebarApp = identity.displayName
        _ = workspaceStore.createWorkspace(title: identity.displayName, filter: filter)
    }
}

// MARK: - BabylonCaptureWorkspaceRegistry

@MainActor
private final class BabylonCaptureWorkspaceRegistry {
    // MARK: Internal

    static let shared = BabylonCaptureWorkspaceRegistry()

    func register(_ identity: BabylonCaptureIdentity) -> Bool {
        registeredSessions.insert("\(identity.clientID):\(identity.sessionID)").inserted
    }

    // MARK: Private

    private var registeredSessions: Set<String> = []
}
