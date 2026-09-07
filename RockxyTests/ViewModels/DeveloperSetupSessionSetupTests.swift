import Foundation
@testable import Rockxy
import Testing

@MainActor
private final class RecordingDeveloperApplicationLauncher: DeveloperApplicationLaunching {
    private(set) var launches: [(DeveloperApplicationInstallation, [String], [String: String])] = []
    private(set) var terminationHandler: (@MainActor @Sendable () -> Void)?
    var launchError: (any Error)?
    var processIdentifier: Int32 = 42_424
    var registeredProcessIdentifier: Int32 = 52_424
    var registrationState: DeveloperApplicationRegistrationState = .registered

    @discardableResult
    func launch(
        _ installation: DeveloperApplicationInstallation,
        arguments: [String],
        environment: [String: String],
        onTermination: (@MainActor @Sendable () -> Void)?
    ) async throws -> DeveloperApplicationLaunchReceipt {
        launches.append((installation, arguments, environment))
        terminationHandler = onTermination
        if let launchError {
            throw launchError
        }
        return DeveloperApplicationLaunchReceipt(
            lifecycleProcessIdentifier: processIdentifier,
            registeredProcessIdentifier: registrationState == .registered ? registeredProcessIdentifier : nil,
            registrationState: registrationState
        )
    }
}

@MainActor
private final class SuspendingDeveloperApplicationLauncher: DeveloperApplicationLaunching {
    private(set) var launchCount = 0
    private var continuation: CheckedContinuation<DeveloperApplicationLaunchReceipt, Never>?

    func launch(
        _: DeveloperApplicationInstallation,
        arguments _: [String],
        environment _: [String: String],
        onTermination _: (@MainActor @Sendable () -> Void)?
    ) async throws -> DeveloperApplicationLaunchReceipt {
        launchCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume(returning: DeveloperApplicationLaunchReceipt(
            lifecycleProcessIdentifier: 42_425,
            registeredProcessIdentifier: 52_425,
            registrationState: .registered
        ))
        continuation = nil
    }
}

@MainActor
private final class RecordingSettingsRestorationMonitor: DeveloperApplicationSettingsRestorationMonitoring {
    private(set) var starts: [(Int32, DeveloperApplicationSettingsPreparation)] = []
    var startError: (any Error)?

    func startMonitoring(
        processIdentifier: Int32,
        preparation: DeveloperApplicationSettingsPreparation
    ) throws {
        starts.append((processIdentifier, preparation))
        if let startError {
            throw startError
        }
    }
}

@Suite("Developer setup session setup")
struct DeveloperSetupSessionSetupTests {
    // MARK: Internal

    @Test("Generated setup script exports scoped proxy and certificate hints")
    func generatedSetupScriptExportsScopedProxyAndCertificateHints() {
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_090,
            certificatePath: "/tmp/Rockxy CA.pem",
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy"
        )

        let script = RockxySetupScriptBuilder.script(context: context)

        #expect(script.contains("export ROCKXY_SETUP_SESSION=1"))
        #expect(script.contains("export HTTP_PROXY=\"http://127.0.0.1:9090\""))
        #expect(script.contains("export HTTPS_PROXY=\"http://127.0.0.1:9090\""))
        #expect(script.contains("export ALL_PROXY=\"http://127.0.0.1:9090\""))
        #expect(script.contains("export NODE_EXTRA_CA_CERTS=\"$ROCKXY_ROOT_CA_PATH\""))
        #expect(!script.contains("export SSL_CERT_FILE="))
        #expect(!script.contains("export REQUESTS_CA_BUNDLE="))
        #expect(!script.contains("export CURL_CA_BUNDLE="))
        #expect(!script.contains("export GIT_SSL_CAINFO="))
        #expect(script.contains("export npm_config_https_proxy=\"$HTTPS_PROXY\""))
        #expect(!script.contains("export NODE_OPTIONS="))
    }

    @Test("Java VMs script injects JAVA_TOOL_OPTIONS proxy properties once and preserves the base")
    func javaScriptInjectsProxyPropertiesAndPreservesBase() {
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_090,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .javaVMs
        )

        let script = RockxySetupScriptBuilder.script(context: context)

        #expect(script.contains("-Dhttp.proxyHost=127.0.0.1"))
        #expect(script.contains("-Dhttp.proxyPort=9090"))
        #expect(script.contains("-Dhttps.proxyHost=127.0.0.1"))
        #expect(script.contains("-Dhttps.proxyPort=9090"))
        #expect(script.contains("export JAVA_TOOL_OPTIONS="))
        #expect(script.contains("${JAVA_TOOL_OPTIONS//$ROCKXY_JAVA_PROXY_OPTS/}"))
        // The proxy option string is emitted exactly once so re-sourcing cannot stack it.
        #expect(script.components(separatedBy: "-Dhttp.proxyHost=127.0.0.1").count - 1 == 1)
    }

    @Test("Non-Java runtime script never injects JAVA_TOOL_OPTIONS")
    func nonJavaScriptOmitsJavaProxyProperties() {
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_090,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .python
        )

        let script = RockxySetupScriptBuilder.script(context: context)

        #expect(script.contains("JAVA_TOOL_OPTIONS") == false)
        #expect(script.contains("-Dhttp.proxyHost") == false)
    }

    @Test("Sourcing the Java script twice keeps existing JAVA_TOOL_OPTIONS and one proxy block")
    func javaScriptPreservesExistingOptionsAcrossReSourcing() throws {
        try assertJavaScriptSourcing(shellPath: "/bin/zsh")
    }

    @Test("Sourcing the Java script twice in bash keeps existing options and one proxy block")
    func javaScriptPreservesExistingOptionsAcrossReSourcingBash() throws {
        try assertJavaScriptSourcing(shellPath: "/bin/bash")
    }

    @Test("Manual source command quotes Application Support paths")
    func manualSourceCommandQuotesApplicationSupportPaths() {
        let scriptURL =
            URL(fileURLWithPath: "/Users/stephen/Library/Application Support/Rockxy/setup/rockxy_env_setup.sh")

        let command = RockxySetupScriptBuilder.sourceCommand(scriptURL: scriptURL)

        #expect(command ==
            "set -a 2>/dev/null || true; source \"/Users/stephen/Library/Application Support/Rockxy/setup/rockxy_env_setup.sh\"; set +a 2>/dev/null || true")
        #expect(!command.contains("__rockxy_setup"))
    }

    @Test("Generated setup command runs in zsh")
    func generatedSetupCommandRunsInZsh() throws {
        try assertGeneratedSetupCommandRuns(shellPath: "/bin/zsh")
    }

    @Test("Generated setup command runs in bash")
    func generatedSetupCommandRunsInBash() throws {
        try assertGeneratedSetupCommandRuns(shellPath: "/bin/bash")
    }

    @Test("Generated setup command reports when the script is missing")
    func generatedSetupCommandReportsWhenTheScriptIsMissing() throws {
        try assertGeneratedSetupCommandReportsMissingScript(shellPath: "/bin/zsh")
    }

    @Test("Generated setup script URL follows the active app support identity")
    func generatedSetupScriptURLFollowsTheActiveAppSupportIdentity() {
        let identity = RockxyIdentity(infoDictionary: [
            "CFBundleIdentifier": "com.amunx.rockxy",
            "RockxyAppSupportDirectoryName": "com.amunx.rockxy",
        ])

        let scriptURL = RockxySetupScriptBuilder.generatedScriptURL(identity: identity)

        #expect(scriptURL.path.contains("/com.amunx.rockxy/setup/rockxy_env_setup.sh"))
        #expect(!scriptURL.path.contains("com.amunx.rockxy.community"))
    }

    @Test("Setup script is written atomically with executable permissions")
    func setupScriptIsWrittenAtomicallyWithExecutablePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-setup-script-\(UUID().uuidString)", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("rockxy_env_setup.sh")
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_091,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy"
        )

        try RockxySetupScriptBuilder.writeScript(context: context, scriptURL: scriptURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(permissions?.intValue == 0o700)
        #expect(contents.contains("export HTTP_PROXY=\"http://127.0.0.1:9091\""))
        #expect(contents.contains("Export or trust the Rockxy root certificate"))
    }

    @Test("Automatic Setup explains generic application capture boundaries and active endpoint")
    @MainActor
    func applicationGuidanceNamesBoundariesAndEndpoint() {
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: MainContentCoordinator(),
            targetID: .python
        )

        let guidance = viewModel.developerApplicationGuidanceText

        #expect(guidance.contains("app-level proxy"))
        #expect(guidance.contains("Containers"))
        #expect(guidance.contains("emulators"))
        #expect(guidance.contains("already-running processes"))
        #expect(guidance.contains(viewModel.proxyEndpointText))
        #expect(viewModel.proxyEndpointText.hasPrefix("127.0.0.1:"))
    }

    @Test("Recognized application proxy setup enables Auto-detect and preserves unrelated settings")
    func recognizedProxySetupPreservesUnrelatedSettings() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let adapter = try #require(fixture.installation.settingsAdapter)

        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = """
        <application>
          <component name="UnrelatedComponent">
            <option name="KEEP_ME" value="yes" />
          </component>
          <component name="HttpConfigurable">
            <option name="USE_HTTP_PROXY" value="true" />
            <option name="USE_PAC_URL" value="true" />
            <option name="PROXY_TYPE_IS_SOCKS" value="true" />
            <option name="PROXY_HOST" value="old.example" />
          </component>
        </application>
        """
        try Data(existing.utf8).write(to: settingsURL)

        let optionalPreparation = try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: fixture.installation,
            applicationSupportURL: fixture.applicationSupportURL
        )
        let preparation = try #require(optionalPreparation)

        let updated = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(updated.contains("UnrelatedComponent"))
        #expect(updated.contains("KEEP_ME"))
        #expect(updated.contains("USE_PROXY_PAC"))
        #expect(updated.contains("value=\"true\""))
        #expect(updated.contains("PROXY_HOST"))
        #expect(!updated.contains("USE_HTTP_PROXY"))
        #expect(!updated.contains("USE_PAC_URL"))
        #expect(!updated.contains("PROXY_TYPE_IS_SOCKS"))
        #expect(FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))

        try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
            preparation,
            applicationSupportURL: fixture.applicationSupportURL
        )
        let restored = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(restored.contains("UnrelatedComponent"))
        #expect(restored.contains("KEEP_ME"))
        #expect(restored.contains("USE_HTTP_PROXY"))
        #expect(restored.contains("USE_PAC_URL"))
        #expect(restored.contains("PROXY_TYPE_IS_SOCKS"))
        #expect(restored.contains("PROXY_HOST"))
        #expect(!restored.contains("USE_PROXY_PAC"))
        #expect(!FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))
    }

    @Test("Outstanding application settings are reconciled after Rockxy restarts")
    func outstandingPreparationIsReconciledAtLaunch() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("<application><component name=\"HttpConfigurable\"><option name=\"USE_HTTP_PROXY\" value=\"true\" /></component></application>".utf8)
        try original.write(to: settingsURL)
        let preparation = try #require(try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: fixture.installation,
            applicationSupportURL: fixture.applicationSupportURL
        ))

        #expect(FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))
        #expect(try Data(contentsOf: settingsURL) != original)

        let reconciled = DeveloperApplicationCaptureConfigurator.reconcileOutstandingPreparations(
            applicationSupportURL: fixture.applicationSupportURL
        )

        #expect(reconciled == 1)
        let restored = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(restored.contains("USE_HTTP_PROXY"))
        #expect(!restored.contains("USE_PROXY_PAC"))
        #expect(!FileManager.default.fileExists(atPath: preparation.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparation.preparedSnapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))
    }

    @Test("Reconciliation skips a live process and an actively prepared settings path")
    func reconciliationRespectsLivenessAndPreparationLock() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let preparation = try #require(try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: fixture.installation,
            applicationSupportURL: fixture.applicationSupportURL
        ))
        try DeveloperApplicationCaptureConfigurator.associateRunningProcess(
            processIdentifier: 42_424,
            processStartSignature: "stable-process-start",
            with: preparation,
            applicationSupportURL: fixture.applicationSupportURL
        )
        let registry = DeveloperApplicationPreparationRegistry()
        var resumedProcessIdentifiers: [Int32] = []

        let liveCount = DeveloperApplicationCaptureConfigurator.reconcileOutstandingPreparations(
            applicationSupportURL: fixture.applicationSupportURL,
            preparationRegistry: registry,
            recordedProcessIsAlive: { processIdentifier, startSignature in
                processIdentifier == 42_424 && startSignature == "stable-process-start"
            },
            livePreparationHandler: { processIdentifier, resumedPreparation in
                resumedProcessIdentifiers.append(processIdentifier)
                #expect(resumedPreparation.settingsURL == preparation.settingsURL)
            }
        )
        #expect(liveCount == 0)
        #expect(resumedProcessIdentifiers == [42_424])
        #expect(FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))

        #expect(registry.begin(preparation.settingsURL.standardizedFileURL.path))
        let lockedCount = DeveloperApplicationCaptureConfigurator.reconcileOutstandingPreparations(
            applicationSupportURL: fixture.applicationSupportURL,
            preparationRegistry: registry,
            recordedProcessIsAlive: { _, _ in false }
        )
        #expect(lockedCount == 0)
        #expect(FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))
        registry.end(preparation.settingsURL.standardizedFileURL.path)

        let exitedCount = DeveloperApplicationCaptureConfigurator.reconcileOutstandingPreparations(
            applicationSupportURL: fixture.applicationSupportURL,
            preparationRegistry: registry,
            recordedProcessIsAlive: { _, _ in false }
        )
        #expect(exitedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))
    }

    @Test("Application rewrites preserve unrelated changes while Rockxy restores only its proxy selector")
    func restorationMergesApplicationRewrite() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = """
        <application><component name="HttpConfigurable">
          <option name="USE_HTTP_PROXY" value="true" />
          <option name="PROXY_HOST" value="corporate.example" />
        </component></application>
        """
        try Data(original.utf8).write(to: settingsURL)
        let preparation = try #require(try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: fixture.installation,
            applicationSupportURL: fixture.applicationSupportURL
        ))

        let applicationRewrite = """
        <application><component name="HttpConfigurable">
          <option name="USE_PROXY_PAC" value="true" />
          <option name="USE_HTTP_PROXY" value="false" />
          <option name="PROXY_HOST" value="corporate.example" />
          <option name="PROXY_EXCEPTIONS" value="internal.example" />
        </component><component name="NewApplicationState" /></application>
        """
        try Data(applicationRewrite.utf8).write(to: settingsURL, options: .atomic)

        try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
            preparation,
            applicationSupportURL: fixture.applicationSupportURL
        )

        let restored = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(restored.contains("USE_HTTP_PROXY"))
        #expect(restored.contains("value=\"true\""))
        #expect(!restored.contains("USE_PROXY_PAC"))
        #expect(restored.contains("PROXY_EXCEPTIONS"))
        #expect(restored.contains("NewApplicationState"))
    }

    @Test("Malformed live settings are quarantined and the original proxy settings are recovered")
    func malformedLiveSettingsRecoveryPreservesBothCopies() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("<application><component name=\"HttpConfigurable\"><option name=\"USE_HTTP_PROXY\" value=\"true\" /></component></application>".utf8)
        try original.write(to: settingsURL)
        let preparation = try #require(try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: fixture.installation,
            applicationSupportURL: fixture.applicationSupportURL
        ))
        let malformed = Data("<application><component".utf8)
        try malformed.write(to: settingsURL, options: .atomic)

        var conflictPath: String?
        do {
            try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
                preparation,
                applicationSupportURL: fixture.applicationSupportURL
            )
            Issue.record("Expected malformed live settings to produce a recovery conflict")
        } catch let error as DeveloperApplicationCaptureError {
            if case let .settingsRecoveryConflict(path) = error {
                conflictPath = path
            } else {
                Issue.record("Expected settingsRecoveryConflict, got \(error)")
            }
        } catch {
            Issue.record(error)
        }

        #expect(conflictPath != nil)
        #expect(try Data(contentsOf: settingsURL) == original)
        #expect(!FileManager.default.fileExists(atPath: preparation.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparation.preparedSnapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparation.recoveryRecordURL.path))
        let conflicts = try FileManager.default.contentsOfDirectory(
            at: settingsURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains("rockxy-conflict-") }
        #expect(conflicts.count == 1)
        #expect(try Data(contentsOf: #require(conflicts.first)) == malformed)
    }

    @Test("Recognized proxy setup derives the settings path from installed product metadata")
    func recognizedProxySetupUsesInstalledMetadata() throws {
        let fixture = try makeApplicationFixture(
            dataDirectoryName: "DeveloperIDE2026.2",
            productVendor: "Example Tools"
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let preparation = try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: fixture.installation,
            applicationSupportURL: fixture.applicationSupportURL
        )
        let settingsURL = try #require(preparation?.settingsURL)

        #expect(settingsURL.path.contains("Example Tools/DeveloperIDE2026.2/options/proxy.settings.xml"))
        let created = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(created.contains("HttpConfigurable"))
        #expect(created.contains("USE_PROXY_PAC"))
    }

    @Test("Malformed recognized proxy settings are never overwritten")
    func malformedRecognizedProxySettingsRemainUnchanged() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let malformed = Data("<application><component".utf8)
        try malformed.write(to: settingsURL)

        #expect(throws: DeveloperApplicationCaptureError.malformedProxySettings) {
            try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
                for: fixture.installation,
                applicationSupportURL: fixture.applicationSupportURL
            )
        }
        #expect(try Data(contentsOf: settingsURL) == malformed)
    }

    @Test("An unrelated product-info schema falls back to scoped launch environment")
    func unrelatedProductInfoIsNotRejected() throws {
        let fixture = try makeApplicationFixture(includeMetadata: false, parseInstallation: false)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let metadataURL = fixture.appURL.appendingPathComponent("Contents/Resources/product-info.json")
        let unrelated = try JSONSerialization.data(
            withJSONObject: ["product": "Example", "channel": "stable"],
            options: [.sortedKeys]
        )
        try unrelated.write(to: metadataURL)

        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)

        #expect(installation.settingsAdapter == nil)
    }

    @Test("Application launch environment covers common toolchains and preserves user state")
    func applicationLaunchEnvironmentIsBroadAndIdempotent() {
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 8_888,
            certificatePath: "/tmp/Rockxy Root.pem",
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .javaVMs
        )

        let environment = DeveloperCaptureEnvironmentBuilder.environment(
            context: context,
            baseEnvironment: [
                "PATH": "/custom/bin",
                "NODE_OPTIONS": "--trace-warnings",
                "JAVA_TOOL_OPTIONS": "-Dfile.encoding=UTF-8 -Dhttp.proxyHost=old",
                "ROCKXY_JAVA_PROXY_OPTS": "-Dhttp.proxyHost=old",
            ]
        )
        let refreshedEnvironment = DeveloperCaptureEnvironmentBuilder.environment(
            context: context,
            baseEnvironment: environment
        )

        #expect(environment["HTTP_PROXY"] == "http://127.0.0.1:8888")
        #expect(environment["HTTPS_PROXY"] == "http://127.0.0.1:8888")
        #expect(environment["npm_config_https_proxy"] == "http://127.0.0.1:8888")
        #expect(environment["ROCKXY_SETUP_SESSION"] == "1")
        #expect(environment["NODE_EXTRA_CA_CERTS"] == "/tmp/Rockxy Root.pem")
        #expect(environment["SSL_CERT_FILE"] == nil)
        #expect(environment["GIT_SSL_CAINFO"] == nil)
        #expect(environment["PIP_CERT"] == nil)
        #expect(environment["CARGO_HTTP_CAINFO"] == nil)
        #expect(environment["PATH"] == "/custom/bin")
        #expect(environment["NODE_OPTIONS"] == "--trace-warnings")
        #expect(environment["JAVA_TOOL_OPTIONS"]?.contains("-Dfile.encoding=UTF-8") == true)
        #expect(environment["JAVA_TOOL_OPTIONS"]?.contains("-Dhttp.proxyHost=old") == false)
        #expect(environment["JAVA_TOOL_OPTIONS"]?.contains("-Dhttps.proxyPort=8888") == true)
        #expect(refreshedEnvironment["NODE_OPTIONS"] == "--trace-warnings")
        #expect(refreshedEnvironment["JAVA_TOOL_OPTIONS"] == environment["JAVA_TOOL_OPTIONS"])

        let minimalEnvironment = DeveloperCaptureEnvironmentBuilder.environment(context: context)
        #expect(minimalEnvironment["PATH"] == nil)
        #expect(minimalEnvironment["SSH_AUTH_SOCK"] == nil)
        #expect(minimalEnvironment["NODE_EXTRA_CA_CERTS"] == "/tmp/Rockxy Root.pem")
    }

    @Test("Safe inherited launch environment keeps process essentials without copying secrets")
    func safeInheritedLaunchEnvironmentIsAllowlisted() {
        let inherited = DeveloperCaptureEnvironmentBuilder.safeInheritedEnvironment(from: [
            "HOME": "/Users/example",
            "USER": "example",
            "LANG": "en_US.UTF-8",
            "LC_CTYPE": "UTF-8",
            "PATH": "/custom/bin",
            "API_TOKEN": "secret",
            "SSH_AUTH_SOCK": "/tmp/agent.sock",
        ])

        #expect(inherited["HOME"] == "/Users/example")
        #expect(inherited["USER"] == "example")
        #expect(inherited["LANG"] == "en_US.UTF-8")
        #expect(inherited["LC_CTYPE"] == "UTF-8")
        #expect(inherited["PATH"] == "/custom/bin")
        #expect(inherited["API_TOKEN"] == nil)
        #expect(inherited["SSH_AUTH_SOCK"] == "/tmp/agent.sock")

        let fallback = DeveloperCaptureEnvironmentBuilder.safeInheritedEnvironment(from: [:])
        #expect(fallback["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test("Recognized application flow writes settings and launches the selected application")
    @MainActor
    func recognizedApplicationFlowConfiguresAndLaunches() async throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        coordinator.isSystemProxyConfigured = true
        let launcher = RecordingDeveloperApplicationLauncher()
        let restorationMonitor = RecordingSettingsRestorationMonitor()
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            targetID: .python,
            applicationLauncher: launcher,
            settingsRestorationMonitor: restorationMonitor,
            systemProxyConfiguredProvider: { coordinator.isSystemProxyConfigured },
            applicationSupportURL: fixture.applicationSupportURL
        )

        await viewModel.openDeveloperApplication(at: fixture.appURL)

        let launch = try #require(launcher.launches.first)
        #expect(launcher.launches.count == 1)
        #expect(launch.0 == fixture.installation)
        #expect(launch.2["HTTP_PROXY"] == "http://127.0.0.1:8888")
        #expect(launch.2["JAVA_TOOL_OPTIONS"]?.contains("-Dhttps.proxyPort=8888") == true)
        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(settings.contains("USE_PROXY_PAC"))
        #expect(viewModel.statusMessage?.contains("recognized proxy settings") == true)
        #expect(launcher.terminationHandler != nil)
        #expect(restorationMonitor.starts.count == 1)
        #expect(restorationMonitor.starts[0].0 == launcher.registeredProcessIdentifier)
        #expect(restorationMonitor.starts[0].1.settingsURL == settingsURL)

        launcher.terminationHandler?()
        // Normal restoration now waits through the bounded in-place-restart window before
        // settling the transaction. Keep this integration assertion outside that timing race.
        for _ in 0 ..< 200 where FileManager.default.fileExists(atPath: settingsURL.path) {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
    }

    @Test("Concurrent setup windows cannot prepare the same application settings")
    @MainActor
    func concurrentPreparationIsRejected() async throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        coordinator.isSystemProxyConfigured = true
        let launcher = SuspendingDeveloperApplicationLauncher()
        let registry = DeveloperApplicationPreparationRegistry()
        let first = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            applicationLauncher: launcher,
            preparationRegistry: registry,
            systemProxyConfiguredProvider: { coordinator.isSystemProxyConfigured },
            applicationSupportURL: fixture.applicationSupportURL
        )
        let second = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            applicationLauncher: launcher,
            preparationRegistry: registry,
            systemProxyConfiguredProvider: { coordinator.isSystemProxyConfigured },
            applicationSupportURL: fixture.applicationSupportURL
        )

        let firstLaunch = Task { await first.openDeveloperApplication(at: fixture.appURL) }
        while launcher.launchCount == 0 {
            await Task.yield()
        }
        await second.openDeveloperApplication(at: fixture.appURL)

        #expect(launcher.launchCount == 1)
        #expect(second.statusMessage?.contains("already preparing") == true)
        launcher.finish()
        await firstLaunch.value
    }

    @Test("Restoration preserves proxy settings changed by the application during the session")
    func restorationDoesNotOverwriteNewerApplicationSettings() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("<application><component name=\"HttpConfigurable\" /></application>".utf8)
        try original.write(to: settingsURL)
        let optionalPreparation = try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
            for: fixture.installation,
            applicationSupportURL: fixture.applicationSupportURL
        )
        let preparation = try #require(optionalPreparation)
        let userChanged = Data("<application><component name=\"UserChanged\" /></application>".utf8)
        try userChanged.write(to: settingsURL, options: .atomic)

        try DeveloperApplicationCaptureConfigurator.restoreRecognizedSettings(
            preparation,
            applicationSupportURL: fixture.applicationSupportURL
        )

        #expect(try Data(contentsOf: settingsURL) == userChanged)
        #expect(!FileManager.default.fileExists(atPath: preparation.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparation.absenceMarkerURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparation.preparedSnapshotURL.path))
    }

    @Test("Out-of-process restoration monitor restores an unchanged prepared settings file")
    func restorationMonitorScriptRestoresAfterApplicationExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-restoration-monitor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsURL = directory.appendingPathComponent("proxy.settings.xml")
        let backupURL = directory.appendingPathComponent("proxy.settings.xml.rockxy-backup")
        let absenceMarkerURL = directory.appendingPathComponent("proxy.settings.xml.rockxy-originally-absent")
        let preparedSnapshotURL = directory.appendingPathComponent("proxy.settings.xml.rockxy-prepared")
        let recoveryRecordURL = directory.appendingPathComponent("recovery.json")
        let original = Data("original".utf8)
        let prepared = Data("prepared".utf8)
        try original.write(to: backupURL)
        try prepared.write(to: settingsURL)
        try prepared.write(to: preparedSnapshotURL)
        try Data("record".utf8).write(to: recoveryRecordURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            DeveloperApplicationSettingsRestorationMonitor.script,
            "rockxy-settings-restoration-monitor-test",
            String(Int32.max),
            settingsURL.path,
            backupURL.path,
            absenceMarkerURL.path,
            preparedSnapshotURL.path,
            recoveryRecordURL.path,
        ]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(try Data(contentsOf: settingsURL) == original)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: preparedSnapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: recoveryRecordURL.path))
    }

    @Test("Out-of-process monitor retains recovery data when the application rewrites settings")
    func restorationMonitorRetainsSemanticReconciliationInputs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy-restoration-monitor-rewrite-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsURL = directory.appendingPathComponent("proxy.settings.xml")
        let backupURL = settingsURL.appendingPathExtension("rockxy-backup")
        let absenceMarkerURL = settingsURL.appendingPathExtension("rockxy-originally-absent")
        let preparedSnapshotURL = settingsURL.appendingPathExtension("rockxy-prepared")
        let recoveryRecordURL = directory.appendingPathComponent("recovery.json")
        try Data("original".utf8).write(to: backupURL)
        try Data("rewritten".utf8).write(to: settingsURL)
        try Data("prepared".utf8).write(to: preparedSnapshotURL)
        try Data("record".utf8).write(to: recoveryRecordURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", DeveloperApplicationSettingsRestorationMonitor.script,
            "rockxy-settings-restoration-monitor-test", String(Int32.max),
            settingsURL.path, backupURL.path, absenceMarkerURL.path, preparedSnapshotURL.path,
            recoveryRecordURL.path,
        ]
        try process.run()
        process.waitUntilExit()

        #expect(try Data(contentsOf: settingsURL) == Data("rewritten".utf8))
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(FileManager.default.fileExists(atPath: preparedSnapshotURL.path))
        #expect(FileManager.default.fileExists(atPath: recoveryRecordURL.path))
    }

    @Test("Recognized proxy settings are restored when application launch fails")
    @MainActor
    func failedApplicationLaunchRestoresProxySettings() async throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("<application><component name=\"HttpConfigurable\" /></application>".utf8)
        try original.write(to: settingsURL)

        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        coordinator.isSystemProxyConfigured = true
        let launcher = RecordingDeveloperApplicationLauncher()
        launcher.launchError = CocoaError(.fileNoSuchFile)
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            applicationLauncher: launcher,
            systemProxyConfiguredProvider: { coordinator.isSystemProxyConfigured },
            applicationSupportURL: fixture.applicationSupportURL
        )

        await viewModel.openDeveloperApplication(at: fixture.appURL)

        let restored = try String(contentsOf: settingsURL, encoding: .utf8)
        #expect(restored.contains("HttpConfigurable"))
        #expect(!restored.contains("USE_PROXY_PAC"))
        #expect(!FileManager.default.fileExists(atPath: settingsURL.appendingPathExtension("rockxy-backup").path))
        #expect(viewModel.statusMessage?.contains("Could not open") == true)
    }

    @Test("Application setup flow never mutates settings while Rockxy proxy is stopped")
    @MainActor
    func applicationSetupFlowRequiresRunningProxy() async throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = false
        let launcher = RecordingDeveloperApplicationLauncher()
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            targetID: .javaVMs,
            applicationLauncher: launcher,
            systemProxyConfiguredProvider: { coordinator.isSystemProxyConfigured },
            applicationSupportURL: fixture.applicationSupportURL
        )

        await viewModel.openDeveloperApplication(at: fixture.appURL)

        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        #expect(launcher.launches.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
        #expect(viewModel.statusMessage?.contains("Start the Rockxy proxy") == true)
    }

    @Test("Running application is rejected before settings mutation or relaunch")
    @MainActor
    func runningApplicationIsRejectedBeforeMutation() async throws {
        let fixture = try makeApplicationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        coordinator.isSystemProxyConfigured = true
        let launcher = RecordingDeveloperApplicationLauncher()
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            applicationLauncher: launcher,
            applicationIsRunning: { _ in true },
            systemProxyConfiguredProvider: { coordinator.isSystemProxyConfigured },
            applicationSupportURL: fixture.applicationSupportURL
        )

        await viewModel.openDeveloperApplication(at: fixture.appURL)

        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        #expect(launcher.launches.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
        #expect(viewModel.statusMessage?.contains("Quit Developer App completely") == true)
    }

    @Test("Recognized app-level settings use live macOS System Proxy state instead of cached UI state")
    @MainActor
    func recognizedSettingsRequireSystemProxy() async throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        coordinator.isSystemProxyConfigured = true
        let launcher = RecordingDeveloperApplicationLauncher()
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            targetID: .python,
            applicationLauncher: launcher,
            systemProxyConfiguredProvider: { false },
            applicationSupportURL: fixture.applicationSupportURL
        )

        await viewModel.openDeveloperApplication(at: fixture.appURL)

        #expect(launcher.launches.isEmpty)
        #expect(viewModel.statusMessage?.contains("Enable macOS System Proxy") == true)
    }

    @Test("Unknown application schemas are launched without mutating preferences")
    @MainActor
    func unknownApplicationUsesScopedEnvironmentOnly() async throws {
        let fixture = try makeApplicationFixture(includeMetadata: false)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        let launcher = RecordingDeveloperApplicationLauncher()
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            targetID: .python,
            applicationLauncher: launcher,
            systemProxyConfiguredProvider: { coordinator.isSystemProxyConfigured },
            applicationSupportURL: fixture.applicationSupportURL
        )

        await viewModel.openDeveloperApplication(at: fixture.appURL)

        #expect(launcher.launches.count == 1)
        #expect(launcher.launches[0].0.settingsAdapter == nil)
        #expect(launcher.launches[0].2["JAVA_TOOL_OPTIONS"] == nil)
        #expect(viewModel.statusMessage?.contains("configure that app-level proxy separately") == true)
    }

    @Test("Detected Chromium runtime receives explicit scoped proxy arguments")
    @MainActor
    func chromiumRuntimeReceivesProxyArguments() async throws {
        let fixture = try makeApplicationFixture(
            includeMetadata: false,
            includeChromiumRuntime: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let coordinator = MainContentCoordinator()
        coordinator.isProxyRunning = true
        let launcher = RecordingDeveloperApplicationLauncher()
        let viewModel = DeveloperSetupSessionSetupViewModel(
            coordinator: coordinator,
            applicationLauncher: launcher,
            systemProxyConfiguredProvider: { coordinator.isSystemProxyConfigured },
            applicationSupportURL: fixture.applicationSupportURL
        )

        await viewModel.openDeveloperApplication(at: fixture.appURL)

        let launch = try #require(launcher.launches.first)
        #expect(launch.0.launchAdapter == .chromiumProxy)
        #expect(launch.1.contains("--proxy-server=http://127.0.0.1:8888"))
        #expect(!launch.1.contains(where: { $0.hasPrefix("--proxy-bypass-list=") }))
        #expect(viewModel.statusMessage?.contains("explicit scoped proxy") == true)
        #expect(viewModel.statusMessage?.contains("configure that app-level proxy separately") == false)
    }

    @Test("Unsafe settings metadata is rejected before filesystem access")
    func unsafeSettingsMetadataIsRejected() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "../Escape", parseInstallation: false)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        #expect(throws: DeveloperApplicationCaptureError.unsafeSettingsLocation) {
            try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)
        }
    }

    @Test("Oversized unrelated application metadata falls back without decoding")
    func oversizedApplicationMetadataFallsBack() throws {
        let fixture = try makeApplicationFixture(includeMetadata: false)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let metadataURL = fixture.appURL
            .appendingPathComponent("Contents/Resources/product-info.json", isDirectory: false)
        try Data(count: Int(DeveloperApplicationCaptureConfigurator.maximumMetadataBytes) + 1)
            .write(to: metadataURL)

        let installation = try DeveloperApplicationCaptureConfigurator.installation(at: fixture.appURL)
        #expect(installation.settingsAdapter == nil)
    }

    @Test("Oversized proxy settings are rejected without replacement")
    func oversizedProxySettingsAreRejected() throws {
        let fixture = try makeApplicationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let adapter = try #require(fixture.installation.settingsAdapter)
        let settingsURL = try DeveloperApplicationCaptureConfigurator.proxySettingsURL(
            for: adapter,
            applicationSupportURL: fixture.applicationSupportURL
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data(count: Int(DeveloperApplicationCaptureConfigurator.maximumProxySettingsBytes) + 1)
        try original.write(to: settingsURL)

        #expect(throws: DeveloperApplicationCaptureError.malformedProxySettings) {
            try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
                for: fixture.installation,
                applicationSupportURL: fixture.applicationSupportURL
            )
        }
        #expect(try Data(contentsOf: settingsURL) == original)
    }

    @Test("Symlinked settings roots cannot escape Application Support")
    func symlinkedSettingsRootIsRejected() throws {
        let fixture = try makeApplicationFixture(dataDirectoryName: "DeveloperIDE2026.2")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let outsideURL = fixture.rootURL.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.applicationSupportURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.applicationSupportURL.appendingPathComponent("Example Tools"),
            withDestinationURL: outsideURL
        )

        #expect(throws: DeveloperApplicationCaptureError.unsafeSettingsLocation) {
            try DeveloperApplicationCaptureConfigurator.prepareRecognizedSettings(
                for: fixture.installation,
                applicationSupportURL: fixture.applicationSupportURL
            )
        }
    }

    @Test("Firefox setup uses a generated profile proxy preference file")
    func firefoxSetupUsesGeneratedProfileProxyPreferenceFile() {
        let userJS = RockxySetupSessionLauncher.firefoxUserJS(proxyHost: "127.0.0.1", proxyPort: 9_090)

        #expect(userJS.contains("user_pref(\"network.proxy.type\", 1);"))
        #expect(userJS.contains("user_pref(\"network.proxy.http\", \"127.0.0.1\");"))
        #expect(userJS.contains("user_pref(\"network.proxy.ssl_port\", 9090);"))
        #expect(userJS.contains("user_pref(\"network.proxy.no_proxies_on\", \"localhost, 127.0.0.1, ::1\");"))
    }

    // MARK: Private

    private struct ShellResult {
        let exitCode: Int32
        let output: String
    }

    private struct ApplicationFixture {
        let rootURL: URL
        let appURL: URL
        let applicationSupportURL: URL
        let installation: DeveloperApplicationInstallation
    }

    private func makeApplicationFixture(
        dataDirectoryName: String = "DeveloperIDE2026.2",
        productVendor: String = "Example Tools",
        includeMetadata: Bool = true,
        includeChromiumRuntime: Bool = false,
        includeJPackageRuntime: Bool = false,
        parseInstallation: Bool = true
    ) throws -> ApplicationFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rockxy-Developer-App-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Developer App.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let executableName = "developer-app"
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.developer-app",
            "CFBundleName": "Developer App",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": executableName,
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        if includeChromiumRuntime {
            try FileManager.default.createDirectory(
                at: contentsURL.appendingPathComponent(
                    "Frameworks/Electron Framework.framework",
                    isDirectory: true
                ),
                withIntermediateDirectories: true
            )
        }

        if includeMetadata {
            let javaURL = contentsURL.appendingPathComponent("jbr/Contents/Home/bin/java")
            try FileManager.default.createDirectory(
                at: javaURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: javaURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: javaURL.path
            )
            let productInfo: [String: Any] = [
                "name": "Developer App",
                "productVendor": productVendor,
                "dataDirectoryName": dataDirectoryName,
                "launch": [[
                    "os": "macOS",
                    "javaExecutablePath": "../jbr/Contents/Home/bin/java",
                ]],
            ]
            let productInfoData = try JSONSerialization.data(withJSONObject: productInfo, options: [.sortedKeys])
            try productInfoData.write(to: resourcesURL.appendingPathComponent("product-info.json"))
        }

        if includeJPackageRuntime {
            let javaURL = contentsURL.appendingPathComponent("runtime/Contents/Home/bin/java")
            let configURL = contentsURL.appendingPathComponent("app/\(executableName).cfg")
            try FileManager.default.createDirectory(
                at: javaURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: javaURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: javaURL.path
            )
            try Data("[Application]\napp.mainclass=com.example.Main\n".utf8).write(to: configURL)
        }

        let applicationSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        let installation: DeveloperApplicationInstallation
        if !parseInstallation {
            installation = DeveloperApplicationInstallation(
                appURL: appURL,
                bundleIdentifier: "com.example.developer-app",
                displayName: "Developer App",
                settingsAdapter: includeMetadata
                    ? .xmlHTTPProxyAutoDetect(
                        vendorDirectory: productVendor,
                        dataDirectoryName: dataDirectoryName
                    )
                    : nil,
                launchAdapter: includeChromiumRuntime ? .chromiumProxy : nil,
                runtimeCapabilities: includeMetadata || includeJPackageRuntime
                    ? [.javaVirtualMachine]
                    : []
            )
        } else {
            installation = try DeveloperApplicationCaptureConfigurator.installation(at: appURL)
        }
        return ApplicationFixture(
            rootURL: rootURL,
            appURL: appURL,
            applicationSupportURL: applicationSupportURL,
            installation: installation
        )
    }

    private func assertGeneratedSetupCommandRuns(shellPath: String) throws {
        try #require(FileManager.default.fileExists(atPath: shellPath))

        let scriptURL = try writeTemporarySetupScript()
        let command = RockxySetupScriptBuilder.sourceCommand(scriptURL: scriptURL) +
            "; printf 'HTTP_PROXY=%s\\nROCKXY_SETUP_SESSION=%s\\n' \"$HTTP_PROXY\" \"$ROCKXY_SETUP_SESSION\""

        let result = try runShell(shellPath: shellPath, command: command)

        #expect(result.exitCode == 0)
        #expect(result.output.contains("HTTP_PROXY=http://127.0.0.1:9092"))
        #expect(result.output.contains("ROCKXY_SETUP_SESSION=1"))
        #expect(result.output.contains("Rockxy setup session is ready: http://127.0.0.1:9092"))
    }

    private func assertJavaScriptSourcing(shellPath: String) throws {
        try #require(FileManager.default.fileExists(atPath: shellPath))

        let scriptURL = try writeTemporaryJavaSetupScript()
        let sourceCommand = RockxySetupScriptBuilder.sourceCommand(scriptURL: scriptURL)
        // A harmless value added before the first source and another added between
        // sources prove both survive while the Rockxy proxy block remains singular.
        let command = "export JAVA_TOOL_OPTIONS=\"-Dfile.encoding=UTF-8\"; " +
            "\(sourceCommand); " +
            "export JAVA_TOOL_OPTIONS=\"$JAVA_TOOL_OPTIONS -Duser.country=VN\"; " +
            "\(sourceCommand); " +
            "printf 'JAVA_TOOL_OPTIONS=%s\\n' \"$JAVA_TOOL_OPTIONS\""

        let result = try runShell(shellPath: shellPath, command: command)

        #expect(result.exitCode == 0)
        #expect(result.output.contains("-Dfile.encoding=UTF-8"))
        #expect(result.output.contains("-Duser.country=VN"))
        #expect(result.output.contains("-Dhttp.proxyHost=127.0.0.1"))
        let proxyBlockCount = result.output.components(separatedBy: "-Dhttp.proxyHost=127.0.0.1").count - 1
        #expect(proxyBlockCount == 1)
    }

    private func writeTemporaryJavaSetupScript() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy java setup \(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support/Rockxy/setup", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("rockxy_env_setup.sh")
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_093,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy",
            targetID: .javaVMs
        )

        try RockxySetupScriptBuilder.writeScript(context: context, scriptURL: scriptURL)
        return scriptURL
    }

    private func assertGeneratedSetupCommandReportsMissingScript(shellPath: String) throws {
        try #require(FileManager.default.fileExists(atPath: shellPath))

        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy missing setup \(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support/Rockxy/setup/rockxy_env_setup.sh")
        let command = RockxySetupScriptBuilder.sourceCommand(scriptURL: missingURL)
        let result = try runShell(shellPath: shellPath, command: command)

        #expect(!result.output.contains("Rockxy setup session is ready"))
        #expect(result.output.contains(missingURL.path))
    }

    private func writeTemporarySetupScript() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rockxy setup command \(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support/Rockxy/setup", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("rockxy_env_setup.sh")
        let context = RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: 9_092,
            certificatePath: nil,
            generatedAt: Date(timeIntervalSince1970: 0),
            appName: "Rockxy"
        )

        try RockxySetupScriptBuilder.writeScript(context: context, scriptURL: scriptURL)
        return scriptURL
    }

    private func runShell(shellPath: String, command: String) throws -> ShellResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let standardOutput = String(data: outputData, encoding: .utf8) ?? ""
        let standardError = String(data: errorData, encoding: .utf8) ?? ""
        let output = standardOutput + standardError
        return ShellResult(exitCode: process.terminationStatus, output: output)
    }
}
