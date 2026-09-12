import Foundation
import os

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
            await manager.setOnClientAppEnriched { [weak self] enrichedTransactions in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    self.handleClientAppEnrichment(enrichedTransactions)
                }
            }
            let settings = AppSettingsStorage.load()
            let effectiveBufferSize = min(settings.maxBufferSize, policy.maxLiveHistoryEntries)
            liveHistoryLimit = max(1, effectiveBufferSize)
            await manager.setMaxBufferSize(effectiveBufferSize)
            await manager.setProxyPort(activeProxyPort)
            await manager.startBatchTimer()
        }
    }

    func receiveBabylonTransaction(_ transaction: HTTPTransaction) async {
        guard captureRecordingGate.allowsCapture() else {
            return
        }
        guard await ensureProjectCatalogReadyForDataIntake() else {
            Self.logger.error("Dropped Babylon traffic because the Project catalog is unavailable")
            return
        }
        transaction.assignCaptureContextIfMissing(activeCaptureContext)
        await sessionManager.addTransaction(transaction)
    }

    func registerBabylonCapture(identity: BabylonCaptureIdentity) async {
        guard await ensureProjectCatalogReadyForDataIntake() else {
            Self.logger.error("Skipped Babylon workspace because the Project catalog is unavailable")
            return
        }
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
