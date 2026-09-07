import Darwin
import Foundation
@testable import Rockxy
import Testing

// MARK: - CapabilityTestLauncher

@MainActor
private final class CapabilityTestLauncher: DeveloperApplicationLaunching {
    private(set) var environment: [String: String] = [:]
    var registrationState: DeveloperApplicationRegistrationState = .registered

    func launch(
        _: DeveloperApplicationInstallation,
        arguments _: [String],
        environment: [String: String],
        onTermination _: (@MainActor @Sendable () -> Void)?
    )
        async throws -> DeveloperApplicationLaunchReceipt
    {
        self.environment = environment
        return DeveloperApplicationLaunchReceipt(
            lifecycleProcessIdentifier: getpid(),
            registeredProcessIdentifier: registrationState == .registered ? getpid() : nil,
            registrationState: registrationState
        )
    }
}

// MARK: - CapabilityTestRestorationMonitor

@MainActor
private final class CapabilityTestRestorationMonitor: DeveloperApplicationSettingsRestorationMonitoring {
    private(set) var startCount = 0
    private(set) var monitoredProcessIdentifiers: [Int32] = []

    func startMonitoring(
        processIdentifier: Int32,
        preparation _: DeveloperApplicationSettingsPreparation
    )
        throws
    {
        startCount += 1
        monitoredProcessIdentifiers.append(processIdentifier)
    }
}

// MARK: - DeveloperApplicationCaptureRegressionTests

@Suite("Developer application capture regressions")
struct DeveloperApplicationCaptureRegressionTests {
    // MARK: Internal

    @Test("Metadata-declared JVM receives Java proxy properties from a non-Java setup route")
    @MainActor
    func metadataDeclaredJVMUsesJavaProxyProperties() async throws {
        let fixture = try makeFixture(productMetadataJavaPath: "../jbr/Contents/Home/bin/java")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try makeExecutable(at: fixture.contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java"))
        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)
        let launcher = CapabilityTestLauncher()
        let workflow = workflow(for: fixture, launcher: launcher)

        _ = try await workflow.open(
            appURL: fixture.appURL,
            context: setupContext(targetID: .python),
            systemProxyConfigured: true
        )

        #expect(installation.runtimeCapabilities.contains(.javaVirtualMachine))
        #expect(launcher.environment["JAVA_TOOL_OPTIONS"]?.contains("-Dhttp.proxyPort=8888") == true)
    }

    @Test("jpackage application receives Java proxy properties without product metadata")
    @MainActor
    func jPackageApplicationUsesJavaProxyProperties() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try makeExecutable(
            at: fixture.contentsURL.appendingPathComponent("runtime/Contents/Home/bin/java")
        )
        let configURL = fixture.contentsURL.appendingPathComponent("app/developer-app.cfg")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("[Application]\napp.mainclass=com.example.Main\n".utf8).write(to: configURL)
        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)
        let launcher = CapabilityTestLauncher()

        _ = try await workflow(for: fixture, launcher: launcher).open(
            appURL: fixture.appURL,
            context: setupContext(targetID: .python),
            systemProxyConfigured: false
        )

        #expect(installation.settingsAdapter == nil)
        #expect(installation.runtimeCapabilities.contains(.javaVirtualMachine))
        #expect(launcher.environment["JAVA_TOOL_OPTIONS"] != nil)
    }

    @Test("Untrusted Java metadata paths do not activate runtime or settings capabilities")
    func untrustedJavaMetadataIsRejected() throws {
        let fixture = try makeFixture(productMetadataJavaPath: "../../../../bin/java")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)

        #expect(installation.settingsAdapter == nil)
        #expect(!installation.runtimeCapabilities.contains(.javaVirtualMachine))
    }

    @Test("Malformed launch entries do not hide a later valid JVM capability")
    func partialProductMetadataFallsBackSafely() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let javaPath = "../jbr/Contents/Home/bin/java"
        try makeExecutable(at: fixture.contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java"))
        let metadata: [String: Any] = [
            "productVendor": "Example Tools",
            "dataDirectoryName": "DeveloperIDE2026.2",
            "launch": [
                ["os": "macOS", "javaExecutablePath": NSNull()],
                ["os": "macOS", "javaExecutablePath": javaPath],
            ],
        ]
        let metadataURL = fixture.contentsURL.appendingPathComponent("Resources/product-info.json")
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]).write(to: metadataURL)

        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)

        #expect(installation.settingsAdapter != nil)
        #expect(installation.runtimeCapabilities.contains(.javaVirtualMachine))
    }

    @Test("A pending first launch binds durable recovery to its lifecycle supervisor")
    @MainActor
    func pendingApplicationLaunchMonitorsLifecycleSupervisor() async throws {
        let fixture = try makeFixture(productMetadataJavaPath: "../jbr/Contents/Home/bin/java")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try makeExecutable(at: fixture.contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java"))
        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)
        let adapter = try #require(installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        let launcher = CapabilityTestLauncher()
        launcher.registrationState = .pending
        let monitor = CapabilityTestRestorationMonitor()
        let workflow = DeveloperApplicationCaptureWorkflow(
            launcher: launcher,
            restorationMonitor: monitor,
            preparationRegistry: DeveloperApplicationPreparationRegistry(),
            applicationIsRunning: { _ in false },
            applicationSupportURL: fixture.applicationSupportURL
        )

        let outcome = try await workflow.open(
            appURL: fixture.appURL,
            context: setupContext(targetID: .python),
            systemProxyConfigured: true
        )

        #expect(outcome == .launchPending(displayName: "Developer App", restorationMonitorActive: true))
        #expect(monitor.startCount == 1)
        #expect(monitor.monitoredProcessIdentifiers == [getpid()])

        let reconciled = DeveloperApplicationCaptureConfigurator.reconcileOutstandingPreparations(
            applicationSupportURL: fixture.applicationSupportURL,
            recordedProcessIsAlive: { processIdentifier, startSignature in
                DeveloperApplicationRecoveryLedger.isRecordedProcessAlive(
                    processIdentifier: processIdentifier,
                    expectedStartSignature: startSignature
                )
            }
        )
        #expect(reconciled == 0)
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    @Test("Recovery process identity requires an exact stable start signature")
    func recoveryProcessIdentityRejectsMissingAndMismatchedSignatures() throws {
        let processIdentifier = getpid()
        let signature = try #require(
            DeveloperApplicationCaptureConfigurator.processStartSignature(
                processIdentifier: processIdentifier
            )
        )

        #expect(DeveloperApplicationRecoveryLedger.isRecordedProcessAlive(
            processIdentifier: processIdentifier,
            expectedStartSignature: signature
        ))
        #expect(!DeveloperApplicationRecoveryLedger.isRecordedProcessAlive(
            processIdentifier: processIdentifier,
            expectedStartSignature: nil
        ))
        #expect(!DeveloperApplicationRecoveryLedger.isRecordedProcessAlive(
            processIdentifier: processIdentifier,
            expectedStartSignature: "   "
        ))
        #expect(!DeveloperApplicationRecoveryLedger.isRecordedProcessAlive(
            processIdentifier: processIdentifier,
            expectedStartSignature: signature + "-different"
        ))
        #expect(DeveloperApplicationCaptureConfigurator.processStartSignature(
            processIdentifier: Int32.max
        ) == nil)
    }

    @Test("Out-of-process monitor never restores when process identity is unavailable")
    func restorationMonitorRetainsRecoveryWhenIdentityProbeIsUnavailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-restoration-monitor-probe-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsURL = directory.appendingPathComponent("proxy.settings.xml")
        let backupURL = settingsURL.appendingPathExtension("rockxy-backup")
        let absenceMarkerURL = settingsURL.appendingPathExtension("rockxy-originally-absent")
        let preparedSnapshotURL = settingsURL.appendingPathExtension("rockxy-prepared")
        let recoveryRecordURL = directory.appendingPathComponent("recovery.json")
        let unavailablePSURL = directory.appendingPathComponent("unavailable-ps")
        try Data("original".utf8).write(to: backupURL)
        try Data("prepared".utf8).write(to: settingsURL)
        try Data("prepared".utf8).write(to: preparedSnapshotURL)
        try Data("record".utf8).write(to: recoveryRecordURL)
        try makeExecutable(at: unavailablePSURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", DeveloperApplicationSettingsRestorationMonitor.script,
            "rockxy-settings-restoration-monitor-test", String(getpid()),
            settingsURL.path, backupURL.path, absenceMarkerURL.path, preparedSnapshotURL.path,
            recoveryRecordURL.path, unavailablePSURL.path,
        ]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(try Data(contentsOf: settingsURL) == Data("prepared".utf8))
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(FileManager.default.fileExists(atPath: preparedSnapshotURL.path))
        #expect(FileManager.default.fileExists(atPath: recoveryRecordURL.path))
    }

    @Test("A corrupt prepared snapshot restores the validated original and preserves live bytes")
    func corruptPreparedSnapshotRecoversWithoutDiscardingLiveSettings() throws {
        let fixture = try makeFixture(productMetadataJavaPath: "../jbr/Contents/Home/bin/java")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try makeExecutable(at: fixture.contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java"))
        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)
        let adapter = try #require(installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data(
            "<application><component name=\"HttpConfigurable\"><option name=\"USE_HTTP_PROXY\" value=\"true\" /></component></application>"
                .utf8
        )
        try original.write(to: settingsURL)
        let preparation = try #require(try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: installation,
            applicationSupportURL: fixture.applicationSupportURL
        ))
        let preparedLiveBytes = try Data(contentsOf: settingsURL)
        try Data("<application><component".utf8).write(
            to: preparation.preparedSnapshotURL,
            options: .atomic
        )

        #expect(throws: DeveloperApplicationCaptureError.self) {
            try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
                preparation,
                applicationSupportURL: fixture.applicationSupportURL
            )
        }

        #expect(try Data(contentsOf: settingsURL) == original)
        #expect(!FileManager.default.fileExists(atPath: preparation.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparation.preparedSnapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))
        let conflicts = try FileManager.default.contentsOfDirectory(
            at: settingsURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains("rockxy-conflict-") }
        #expect(conflicts.count == 1)
        #expect(try Data(contentsOf: #require(conflicts.first)) == preparedLiveBytes)
    }

    @Test("Reconciliation rebinds recovery to an already relaunched application")
    func recoveryRebindsToRelaunchedApplicationIdentity() throws {
        let fixture = try makeFixture(productMetadataJavaPath: "../jbr/Contents/Home/bin/java")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try makeExecutable(at: fixture.contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java"))
        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)
        let preparation = try #require(try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: installation,
            applicationSupportURL: fixture.applicationSupportURL
        ))
        try DeveloperApplicationCaptureConfigurator.associateRunningProcess(
            processIdentifier: 42_424,
            processStartSignature: "old-session",
            with: preparation,
            applicationSupportURL: fixture.applicationSupportURL
        )
        var reboundProcessIdentifiers: [Int32] = []

        let liveCount = DeveloperApplicationCaptureConfigurator.reconcileOutstandingPreparations(
            applicationSupportURL: fixture.applicationSupportURL,
            recordedProcessIsAlive: { _, _ in false },
            recordedApplicationProcessIdentifier: { bundleIdentifier, bundlePath in
                #expect(bundleIdentifier == installation.bundleIdentifier)
                #expect(bundlePath == installation.appURL.resolvingSymlinksInPath().path)
                return getpid()
            },
            livePreparationHandler: { processIdentifier, _ in
                reboundProcessIdentifiers.append(processIdentifier)
            }
        )

        #expect(liveCount == 0)
        #expect(reboundProcessIdentifiers == [getpid()])
        #expect(FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))

        let restoredCount = DeveloperApplicationCaptureConfigurator.reconcileOutstandingPreparations(
            applicationSupportURL: fixture.applicationSupportURL,
            recordedProcessIsAlive: { _, _ in false }
        )
        #expect(restoredCount == 1)
        #expect(!FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))
    }

    @Test("A recovery record left without artifacts is settled instead of blocking preparation")
    func artifactFreeRecoveryRecordSettlesAndAllowsPreparation() throws {
        let prepared = try makePreparedFixture()
        defer { try? FileManager.default.removeItem(at: prepared.fixture.rootURL) }
        // A completed restore removed every recovery artifact, then Rockxy was terminated before
        // the ledger entry itself could be removed.
        try FileManager.default.removeItem(at: prepared.preparation.backupURL)
        try FileManager.default.removeItem(at: prepared.preparation.preparedSnapshotURL)
        try prepared.originalData.write(to: prepared.settingsURL, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: prepared.preparation.recoveryRecordURL.path))
        #expect(!FileManager.default.fileExists(atPath: prepared.preparation.absenceMarkerURL.path))

        let second = try #require(try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: prepared.installation,
            applicationSupportURL: prepared.fixture.applicationSupportURL
        ))

        // The stale entry must not be reported as malformed settings and must not consume the
        // current configuration: the new backup is exactly what was on disk before preparation.
        #expect(try Data(contentsOf: second.backupURL) == prepared.originalData)
        let live = try String(contentsOf: prepared.settingsURL, encoding: .utf8)
        #expect(live.contains("USE_PROXY_PAC"))
        #expect(!live.contains("USE_HTTP_PROXY"))
        #expect(FileManager.default.fileExists(atPath: second.recoveryRecordURL.path))

        try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
            second,
            applicationSupportURL: prepared.fixture.applicationSupportURL
        )
        let restored = try String(contentsOf: prepared.settingsURL, encoding: .utf8)
        #expect(restored.contains("USE_HTTP_PROXY"))
        #expect(!restored.contains("USE_PROXY_PAC"))
        #expect(!FileManager.default.fileExists(atPath: second.recoveryRecordURL.path))
    }

    @Test("A running installation sharing one settings scope blocks preparation of another copy")
    func sharedSettingsScopeBlocksPreparation() throws {
        let first = try makeFixture(productMetadataJavaPath: "../jbr/Contents/Home/bin/java")
        defer { try? FileManager.default.removeItem(at: first.rootURL) }
        let second = try makeFixture(productMetadataJavaPath: "../jbr/Contents/Home/bin/java")
        defer { try? FileManager.default.removeItem(at: second.rootURL) }
        let distinct = try makeFixture(
            productMetadataJavaPath: "../jbr/Contents/Home/bin/java",
            dataDirectoryName: "DeveloperIDE2026.3"
        )
        defer { try? FileManager.default.removeItem(at: distinct.rootURL) }
        for fixture in [first, second, distinct] {
            try makeExecutable(at: fixture.contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java"))
        }

        let candidate = try DeveloperApplicationCaptureConfigurator.scopeIdentity(
            for: DeveloperApplicationCaptureConfigurator.installation(at: first.appURL)
        )
        let sameScope = DeveloperApplicationCaptureConfigurator.scopeIdentity(
            forBundleAt: second.appURL
        )
        let otherScope = DeveloperApplicationCaptureConfigurator.scopeIdentity(
            forBundleAt: distinct.appURL
        )

        #expect(candidate.bundlePath != sameScope.bundlePath)
        #expect(candidate.settingsAdapter != nil)
        #expect(sameScope.settingsAdapter == candidate.settingsAdapter)
        #expect(otherScope.settingsAdapter != candidate.settingsAdapter)
        #expect(DeveloperApplicationScopeResolution.blockingInstance(
            candidate: candidate,
            runningInstances: [
                DeveloperApplicationRunningInstance(processIdentifier: 4_242, scope: sameScope),
            ]
        )?.processIdentifier == 4_242)
        #expect(DeveloperApplicationScopeResolution.blockingInstance(
            candidate: candidate,
            runningInstances: [
                DeveloperApplicationRunningInstance(processIdentifier: 4_243, scope: otherScope),
            ]
        ) == nil)
    }

    @Test("Applications without a settings adapter keep exact bundle-path running detection")
    func genericApplicationsKeepExactPathRunningDetection() throws {
        let first = try makeFixture()
        defer { try? FileManager.default.removeItem(at: first.rootURL) }
        let second = try makeFixture()
        defer { try? FileManager.default.removeItem(at: second.rootURL) }

        let candidate = try DeveloperApplicationCaptureConfigurator.scopeIdentity(
            for: DeveloperApplicationCaptureConfigurator.installation(at: first.appURL)
        )
        let sameInstallation = DeveloperApplicationCaptureConfigurator.scopeIdentity(
            forBundleAt: first.appURL
        )
        let otherInstallation = DeveloperApplicationCaptureConfigurator.scopeIdentity(
            forBundleAt: second.appURL
        )

        #expect(candidate.settingsAdapter == nil)
        #expect(DeveloperApplicationScopeResolution.sharesSettingsScope(candidate, sameInstallation))
        #expect(!DeveloperApplicationScopeResolution.sharesSettingsScope(candidate, otherInstallation))
    }

    @Test("An in-place restart rebinds the transaction to the successor instead of restoring")
    @MainActor
    func inPlaceRestartRebindsToSuccessor() async throws {
        let prepared = try makePreparedFixture()
        defer { try? FileManager.default.removeItem(at: prepared.fixture.rootURL) }
        let preparedBytes = try Data(contentsOf: prepared.settingsURL)
        let monitor = CapabilityTestRestorationMonitor()
        let scope = DeveloperApplicationCaptureConfigurator.scopeIdentity(for: prepared.installation)
        let settler = makeSettler(
            for: prepared,
            monitor: monitor,
            runningInstances: [
                DeveloperApplicationRunningInstance(processIdentifier: getpid(), scope: scope),
            ]
        )
        settler.bindLaunchedProcess(42_424)

        await settler.settleAfterApplicationExit()

        #expect(settler.settlement == DeveloperApplicationTransactionSettlement.reboundToSuccessor(
            processIdentifier: getpid()
        ))
        #expect(monitor.monitoredProcessIdentifiers == [getpid()])
        #expect(try Data(contentsOf: prepared.settingsURL) == preparedBytes)
        #expect(FileManager.default.fileExists(atPath: prepared.preparation.recoveryRecordURL.path))
        #expect(FileManager.default.fileExists(atPath: prepared.preparation.backupURL.path))
    }

    @Test("An ordinary application exit still restores the original settings")
    @MainActor
    func ordinaryExitRestoresOriginalSettings() async throws {
        let prepared = try makePreparedFixture()
        defer { try? FileManager.default.removeItem(at: prepared.fixture.rootURL) }
        let monitor = CapabilityTestRestorationMonitor()
        let settler = makeSettler(for: prepared, monitor: monitor, runningInstances: [])
        settler.bindLaunchedProcess(42_424)

        await settler.settleAfterApplicationExit()

        #expect(settler.settlement == DeveloperApplicationTransactionSettlement.restored)
        #expect(monitor.startCount == 0)
        let restored = try String(contentsOf: prepared.settingsURL, encoding: .utf8)
        #expect(restored.contains("USE_HTTP_PROXY"))
        #expect(!restored.contains("USE_PROXY_PAC"))
        #expect(!FileManager.default.fileExists(atPath: prepared.preparation.recoveryRecordURL.path))
    }

    @Test("A different application running at exit never claims the transaction")
    @MainActor
    func mismatchedRunningIdentityStillRestores() async throws {
        let prepared = try makePreparedFixture()
        defer { try? FileManager.default.removeItem(at: prepared.fixture.rootURL) }
        let unrelated = try makeFixture(
            productMetadataJavaPath: "../jbr/Contents/Home/bin/java",
            dataDirectoryName: "DeveloperIDE2026.3"
        )
        defer { try? FileManager.default.removeItem(at: unrelated.rootURL) }
        try makeExecutable(at: unrelated.contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java"))
        let monitor = CapabilityTestRestorationMonitor()
        let settler = makeSettler(
            for: prepared,
            monitor: monitor,
            runningInstances: [
                DeveloperApplicationRunningInstance(
                    processIdentifier: getpid(),
                    scope: DeveloperApplicationCaptureConfigurator.scopeIdentity(forBundleAt: unrelated.appURL)
                ),
            ]
        )
        settler.bindLaunchedProcess(42_424)

        await settler.settleAfterApplicationExit()

        #expect(settler.settlement == DeveloperApplicationTransactionSettlement.restored)
        #expect(monitor.startCount == 0)
        let restored = try String(contentsOf: prepared.settingsURL, encoding: .utf8)
        #expect(restored.contains("USE_HTTP_PROXY"))
        #expect(!FileManager.default.fileExists(atPath: prepared.preparation.recoveryRecordURL.path))
    }

    @Test("Out-of-process monitor stands down when a successor runs from the same bundle")
    func restorationMonitorFollowsInPlaceRestart() throws {
        let scenario = try makeMonitorScenario(processTable: [
            "4242 \(monitorBundlePath)/Contents/MacOS/developer-app",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.directory) }

        let status = try scenario.run()

        #expect(status == 0)
        #expect(try Data(contentsOf: scenario.settingsURL) == Data("prepared".utf8))
        #expect(FileManager.default.fileExists(atPath: scenario.backupURL.path))
        #expect(FileManager.default.fileExists(atPath: scenario.preparedSnapshotURL.path))
        #expect(FileManager.default.fileExists(atPath: scenario.recoveryRecordURL.path))
    }

    @Test("Out-of-process monitor restores after an ordinary exit and clears its marker")
    func restorationMonitorRestoresWithoutSuccessor() throws {
        let scenario = try makeMonitorScenario(processTable: [
            "4242 /Applications/Unrelated.app/Contents/MacOS/unrelated",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.directory) }

        let status = try scenario.run()

        #expect(status == 0)
        #expect(try Data(contentsOf: scenario.settingsURL) == Data("original".utf8))
        #expect(!FileManager.default.fileExists(atPath: scenario.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: scenario.preparedSnapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: scenario.recoveryRecordURL.path))
        #expect(!FileManager.default.fileExists(atPath: scenario.monitorMarkerURL.path))
    }

    @Test("Out-of-process monitor never treats a matching process name as a successor")
    func restorationMonitorRejectsProcessNameEvidence() throws {
        let scenario = try makeMonitorScenario(processTable: [
            "4242 /Applications/Other App.app/Contents/MacOS/developer-app",
            "4243 /tmp/wrapper\(monitorBundlePath)/Contents/MacOS/developer-app",
        ])
        defer { try? FileManager.default.removeItem(at: scenario.directory) }

        let status = try scenario.run()

        #expect(status == 0)
        #expect(try Data(contentsOf: scenario.settingsURL) == Data("original".utf8))
        #expect(!FileManager.default.fileExists(atPath: scenario.recoveryRecordURL.path))
    }

    @Test("A live restoration monitor marker is reused instead of duplicated on relaunch")
    func liveRestorationMonitorMarkerIsReused() throws {
        let directory = try makeTemporaryDirectory(named: "rockxy-monitor-marker")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recoveryRecordURL = directory.appendingPathComponent("recovery.json")
        let markerURL = DeveloperApplicationRestorationMonitorLedger.markerURL(for: recoveryRecordURL)
        let signature = try #require(
            DeveloperApplicationCaptureConfigurator.processStartSignature(processIdentifier: getpid())
        )
        try DeveloperApplicationRestorationMonitorLedger.writeMarker(
            monitorProcessIdentifier: getpid(),
            monitorStartSignature: signature,
            monitoredProcessIdentifier: 4_242,
            to: markerURL
        )

        #expect(markerURL.lastPathComponent == "recovery.monitor")
        #expect(!DeveloperApplicationRestorationMonitorLedger.shouldStartMonitor(
            markerURL: markerURL,
            monitoredProcessIdentifier: 4_242
        ))
        // A marker that watches a different application process cannot suppress a new monitor.
        #expect(DeveloperApplicationRestorationMonitorLedger.shouldStartMonitor(
            markerURL: markerURL,
            monitoredProcessIdentifier: 4_243
        ))
    }

    @Test("Stale, missing, or corrupt monitor markers always start a fresh monitor")
    func staleRestorationMonitorMarkerIsReplaced() throws {
        let directory = try makeTemporaryDirectory(named: "rockxy-monitor-marker-stale")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recoveryRecordURL = directory.appendingPathComponent("recovery.json")
        let markerURL = DeveloperApplicationRestorationMonitorLedger.markerURL(for: recoveryRecordURL)

        #expect(DeveloperApplicationRestorationMonitorLedger.shouldStartMonitor(
            markerURL: markerURL,
            monitoredProcessIdentifier: 4_242
        ))

        try DeveloperApplicationRestorationMonitorLedger.writeMarker(
            monitorProcessIdentifier: Int32.max,
            monitorStartSignature: "proc-v1:1:1",
            monitoredProcessIdentifier: 4_242,
            to: markerURL
        )
        #expect(DeveloperApplicationRestorationMonitorLedger.shouldStartMonitor(
            markerURL: markerURL,
            monitoredProcessIdentifier: 4_242
        ))

        try Data("not a marker".utf8).write(to: markerURL, options: .atomic)
        #expect(DeveloperApplicationRestorationMonitorLedger.marker(at: markerURL) == nil)
        #expect(DeveloperApplicationRestorationMonitorLedger.shouldStartMonitor(
            markerURL: markerURL,
            monitoredProcessIdentifier: 4_242
        ))
    }

    // MARK: Private

    private struct Fixture {
        let rootURL: URL
        let appURL: URL
        let contentsURL: URL
        let applicationSupportURL: URL
    }

    private struct PreparedFixture {
        let fixture: Fixture
        let installation: DeveloperApplicationInstallation
        let settingsURL: URL
        let preparation: DeveloperApplicationSettingsPreparation
        let originalData: Data
    }

    private struct MonitorScenario {
        let directory: URL
        let settingsURL: URL
        let backupURL: URL
        let absenceMarkerURL: URL
        let preparedSnapshotURL: URL
        let recoveryRecordURL: URL
        let monitorMarkerURL: URL
        let processTableURL: URL
        let bundlePath: String

        func run() throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                "-c", DeveloperApplicationSettingsRestorationMonitor.script,
                "rockxy-settings-restoration-monitor-test", String(Int32.max),
                settingsURL.path, backupURL.path, absenceMarkerURL.path, preparedSnapshotURL.path,
                recoveryRecordURL.path, processTableURL.path, bundlePath, "1",
            ]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
    }

    /// Bundle path used by the out-of-process monitor scenarios. It never has to exist on disk:
    /// the monitor compares it against the executable paths reported by the process table.
    private var monitorBundlePath: String {
        "/Applications/Developer App.app"
    }

    private func makeFixture(
        productMetadataJavaPath: String? = nil,
        productVendor: String = "Example Tools",
        dataDirectoryName: String = "DeveloperIDE2026.2"
    )
        throws -> Fixture
    {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rockxy-Capability-App-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Developer App.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.capability-app",
            "CFBundleName": "Developer App",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "developer-app",
        ]
        try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        ).write(to: contentsURL.appendingPathComponent("Info.plist"))
        if let productMetadataJavaPath {
            let metadata: [String: Any] = [
                "productVendor": productVendor,
                "dataDirectoryName": dataDirectoryName,
                "launch": [[
                    "os": "macOS",
                    "javaExecutablePath": productMetadataJavaPath,
                ]],
            ]
            try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
                .write(to: resourcesURL.appendingPathComponent("product-info.json"))
        }
        return Fixture(
            rootURL: rootURL,
            appURL: appURL,
            contentsURL: contentsURL,
            applicationSupportURL: rootURL.appendingPathComponent("Application Support", isDirectory: true)
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePreparedFixture(
        dataDirectoryName: String = "DeveloperIDE2026.2"
    )
        throws -> PreparedFixture
    {
        let fixture = try makeFixture(
            productMetadataJavaPath: "../jbr/Contents/Home/bin/java",
            dataDirectoryName: dataDirectoryName
        )
        try makeExecutable(at: fixture.contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java"))
        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)
        let adapter = try #require(installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data(
            "<application><component name=\"HttpConfigurable\"><option name=\"USE_HTTP_PROXY\" value=\"true\" /></component></application>"
                .utf8
        )
        try original.write(to: settingsURL)
        let preparation = try #require(try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: installation,
            applicationSupportURL: fixture.applicationSupportURL
        ))
        return PreparedFixture(
            fixture: fixture,
            installation: installation,
            settingsURL: settingsURL,
            preparation: preparation,
            originalData: original
        )
    }

    @MainActor
    private func makeSettler(
        for prepared: PreparedFixture,
        monitor: CapabilityTestRestorationMonitor,
        runningInstances: [DeveloperApplicationRunningInstance]
    )
        -> DeveloperApplicationTransactionSettler
    {
        DeveloperApplicationTransactionSettler(
            scope: DeveloperApplicationCaptureConfigurator.scopeIdentity(for: prepared.installation),
            preparation: prepared.preparation,
            applicationSupportURL: prepared.fixture.applicationSupportURL,
            restorationMonitor: monitor,
            runningInstances: { runningInstances },
            successorScanAttempts: 1,
            successorScanInterval: .milliseconds(1)
        )
    }

    /// Builds a self-contained transaction on disk plus a deterministic process table, so the
    /// out-of-process monitor can be exercised without launching or observing a real application.
    private func makeMonitorScenario(processTable: [String]) throws -> MonitorScenario {
        let directory = try makeTemporaryDirectory(named: "rockxy-restoration-monitor-restart")
        let settingsURL = directory.appendingPathComponent("proxy.settings.xml")
        let recoveryRecordURL = directory.appendingPathComponent("recovery.json")
        let monitorMarkerURL = DeveloperApplicationRestorationMonitorLedger.markerURL(
            for: recoveryRecordURL
        )
        let processTableURL = directory.appendingPathComponent("process-table")
        try Data("original".utf8).write(to: settingsURL.appendingPathExtension("rockxy-backup"))
        try Data("prepared".utf8).write(to: settingsURL)
        try Data("prepared".utf8).write(to: settingsURL.appendingPathExtension("rockxy-prepared"))
        try Data("record".utf8).write(to: recoveryRecordURL)
        try Data("marker".utf8).write(to: monitorMarkerURL)
        try makeProcessTableCommand(at: processTableURL, entries: processTable)
        return MonitorScenario(
            directory: directory,
            settingsURL: settingsURL,
            backupURL: settingsURL.appendingPathExtension("rockxy-backup"),
            absenceMarkerURL: settingsURL.appendingPathExtension("rockxy-originally-absent"),
            preparedSnapshotURL: settingsURL.appendingPathExtension("rockxy-prepared"),
            recoveryRecordURL: recoveryRecordURL,
            monitorMarkerURL: monitorMarkerURL,
            processTableURL: processTableURL,
            bundlePath: monitorBundlePath
        )
    }

    private func makeProcessTableCommand(at url: URL, entries: [String]) throws {
        let printedEntries = entries
            .map { "printf '%s\\n' \"\($0)\"" }
            .joined(separator: "\n")
        let script = """
        #!/bin/sh
        if [ "$1" = "-A" ]; then
        \(printedEntries)
        fi
        exit 0
        """
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    @MainActor
    private func workflow(
        for fixture: Fixture,
        launcher: CapabilityTestLauncher
    )
        -> DeveloperApplicationCaptureWorkflow
    {
        DeveloperApplicationCaptureWorkflow(
            launcher: launcher,
            restorationMonitor: CapabilityTestRestorationMonitor(),
            preparationRegistry: DeveloperApplicationPreparationRegistry(),
            applicationIsRunning: { _ in false },
            applicationSupportURL: fixture.applicationSupportURL
        )
    }

    private func setupContext(targetID: SetupTarget.ID) -> RockxySetupScriptContext {
        RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 8_888,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: targetID
        )
    }
}
