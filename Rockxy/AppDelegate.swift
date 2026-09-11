import AppKit
import os

/// Application delegate handling lifecycle events. Keeps the app running when the
/// last window closes (dock-icon behavior) and will restore system proxy settings
/// on termination once `SystemProxyManager` is implemented.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSUserInterfaceValidations {
    // MARK: Internal

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        let theme = AppSettingsStorage.load().appTheme.rawValue
        AppThemeApplier.apply(theme)

        defaults.register(defaults: [
            Self.identity.defaultsKey("showAlertOnQuit"): true
        ])
        terminationSignalMonitor = TerminationSignalMonitor { signum in
            SystemProxyManager.shared.performEmergencyTerminationCleanup(
                reason: "termination signal \(signum)"
            )
            if !SSLProxyingManager.shared.flushPassthroughPersistence() {
                Self.logger.error("Termination signal: timed out flushing HTTPS fallback state")
            }
        }
        Self.logger.info("Rockxy launched")
        Task {
            // Restore network reachability before any updater or startup service can create a
            // request through a proxy left behind by a previous abnormal termination.
            await SystemProxyStartupRecovery.task.value
            if !RockxyIdentity.isRunningTests {
                AppUpdater.shared.startIfConfigured()
            }
            let applicationSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            if !RockxyIdentity.isRunningTests, let applicationSupportURL {
                let runningApplicationProcesses = Dictionary(
                    NSWorkspace.shared.runningApplications.compactMap { application -> (String, Int32)? in
                        guard !application.isTerminated,
                              application.processIdentifier > 0,
                              let bundleIdentifier = application.bundleIdentifier,
                              let bundleURL = application.bundleURL else
                        {
                            return nil
                        }
                        return (
                            Self.developerApplicationIdentityKey(
                                bundleIdentifier: bundleIdentifier,
                                bundleURL: bundleURL
                            ),
                            application.processIdentifier
                        )
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                Task.detached(priority: .utility) {
                    DeveloperApplicationCaptureConfigurator.reconcileOutstandingPreparations(
                        applicationSupportURL: applicationSupportURL,
                        recordedApplicationProcessIdentifier: { bundleIdentifier, bundlePath in
                            runningApplicationProcesses[
                                Self.developerApplicationIdentityKey(
                                    bundleIdentifier: bundleIdentifier,
                                    bundleURL: URL(fileURLWithPath: bundlePath)
                                )
                            ]
                        },
                        livePreparationHandler: { processIdentifier, preparation in
                            Task { @MainActor in
                                do {
                                    try DeveloperApplicationSettingsRestorationMonitor.shared.startMonitoring(
                                        processIdentifier: processIdentifier,
                                        preparation: preparation
                                    )
                                } catch {
                                    Self.logger.error(
                                        "Could not resume a developer-application settings restoration monitor: \(error.localizedDescription)"
                                    )
                                }
                            }
                        }
                    )
                }
            }
            if !RockxyIdentity.isRunningTests {
                do {
                    try await CertificateManager.shared.ensureRootCA()
                } catch {
                    Self.logger.error("Failed to initialize root CA: \(error.localizedDescription)")
                }
            }
            // Start the shared barrier now, but do not hold independent app services behind the
            // legacy helper's bounded launchd recovery window. The capture UI awaits this same
            // task before it can restore an automatic capture session.
            let helperReconciliation = HelperUpdateStartupReconciliation.task
            await PluginManager.shared.ensureLoadedOnce()
            if !RockxyIdentity.isRunningTests {
                await MCPServerCoordinator.shared.startIfEnabled()
            }
            await helperReconciliation.value
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc
    func newWindowForTab(_ sender: Any?) {
        RockxyWorkspaceWindowManager.shared.openNewWorkspaceTabFromNativeControl()
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(newWindowForTab(_:)) else {
            return true
        }
        return RockxyWorkspaceWindowManager.shared.canCreateWorkspaceTab
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let skipConfirmation = skipNextQuitConfirmation
        skipNextQuitConfirmation = false
        let showAlert = !skipConfirmation
            && UserDefaults.standard.bool(forKey: Self.identity.defaultsKey("showAlertOnQuit"))
        if showAlert {
            let alert = NSAlert()
            alert.messageText = String(localized: "Quit Rockxy?", bundle: RockxyLocalization.bundle)
            if SystemProxyManager.shared.systemProxyEnabled {
                alert.informativeText = String(
                    localized: "Your current recording Request/Response data will be lost. Rockxy will stop capturing and restore macOS proxy settings before quitting.",
                    bundle: RockxyLocalization.bundle
                )
            } else {
                alert.informativeText = String(
                    localized: "Your current recording Request/Response data will be lost.",
                    bundle: RockxyLocalization.bundle
                )
            }
            alert.addButton(withTitle: String(localized: "Quit", bundle: RockxyLocalization.bundle))
            alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
            alert.alertStyle = .warning
            alert.icon = AppIconProvider.appIcon
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = String(localized: "Don’t ask again", bundle: RockxyLocalization.bundle)

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
            await RockxyWorkspaceWindowManager.shared.flushProjectStateForTermination()
            await MCPServerCoordinator.shared.stop()
            let didFlushHTTPSFallbackState = await Task.detached(priority: .utility) {
                SSLProxyingManager.shared.flushPassthroughPersistence()
            }.value
            if !didFlushHTTPSFallbackState {
                Self.logger.error("Quit: timed out flushing HTTPS fallback state")
            }
            MCPHandshakeStore.delete()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func requestQuitForRequiredReopen() {
        skipNextQuitConfirmation = true
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.logger.info("applicationWillTerminate — final proxy cleanup fallback")
        SystemProxyManager.shared.performEmergencyTerminationCleanup(
            reason: "applicationWillTerminate"
        )
        if !SSLProxyingManager.shared.flushPassthroughPersistence() {
            Self.logger.error("applicationWillTerminate: timed out flushing HTTPS fallback state")
        }
        MCPHandshakeStore.delete()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: Private

    private static let identity = RockxyIdentity.current

    private static let logger = Logger(subsystem: identity.logSubsystem, category: "AppDelegate")

    private var skipNextQuitConfirmation = false

    private var terminationSignalMonitor: TerminationSignalMonitor?

    nonisolated private static func developerApplicationIdentityKey(
        bundleIdentifier: String,
        bundleURL: URL
    )
        -> String
    {
        let normalizedIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        return "\(normalizedIdentifier)|\(normalizedPath)"
    }
}
