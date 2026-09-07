import Foundation
import os

// MARK: - App update reconciliation

extension HelperManager {
    /// Only an older helper with the approval-preserving refresh capability is safe to refresh
    /// automatically. An unknown/newer protocol is never downgraded, and a protocol-1/2 helper
    /// remains usable until the user explicitly chooses the one-time manual update path.
    nonisolated static func shouldAutomaticallyRefreshAfterAppUpdate(_ status: HelperStatus) -> Bool {
        switch status {
        case .installedOutdated:
            true
        case .notInstalled,
             .requiresApproval,
             .installedCompatible,
             .installedIncompatible,
             .unreachable,
             .signingMismatch:
            false
        }
    }

    /// Reconciles an already installed helper with the helper embedded in the newly launched app.
    ///
    /// `SMAppService` keeps the daemon inside the app bundle. A protocol-3-or-newer helper can terminate
    /// itself after acknowledging this request, allowing launchd to resolve the executable from
    /// the updated app bundle while preserving the existing Background Items approval. Older
    /// helpers are deliberately left working rather than automatically unregistering them.
    func refreshAfterAppUpdateIfNeeded() async {
        await checkStatus()
        guard Self.shouldAutomaticallyRefreshAfterAppUpdate(status),
              let installedInfo,
              HelperCompatibilityPolicy.supportsExecutableRefresh(
                  protocolVersion: installedInfo.protocolVersion
              )
        else {
            return
        }

        Self.appUpdateLogger.info("Refreshing helper executable without unregistering its approved service")
        do {
            try await HelperConnection.shared.refreshHelperExecutable()
            let delays: [Duration] = [
                .milliseconds(250),
                .milliseconds(500),
                .seconds(1),
                .seconds(2),
                .seconds(3),
            ]
            var refreshed = false
            for delay in delays {
                try? await Task.sleep(for: delay)
                await checkStatus()
                if status == .installedCompatible {
                    refreshed = true
                    break
                }
            }
            guard refreshed else {
                Self.appUpdateLogger.warning("Helper executable refresh did not reach the bundled version")
                return
            }
            Self.appUpdateLogger.info("Helper executable refresh completed")
        } catch {
            Self.appUpdateLogger.error("Automatic helper refresh failed: \(error.localizedDescription)")
        }
    }

    private static let appUpdateLogger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperAppUpdate"
    )
}
