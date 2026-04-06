import AppKit
import os

/// Application delegate handling lifecycle events. Keeps the app running when the
/// last window closes (dock-icon behavior) and will restore system proxy settings
/// on termination once `SystemProxyManager` is implemented.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: Internal

    private static let identity = RockxyIdentity.current

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        let theme = defaults.string(forKey: Self.identity.defaultsKey("appTheme")) ?? "system"
        AppThemeApplier.apply(theme)

        defaults.register(defaults: [
            Self.identity.defaultsKey("showAlertOnQuit"): true
        ])
        terminationSignalMonitor = TerminationSignalMonitor { signum in
            SystemProxyManager.shared.performEmergencyTerminationCleanup(
                reason: "termination signal \(signum)"
            )
        }
        Self.logger.info("Rockxy launched")
        Task {
            await SystemProxyManager.shared.recoverStaleProxyIfNeeded()
            do {
                try await CertificateManager.shared.ensureRootCA()
            } catch {
                Self.logger.error("Failed to initialize root CA: \(error.localizedDescription)")
            }
            await HelperManager.shared.checkStatus()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let showAlert = UserDefaults.standard.bool(forKey: Self.identity.defaultsKey("showAlertOnQuit"))
        if showAlert {
            let alert = NSAlert()
            alert.messageText = String(localized: "Quit Rockxy?")
            if SystemProxyManager.shared.systemProxyEnabled {
                alert.informativeText = String(
                    localized: "Your current recording Request/Response data will be lost. Rockxy will stop capturing and restore macOS proxy settings before quitting."
                )
            } else {
                alert.informativeText = String(
                    localized: "Your current recording Request/Response data will be lost."
                )
            }
            alert.addButton(withTitle: String(localized: "Quit"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.alertStyle = .warning
            alert.icon = AppIconProvider.appIcon
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = String(localized: "Don’t ask again")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return .terminateCancel
            }

            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(false, forKey: Self.identity.defaultsKey("showAlertOnQuit"))
            }
        }

        Self.logger.info("Rockxy terminating — cleaning up system proxy")
        Task {
            Self.logger.info("Quit: starting proxy restore")
            do {
                try await SystemProxyManager.shared.disableSystemProxy()
                Self.logger.info("Quit: proxy restore completed successfully")
            } catch {
                Self.logger.error("Quit: proxy restore failed — \(error.localizedDescription)")
            }
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.logger.info("applicationWillTerminate — final proxy cleanup fallback")
        SystemProxyManager.shared.performEmergencyTerminationCleanup(
            reason: "applicationWillTerminate"
        )
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: Private

    private static let logger = Logger(subsystem: identity.logSubsystem, category: "AppDelegate")

    private var terminationSignalMonitor: TerminationSignalMonitor?
}
