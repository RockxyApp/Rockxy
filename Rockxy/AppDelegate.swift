import AppKit
import os

// MARK: - AppDelegate

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
        let fallbackManager = SSLProxyingManager.shared
        let terminationLogger = Self.logger
        terminationSignalMonitor = TerminationSignalMonitor { signum in
            SystemProxyManager.shared.performEmergencyTerminationCleanup(
                reason: "termination signal \(signum)"
            )
            if !fallbackManager.flushPassthroughPersistence() {
                terminationLogger.error("Termination signal: timed out flushing HTTPS fallback state")
            }
        }
        if !RockxyIdentity.isRunningTests {
            StayOnTopController.shared.start()
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
                CommandLineControlCoordinator.shared.startIfEnabled()
            }
            await helperReconciliation.value
        }
    }

    /// Finder double-clicks, "Open With", and Dock drops of HAR or session files.
    func application(_ application: NSApplication, open urls: [URL]) {
        ExternalDocumentOpenRouter.shared.open(urls)
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
        // Logout, restart, and shutdown must not wait on a question; a required reopen is not the
        // user leaving Rockxy. Both keep the current proxy settings without asking.
        let mayAskAboutPreviousProxy = !skipConfirmation && !Self.isSystemInitiatedTermination()
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
                let report = try await SystemProxyManager.shared.disableSystemProxy()
                Self.logger.info("Quit: proxy restore completed successfully")
                if report.needsDecision, mayAskAboutPreviousProxy {
                    await PreviousProxyRestorePresenter.resolve(report)
                }
            } catch {
                Self.logger.error("Quit: proxy restore failed — \(error.localizedDescription)")
            }
            await AndroidEmulatorSetupFlow.revertQuietly()
            await RockxyWorkspaceWindowManager.shared.flushProjectStateForTermination()
            await MCPServerCoordinator.shared.stop()
            let fallbackManager = SSLProxyingManager.shared
            let didFlushHTTPSFallbackState = await Task.detached(priority: .utility) {
                fallbackManager.flushPassthroughPersistence()
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
        let fallbackManager = SSLProxyingManager.shared
        let terminationLogger = Self.logger
        // None of this ran off the main thread before, and `SystemProxyManager` is a plain class
        // rather than an actor, so the cleanup executed on whatever thread called it — here, the
        // main one. Its worst case is minutes: a blocking recursive lock, a 5 s cross-process
        // flock acquisition, then five `networksetup` reads per network service at a 10 s cap
        // each, plus a 3 s helper semaphore and, if an earlier disable left a direct backup, six
        // more reads and about seven writes per service. Quit beachballed, and the OS termination
        // watchdog could kill the app mid-restore — leaving the user's system proxy pointed at a
        // port that no longer listens. Returning the main thread promptly makes that *less*
        // likely, not more.
        // Independent steps run side by side against one shared deadline, so a slow proxy restore
        // can neither starve the fallback-state flush nor stretch Quit past the budget. Anything
        // unfinished at the deadline is logged by name inside the barrier.
        TerminationCleanupBarrier.wait(steps: [
            .init(name: "system proxy restore") {
                SystemProxyManager.shared.performEmergencyTerminationCleanup(
                    reason: "applicationWillTerminate"
                )
            },
            .init(name: "HTTPS fallback state flush") {
                if !fallbackManager.flushPassthroughPersistence(timeout: .seconds(2)) {
                    terminationLogger.error("applicationWillTerminate: timed out flushing HTTPS fallback state")
                }
            },
        ])
        MCPHandshakeStore.delete()
        CommandLineControlCoordinator.shared.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: Private

    private static let identity = RockxyIdentity.current

    private static let logger = Logger(subsystem: identity.logSubsystem, category: "AppDelegate")

    private var skipNextQuitConfirmation = false

    private var terminationSignalMonitor: TerminationSignalMonitor?

    /// True when macOS asked Rockxy to quit for a logout, restart, or shutdown. Those quit
    /// events carry a quit reason; a quit the user chose does not.
    private static func isSystemInitiatedTermination() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass,
              event.eventID == kAEQuitApplication else
        {
            return false
        }
        return event.attributeDescriptor(forKeyword: kAEQuitReason) != nil
    }

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

// MARK: - TerminationCleanupBarrier

/// Bounds how long the main thread waits for the final termination cleanup.
///
/// The barrier bounds only the *wait*. Nothing cancels the work, nothing shortens the shared
/// flock or the proxy mutation gate, and no per-command budget changes — restoring the user's
/// system proxy is the point of the whole path, so it is never abandoned to meet a deadline.
/// Expiry therefore has two outcomes. If the process outlives the barrier the cleanup simply
/// completes a moment later. If macOS kills it first the restore is not lost:
/// `recoverOwnedDirectServices` persists the backup narrowed to the services it still owns
/// *before* restoring them, and an incomplete restore deliberately leaves that narrowed record on
/// disk, so `SystemProxyStartupRecovery` — which already runs before any network use on the next
/// launch — and the launchd direct watchdog finish exactly the services that were left behind.
enum TerminationCleanupBarrier {
    // MARK: Internal

    /// One independent piece of final cleanup, named so an overrun can say what it gave up on.
    struct Step: Sendable {
        let name: String
        let work: @Sendable () -> Void
    }

    /// The complete main-thread budget for the final termination cleanup, shared by all steps.
    ///
    /// What it waits on: this runs in `applicationWillTerminate`, after the `.terminateLater`
    /// path in `applicationShouldTerminate` has already restored the proxy, flushed project
    /// state and stopped MCP. In the normal case the direct backup is already cleared, so the
    /// system-proxy step is a lock acquisition plus a file read (milliseconds) and the fallback
    /// flush is one queue hop. The only time it has real work is when the earlier restore
    /// failed or was skipped (force quit paths, signals): then it is a flock attempt (5 s
    /// timeout), then one `networksetup` write set per service. A handful of services restores
    /// in well under a second, so 3 s covers every case that can plausibly finish while the
    /// user is still looking at Quit.
    ///
    /// The unbounded tails — a held flock, a 10 s `networksetup` command, a 3 s helper
    /// semaphore, waiting on an in-flight enable — are exactly what the budget refuses to wait
    /// for. macOS publishes no hard number for `applicationWillTerminate`, but 10 s on Cmd-Q
    /// reads as a hang, and the recovery record described above makes giving up at 3 s safe.
    /// **This number is Stephen's to change.**
    static let budget: TimeInterval = 3

    /// Runs every step on its own detached thread and waits until all finish or `budget`
    /// elapses, whichever is first. The deadline is shared, so the total wait is at most
    /// `budget` regardless of step count. Returns the names of steps still running at expiry
    /// (empty when everything finished); the unfinished work is not cancelled.
    ///
    /// Detached threads rather than a global queue: this work holds a recursive lock and a
    /// cross-process advisory lock for its whole duration, which is not something to park on a
    /// shared queue worker during shutdown.
    @discardableResult
    static func wait(budget: TimeInterval = budget, steps: [Step]) -> [String] {
        let group = DispatchGroup()
        let pending = PendingSteps(steps.map(\.name))
        for step in steps {
            group.enter()
            Thread.detachNewThread {
                step.work()
                pending.finish(step.name)
                group.leave()
            }
        }
        guard group.wait(timeout: .now() + budget) != .success else {
            return []
        }
        let unfinished = pending.names
        let gaveUpOn = unfinished.joined(separator: ", ")
        logger.error(
            "Termination cleanup passed its \(budget, privacy: .public)s budget; terminating without: \(gaveUpOn, privacy: .public)"
        )
        return unfinished
    }

    /// Single-step convenience; returns whether the work finished inside the budget.
    @discardableResult
    static func wait(budget: TimeInterval = budget, for work: @escaping @Sendable () -> Void) -> Bool {
        wait(budget: budget, steps: [Step(name: "cleanup", work: work)]).isEmpty
    }

    // MARK: Private

    private final class PendingSteps: @unchecked Sendable {
        // MARK: Lifecycle

        init(_ names: [String]) {
            remaining = names
        }

        // MARK: Internal

        var names: [String] {
            lock.lock()
            defer { lock.unlock() }
            return remaining
        }

        func finish(_ name: String) {
            lock.lock()
            defer { lock.unlock() }
            if let index = remaining.firstIndex(of: name) {
                remaining.remove(at: index)
            }
        }

        // MARK: Private

        private let lock = NSLock()
        private var remaining: [String]
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "TerminationCleanupBarrier"
    )
}
