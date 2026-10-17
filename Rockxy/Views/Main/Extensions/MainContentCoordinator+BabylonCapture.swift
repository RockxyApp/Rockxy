import AppKit
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

    /// `isUpdate` marks a later delivery of a row already handed over (a WebSocket that closed). It
    /// only refreshes a row that is still live, so it can never add the same row a second time when
    /// it overtakes the first delivery; that first delivery then adds the already-finished row.
    func receiveBabylonTransaction(_ transaction: HTTPTransaction, isUpdate: Bool = false) async {
        guard captureRecordingGate.allowsCapture() else {
            return
        }
        guard await ensureProjectCatalogReadyForDataIntake() else {
            Self.logger.error("Dropped Babylon traffic because the Project catalog is unavailable")
            return
        }
        transaction.assignCaptureContextIfMissing(activeCaptureContext)
        await sessionManager.addTransaction(transaction, acceptsNewRows: !isUpdate)
    }

    func registerBabylonCapture(identity: BabylonCaptureIdentity) async {
        guard await ensureProjectCatalogReadyForDataIntake() else {
            Self.logger.error("Skipped Babylon workspace because the Project catalog is unavailable")
            return
        }
        guard BabylonCaptureWorkspaceRegistry.shared.register(identity) else {
            return
        }
        // Every app launch is a new Babylon session; one tab per app and device is enough, and
        // relaunching while debugging must not keep opening tabs or pull focus away.
        guard !workspaceStore.workspaces.contains(where: { $0.filterCriteria.sidebarApp == identity.displayName }) else {
            return
        }
        var filter = FilterCriteria.empty
        filter.sidebarApp = identity.displayName
        _ = workspaceStore.createWorkspace(title: identity.displayName, filter: filter)
    }
}

// MARK: - Babylon trace navigation

extension MainContentCoordinator {
    /// Every captured request the app made in a runtime trace, or in one step of it.
    func babylonRequestCount(
        sourceClientID: String? = nil,
        sessionID: String? = nil,
        traceID: String,
        stepID: String? = nil
    )
        -> Int
    {
        transactions.count { transaction in
            guard let correlation = transaction.babylonCorrelation,
                  sourceClientID == nil || correlation.sourceClientID == sourceClientID,
                  correlation.traceID == traceID,
                  sessionID == nil || correlation.sessionID == sessionID else
            {
                return false
            }
            return stepID == nil || correlation.stepID == stepID
        }
    }

    /// Brings the traffic list forward filtered to one runtime trace (and step), using the same
    /// `trace:` and `step:` tokens a user can type, so the filter stays visible and editable.
    func showBabylonTraceRequests(
        sourceClientID: String? = nil,
        sessionID: String? = nil,
        traceID: String,
        stepID: String? = nil
    ) {
        let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.canBecomeKey }
            ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.canBecomeKey && $0.isVisible }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        var criteria = FilterCriteria.empty
        criteria.searchText = Self.babylonTraceQuery(
            sourceClientID: sourceClientID,
            sessionID: sessionID,
            traceID: traceID,
            stepID: stepID
        )
        filterCriteria = criteria
        sidebarSelection = nil
        activeMainTab = .traffic
        recomputeFilteredTransactions()
    }

    nonisolated static func babylonTraceQuery(
        sourceClientID: String? = nil,
        sessionID: String?,
        traceID: String,
        stepID: String?
    )
        -> String
    {
        var tokens: [String] = []
        if let sourceClientID {
            let escapedClientID = sourceClientID
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            tokens.append("source:\"\(escapedClientID)\"")
        }
        if let sessionID {
            tokens.append("session:\(sessionID)")
        }
        tokens.append("trace:\(traceID)")
        if let stepID {
            tokens.append("step:\(stepID)")
        }
        return tokens.joined(separator: " ")
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
