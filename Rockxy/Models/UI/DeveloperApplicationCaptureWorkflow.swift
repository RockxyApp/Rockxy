import Foundation
import os

// One reversible developer-application preparation and launch, plus the restart-aware settlement
// that decides whether an exited application should be restored or followed to its successor.

nonisolated private let developerApplicationWorkflowLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "DeveloperApplicationCaptureWorkflow"
)

// MARK: - DeveloperApplicationCaptureOutcome

enum DeveloperApplicationCaptureOutcome: Equatable {
    case prepared(displayName: String, restorationMonitorActive: Bool)
    case explicitProxyLaunch(displayName: String)
    case environmentOnly(displayName: String)
    case launchPending(displayName: String, restorationMonitorActive: Bool)
}

// MARK: - DeveloperApplicationTransactionSettlement

enum DeveloperApplicationTransactionSettlement: Equatable, Sendable {
    case restored
    case reboundToSuccessor(processIdentifier: Int32)
}

// MARK: - DeveloperApplicationTransactionSettler

/// Decides what happens to one durable settings transaction once the launched application exits.
///
/// A normal quit restores the original settings exactly as before. An in-place restart or self
/// update is different: the application replaces itself and a successor keeps running from the
/// same bundle or settings scope. Restoring then would strip the settings the user asked Rockxy
/// to prepare, so the transaction is rebound to the successor and monitored there instead.
///
/// Ownership is explicit. This in-process settlement runs first with a short bounded window and
/// is the only writer during that window; the out-of-process monitor waits strictly longer, so it
/// observes the result of this decision — a removed prepared snapshot or a rebound record — and
/// never settles the same transaction a second time.
@MainActor
final class DeveloperApplicationTransactionSettler {
    // MARK: Lifecycle

    init(
        scope: DeveloperApplicationScopeIdentity,
        preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL,
        restorationMonitor: any DeveloperApplicationSettingsRestorationMonitoring,
        runningInstances: (@MainActor () -> [DeveloperApplicationRunningInstance])? = nil,
        successorScanAttempts: Int = 16,
        successorScanInterval: Duration = .milliseconds(250)
    ) {
        self.scope = scope
        self.preparation = preparation
        self.applicationSupportURL = applicationSupportURL
        self.restorationMonitor = restorationMonitor
        if let runningInstances {
            self.runningInstances = runningInstances
        } else {
            let resolvesSettingsAdapters = scope.settingsAdapter != nil
            self.runningInstances = {
                DeveloperApplicationWorkspaceScopeProvider.runningInstances(
                    resolvingSettingsAdapters: resolvesSettingsAdapters
                )
            }
        }
        self.successorScanAttempts = max(1, successorScanAttempts)
        self.successorScanInterval = successorScanInterval
    }

    // MARK: Internal

    private(set) var settlement: DeveloperApplicationTransactionSettlement?

    /// Restores the original settings without any successor handling.
    nonisolated static func restoreSettings(
        _ preparation: DeveloperApplicationSettingsPreparation,
        applicationSupportURL: URL
    ) {
        do {
            try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
                preparation,
                applicationSupportURL: applicationSupportURL
            )
        } catch {
            developerApplicationWorkflowLogger.error(
                "Could not restore temporary developer-application proxy settings: \(error.localizedDescription)"
            )
        }
    }

    /// Records the process identity of the launched instance, so a stale listing of that exact
    /// process can never be mistaken for its successor.
    func bindLaunchedProcess(_ processIdentifier: Int32) {
        guard processIdentifier > 0 else {
            return
        }
        launchedProcessIdentifier = processIdentifier
    }

    /// Settles the transaction after the launch supervisor reported a clean application exit.
    func settleAfterApplicationExit() async {
        guard settlement == nil, !isSettling else {
            return
        }
        isSettling = true
        defer { isSettling = false }

        if let successor = await waitForSuccessor(), await rebind(to: successor) {
            settlement = .reboundToSuccessor(processIdentifier: successor.processIdentifier)
            return
        }

        let preparation = self.preparation
        let applicationSupportURL = self.applicationSupportURL
        await Task.detached(priority: .utility) {
            Self.restoreSettings(preparation, applicationSupportURL: applicationSupportURL)
        }.value
        settlement = .restored
    }

    // MARK: Private

    private let scope: DeveloperApplicationScopeIdentity
    private let preparation: DeveloperApplicationSettingsPreparation
    private let applicationSupportURL: URL
    private let restorationMonitor: any DeveloperApplicationSettingsRestorationMonitoring
    private let runningInstances: @MainActor () -> [DeveloperApplicationRunningInstance]
    private let successorScanAttempts: Int
    private let successorScanInterval: Duration
    private var launchedProcessIdentifier: Int32?
    private var isSettling = false

    /// Bounded wait so a self update that takes a moment to relaunch is still recognized while a
    /// normal quit is never delayed indefinitely.
    private func waitForSuccessor() async -> DeveloperApplicationRunningInstance? {
        for attempt in 0 ..< successorScanAttempts {
            if let successor = DeveloperApplicationScopeResolution.successor(
                candidate: scope,
                excludingProcessIdentifier: launchedProcessIdentifier,
                runningInstances: runningInstances()
            ) {
                return successor
            }
            if attempt < successorScanAttempts - 1 {
                try? await Task.sleep(for: successorScanInterval)
            }
        }
        return nil
    }

    private func rebind(to successor: DeveloperApplicationRunningInstance) async -> Bool {
        let preparation = self.preparation
        let applicationSupportURL = self.applicationSupportURL
        let processIdentifier = successor.processIdentifier
        do {
            try await Task.detached(priority: .utility) {
                // The start signature keeps identity exact: `associateRunningProcess` records the
                // successor's identifier only when that signature can be proven.
                let startSignature = DeveloperApplicationCaptureConfigurator.processStartSignature(
                    processIdentifier: processIdentifier
                )
                try DeveloperApplicationCaptureConfigurator.associateRunningProcess(
                    processIdentifier: processIdentifier,
                    processStartSignature: startSignature,
                    with: preparation,
                    applicationSupportURL: applicationSupportURL
                )
            }.value
        } catch {
            developerApplicationWorkflowLogger.error(
                "Could not rebind a developer-application settings transaction to the successor process: \(error.localizedDescription)"
            )
            return false
        }
        do {
            try restorationMonitor.startMonitoring(
                processIdentifier: processIdentifier,
                preparation: preparation
            )
        } catch {
            developerApplicationWorkflowLogger.error(
                "Could not monitor the successor of a prepared developer application: \(error.localizedDescription)"
            )
        }
        return true
    }
}

// MARK: - DeveloperApplicationCaptureWorkflow

/// Coordinates one reversible application preparation and launch. Keeping this workflow outside
/// the setup view model makes the capability boundary independently testable and keeps UI state
/// updates separate from filesystem and process lifecycle work.
@MainActor
struct DeveloperApplicationCaptureWorkflow {
    // MARK: Internal

    let launcher: DeveloperApplicationLaunching
    let restorationMonitor: DeveloperApplicationSettingsRestorationMonitoring
    let preparationRegistry: DeveloperApplicationPreparationRegistry
    let applicationIsRunning: @MainActor (DeveloperApplicationInstallation) -> Bool
    let applicationSupportURL: URL

    func open(
        appURL: URL,
        context: RockxySetupScriptContext,
        systemProxyConfigured: Bool
    )
        async throws -> DeveloperApplicationCaptureOutcome
    {
        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: appURL)
        try validate(installation, systemProxyConfigured: systemProxyConfigured)

        let preparationKey = try settingsURL(for: installation)?.standardizedFileURL.path
        if let preparationKey, !preparationRegistry.begin(preparationKey) {
            throw DeveloperApplicationCaptureError.preparationInProgress(installation.displayName)
        }
        defer {
            if let preparationKey {
                preparationRegistry.end(preparationKey)
            }
        }

        let preparation = try await prepareSettings(for: installation)
        return try await launch(installation, preparation: preparation, context: context)
    }

    // MARK: Private

    private func validate(
        _ installation: DeveloperApplicationInstallation,
        systemProxyConfigured: Bool
    )
        throws
    {
        guard !applicationIsRunning(installation) else {
            throw DeveloperApplicationCaptureError.applicationIsRunning(installation.displayName)
        }
        if installation.settingsAdapter?.requiresSystemProxy == true, !systemProxyConfigured {
            throw DeveloperApplicationCaptureError.systemProxyRequired(installation.displayName)
        }
    }

    private func settingsURL(for installation: DeveloperApplicationInstallation) throws -> URL? {
        try installation.settingsAdapter.map {
            try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
                for: $0,
                applicationSupportURL: applicationSupportURL
            )
        }
    }

    private func prepareSettings(
        for installation: DeveloperApplicationInstallation
    )
        async throws -> DeveloperApplicationSettingsPreparation?
    {
        let applicationSupportURL = self.applicationSupportURL
        return try await Task.detached {
            try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
                for: installation,
                applicationSupportURL: applicationSupportURL
            )
        }.value
    }

    private func launch(
        _ installation: DeveloperApplicationInstallation,
        preparation: DeveloperApplicationSettingsPreparation?,
        context: RockxySetupScriptContext
    )
        async throws -> DeveloperApplicationCaptureOutcome
    {
        let arguments = installation.launchAdapter?.arguments(context: context) ?? []
        let environment = DeveloperCaptureEnvironmentBuilder.environment(
            context: context,
            baseEnvironment: DeveloperCaptureEnvironmentBuilder.safeInheritedEnvironment(),
            includeJavaProxyProperties: context.targetID == .javaVMs
                || installation.runtimeCapabilities.contains(.javaVirtualMachine)
        )
        let applicationSupportURL = self.applicationSupportURL
        let settler = makeSettler(for: preparation, installation: installation)
        let terminationCallback = makeTerminationCallback(for: settler)

        do {
            let receipt = try await launcher.launch(
                installation,
                arguments: arguments,
                environment: environment,
                onTermination: terminationCallback
            )
            guard let preparation else {
                if receipt.registrationState == .pending {
                    return .launchPending(
                        displayName: installation.displayName,
                        restorationMonitorActive: false
                    )
                }
                if installation.launchAdapter != nil {
                    return .explicitProxyLaunch(displayName: installation.displayName)
                }
                return .environmentOnly(displayName: installation.displayName)
            }
            guard let processIdentifier = receipt.registeredProcessIdentifier else {
                // LaunchServices accepted the request but macOS has not registered the app yet.
                // `/usr/bin/open -W` remains alive for the launched app's lifetime, so bind the
                // durable transaction to that exact supervisor identity until startup recovery
                // can discover the real bundle process. This closes the crash window between a
                // slow first launch and application registration without guessing by app name.
                let lifecycleProcessIdentifier = receipt.lifecycleProcessIdentifier
                settler?.bindLaunchedProcess(lifecycleProcessIdentifier)
                await associateRunningProcess(
                    processIdentifier: lifecycleProcessIdentifier,
                    preparation: preparation
                )
                let monitorActive = startRestorationMonitor(
                    processIdentifier: lifecycleProcessIdentifier,
                    preparation: preparation
                )
                return .launchPending(
                    displayName: installation.displayName,
                    restorationMonitorActive: monitorActive
                )
            }
            settler?.bindLaunchedProcess(processIdentifier)
            await associateRunningProcess(
                processIdentifier: processIdentifier,
                preparation: preparation
            )
            let monitorActive = startRestorationMonitor(
                processIdentifier: processIdentifier,
                preparation: preparation
            )
            if receipt.registrationState == .pending {
                return .launchPending(
                    displayName: installation.displayName,
                    restorationMonitorActive: monitorActive
                )
            }
            return .prepared(
                displayName: installation.displayName,
                restorationMonitorActive: monitorActive
            )
        } catch {
            if let preparation {
                await Task.detached(priority: .utility) {
                    DeveloperApplicationTransactionSettler.restoreSettings(
                        preparation,
                        applicationSupportURL: applicationSupportURL
                    )
                }.value
            }
            throw error
        }
    }

    private func makeSettler(
        for preparation: DeveloperApplicationSettingsPreparation?,
        installation: DeveloperApplicationInstallation
    )
        -> DeveloperApplicationTransactionSettler?
    {
        guard let preparation else {
            return nil
        }
        return DeveloperApplicationTransactionSettler(
            scope: DeveloperApplicationCaptureConfigurator.scopeIdentity(for: installation),
            preparation: preparation,
            applicationSupportURL: applicationSupportURL,
            restorationMonitor: restorationMonitor
        )
    }

    private func makeTerminationCallback(
        for settler: DeveloperApplicationTransactionSettler?
    )
        -> (@MainActor @Sendable () -> Void)?
    {
        guard let settler else {
            return nil
        }
        return {
            Task { @MainActor in
                await settler.settleAfterApplicationExit()
            }
        }
    }

    private func startRestorationMonitor(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    )
        -> Bool
    {
        do {
            try restorationMonitor.startMonitoring(
                processIdentifier: processIdentifier,
                preparation: preparation
            )
            return true
        } catch {
            developerApplicationWorkflowLogger.error(
                "Could not start the developer-application settings restoration monitor: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func associateRunningProcess(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    )
        async
    {
        let applicationSupportURL = self.applicationSupportURL
        do {
            try await Task.detached(priority: .utility) {
                let startSignature = DeveloperApplicationCaptureConfigurator.processStartSignature(
                    processIdentifier: processIdentifier
                )
                try DeveloperApplicationCaptureConfigurator.associateRunningProcess(
                    processIdentifier: processIdentifier,
                    processStartSignature: startSignature,
                    with: preparation,
                    applicationSupportURL: applicationSupportURL
                )
            }.value
        } catch {
            developerApplicationWorkflowLogger.error(
                "Could not associate the launched application with its recovery record: \(error.localizedDescription)"
            )
        }
    }
}
