import AppKit
import Foundation
import Observation

// MARK: - DeveloperSetupPasteboardWriting

@MainActor
protocol DeveloperSetupPasteboardWriting {
    func write(_ string: String)
}

// MARK: - DeveloperSetupSystemPasteboard

@MainActor
struct DeveloperSetupSystemPasteboard: DeveloperSetupPasteboardWriting {
    func write(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - SetupTerminalApp

enum SetupTerminalApp: String, CaseIterable, Identifiable {
    case appleTerminal
    case iTerm2
    case ghostty
    case custom

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appleTerminal:
            String(localized: "Apple Terminal", bundle: RockxyLocalization.bundle)
        case .iTerm2:
            String(localized: "iTerm2", bundle: RockxyLocalization.bundle)
        case .ghostty:
            String(localized: "Ghostty", bundle: RockxyLocalization.bundle)
        case .custom:
            String(localized: "My own Terminal...", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - SetupBrowserApp

enum SetupBrowserApp: String, CaseIterable, Identifiable {
    case chromeNewProfile
    case chromeCurrentProfile
    case firefox

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .chromeNewProfile:
            String(localized: "Google Chrome (New Profile)...", bundle: RockxyLocalization.bundle)
        case .chromeCurrentProfile:
            String(localized: "Google Chrome (Current Profile)...", bundle: RockxyLocalization.bundle)
        case .firefox:
            String(localized: "Firefox...", bundle: RockxyLocalization.bundle)
        }
    }

    var isEnabled: Bool {
        true
    }
}

// MARK: - DeveloperSetupLaunchError

enum DeveloperSetupLaunchError: LocalizedError {
    case processFailed(command: String, status: Int32, message: String?)
    case browserUnavailable(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .processFailed(command, status, message):
            if let message, !message.isEmpty {
                return String(
                    localized: "\(command) exited with status \(status): \(message)",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(localized: "\(command) exited with status \(status).", bundle: RockxyLocalization.bundle)
        case let .browserUnavailable(name):
            return String(localized: "\(name) is not available on this Mac.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - DeveloperSetupProcessRunning

/// Injectable seam so launcher outcomes are honest and testable: the runner
/// waits for the launched process and reports a nonzero exit as an error.
protocol DeveloperSetupProcessRunning: Sendable {
    func run(executableURL: URL, arguments: [String]) throws
}

// MARK: - DeveloperSetupProcessRunner

struct DeveloperSetupProcessRunner: DeveloperSetupProcessRunning {
    func run(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw DeveloperSetupLaunchError.processFailed(
                command: executableURL.lastPathComponent,
                status: -1,
                message: error.localizedDescription
            )
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DeveloperSetupLaunchError.processFailed(
                command: executableURL.lastPathComponent,
                status: process.terminationStatus,
                message: (raw?.isEmpty == false) ? raw : nil
            )
        }
    }
}

// MARK: - RockxySetupScriptContext

struct RockxySetupScriptContext: Equatable {
    // MARK: Lifecycle

    init(
        proxyHost: String,
        proxyPort: Int,
        certificatePath: String?,
        generatedAt: Date,
        appName: String,
        targetID: SetupTarget.ID = .python
    ) {
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.certificatePath = certificatePath
        self.generatedAt = generatedAt
        self.appName = appName
        self.targetID = targetID
    }

    // MARK: Internal

    let proxyHost: String
    let proxyPort: Int
    let certificatePath: String?
    let generatedAt: Date
    let appName: String
    /// The routed target this script was generated for. Only `.javaVMs` receives
    /// JVM-specific proxy properties; every other target keeps the shared shell.
    let targetID: SetupTarget.ID
}

// MARK: - RockxySetupScriptBuilder

enum RockxySetupScriptBuilder {
    static let relativeScriptPath = "setup/rockxy_env_setup.sh"

    static func generatedScriptURL(
        identity: RockxyIdentity = .current,
        fileManager: FileManager = .default
    )
        -> URL
    {
        identity.appSupportPath(relativeScriptPath, fileManager: fileManager)
    }

    static func sourceCommand(scriptURL: URL) -> String {
        let quotedPath = shellDoubleQuoted(scriptURL.path)
        return "set -a 2>/dev/null || true; source \(quotedPath); set +a 2>/dev/null || true"
    }

    @discardableResult
    static func writeScript(
        context: RockxySetupScriptContext,
        scriptURL: URL = generatedScriptURL(),
        fileManager: FileManager = .default
    )
        throws -> URL
    {
        let directory = scriptURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let contents = script(context: context)
        let temporaryURL = directory
            .appendingPathComponent(".\(scriptURL.lastPathComponent).tmp-\(UUID().uuidString)")
        try contents.write(to: temporaryURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryURL.path)

        if fileManager.fileExists(atPath: scriptURL.path) {
            _ = try fileManager.replaceItemAt(scriptURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: scriptURL)
        }

        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    static func script(context: RockxySetupScriptContext) -> String {
        let proxyURL = "http://\(context.proxyHost):\(context.proxyPort)"
        let generatedAt = ISO8601DateFormatter().string(from: context.generatedAt)
        var lines = [
            "#!/bin/zsh",
            "# Generated by \(context.appName). Do not edit this file directly.",
            "# Rockxy setup script version: 1",
            "# Generated at: \(generatedAt)",
            "",
            "export ROCKXY_SETUP_SESSION=1",
            "export ROCKXY_PROXY_HOST=\(shellDoubleQuoted(context.proxyHost))",
            "export ROCKXY_PROXY_PORT=\(shellDoubleQuoted(String(context.proxyPort)))",
            "export HTTP_PROXY=\(shellDoubleQuoted(proxyURL))",
            "export HTTPS_PROXY=\(shellDoubleQuoted(proxyURL))",
            "export ALL_PROXY=\(shellDoubleQuoted(proxyURL))",
            "export http_proxy=\"$HTTP_PROXY\"",
            "export https_proxy=\"$HTTPS_PROXY\"",
            "export all_proxy=\"$ALL_PROXY\"",
            "export npm_config_proxy=\"$HTTP_PROXY\"",
            "export npm_config_https_proxy=\"$HTTPS_PROXY\"",
            "export NO_PROXY=\"${NO_PROXY:-localhost,127.0.0.1,::1}\"",
            "export no_proxy=\"$NO_PROXY\"",
        ]

        if let certificatePath = context.certificatePath, !certificatePath.isEmpty {
            lines.append(contentsOf: [
                "export ROCKXY_ROOT_CA_PATH=\(shellDoubleQuoted(certificatePath))",
                "export NODE_EXTRA_CA_CERTS=\"$ROCKXY_ROOT_CA_PATH\"",
                "# Replacement-style CA variables are not changed: setting them to one Rockxy root",
                "# would discard the runtime's existing public or corporate trust anchors.",
            ])
        } else {
            lines.append("# Export or trust the Rockxy root certificate to enable certificate environment hints.")
        }

        if context.targetID == .javaVMs {
            lines.append(contentsOf: javaProxyLines(proxyHost: context.proxyHost, proxyPort: context.proxyPort))
        }

        lines.append(contentsOf: [
            "",
            "echo \"\(context.appName) setup session is ready: $HTTP_PROXY\"",
            "echo \"Run your server or script in this terminal so Rockxy can capture its HTTP and HTTPS traffic.\"",
            "",
        ])

        return lines.joined(separator: "\n")
    }

    /// JVM proxy properties for the Java VMs target. Re-sourcing removes the
    /// previous Rockxy block before appending the current one, so user options
    /// added at any point survive and stale proxy properties never accumulate.
    static func javaProxyLines(proxyHost: String, proxyPort: Int) -> [String] {
        let proxyOptions = DeveloperCaptureEnvironmentBuilder.javaProxyOptions(
            proxyHost: proxyHost,
            proxyPort: proxyPort
        )
        return [
            "",
            "# Java VMs: route the JVM through Rockxy while preserving existing JAVA_TOOL_OPTIONS.",
            "# Remove the previous Rockxy block before appending the current one.",
            "if [ -n \"${ROCKXY_JAVA_PROXY_OPTS:-}\" ] && [ -n \"${JAVA_TOOL_OPTIONS:-}\" ]; then",
            "  export JAVA_TOOL_OPTIONS=\"${JAVA_TOOL_OPTIONS//$ROCKXY_JAVA_PROXY_OPTS/}\"",
            "fi",
            "export ROCKXY_JAVA_PROXY_OPTS=\(shellDoubleQuoted(proxyOptions))",
            "if [ -n \"${JAVA_TOOL_OPTIONS:-}\" ]; then",
            "  export JAVA_TOOL_OPTIONS=\"$JAVA_TOOL_OPTIONS $ROCKXY_JAVA_PROXY_OPTS\"",
            "else",
            "  export JAVA_TOOL_OPTIONS=\"$ROCKXY_JAVA_PROXY_OPTS\"",
            "fi",
        ]
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    static func shellDoubleQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

// MARK: - RockxySetupSessionLauncher

enum RockxySetupSessionLauncher {
    // MARK: Internal

    static func openTerminal(
        _ app: SetupTerminalApp,
        sourceCommand: String,
        runner: DeveloperSetupProcessRunning = DeveloperSetupProcessRunner()
    )
        throws
    {
        let command = "\(sourceCommand) && printf '\\nRockxy is ready. Start your server or scripts here.\\n'"

        switch app {
        case .appleTerminal:
            try runAppleScript(
                """
                tell application "Terminal"
                    activate
                    do script "\(appleScriptString(command))"
                end tell
                """,
                runner: runner
            )
        case .iTerm2:
            try runAppleScript(
                """
                tell application "iTerm2"
                    activate
                    create window with default profile
                    tell current session of current window
                        write text "\(appleScriptString(command))"
                    end tell
                end tell
                """,
                runner: runner
            )
        case .ghostty:
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-na", "Ghostty", "--args", "-e", "/bin/zsh", "-lc", "\(command); exec /bin/zsh -l"]
            )
        case .custom:
            // Custom terminals are handled by the target-aware view model, which
            // copies through its injectable pasteboard seam.
            return
        }
    }

    static func openBrowser(
        _ app: SetupBrowserApp,
        proxyHost: String,
        proxyPort: Int,
        supportDirectory: URL = RockxyIdentity.current.appSupportPath("setup"),
        runner: DeveloperSetupProcessRunning = DeveloperSetupProcessRunner()
    )
        throws
    {
        guard app.isEnabled else {
            throw DeveloperSetupLaunchError.browserUnavailable(app.title)
        }

        let proxyServer = "http://\(proxyHost):\(proxyPort)"
        switch app {
        case .chromeNewProfile:
            let profileURL = supportDirectory.appendingPathComponent("Chrome Profile", isDirectory: true)
            try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: [
                    "-na", "Google Chrome", "--args",
                    "--user-data-dir=\(profileURL.path)",
                    "--proxy-server=\(proxyServer)",
                    "--proxy-bypass-list=<-loopback>",
                ]
            )
        case .chromeCurrentProfile:
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-a", "Google Chrome", "--args", "--proxy-server=\(proxyServer)"]
            )
        case .firefox:
            let profileURL = supportDirectory.appendingPathComponent("Firefox Profile", isDirectory: true)
            try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
            try firefoxUserJS(proxyHost: proxyHost, proxyPort: proxyPort)
                .write(to: profileURL.appendingPathComponent("user.js"), atomically: true, encoding: .utf8)
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-na", "Firefox", "--args", "-no-remote", "-profile", profileURL.path]
            )
        }
    }

    static func firefoxUserJS(proxyHost: String, proxyPort: Int) -> String {
        """
        user_pref("network.proxy.type", 1);
        user_pref("network.proxy.http", "\(proxyHost)");
        user_pref("network.proxy.http_port", \(proxyPort));
        user_pref("network.proxy.ssl", "\(proxyHost)");
        user_pref("network.proxy.ssl_port", \(proxyPort));
        user_pref("network.proxy.no_proxies_on", "localhost, 127.0.0.1, ::1");
        """
    }

    // MARK: Private

    private static func runAppleScript(_ script: String, runner: DeveloperSetupProcessRunning) throws {
        try runner.run(executableURL: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", script])
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - DeveloperSetupSessionSetupViewModel

@MainActor @Observable
final class DeveloperSetupSessionSetupViewModel {
    // MARK: Lifecycle

    init(
        coordinator: MainContentCoordinator,
        targetID: SetupTarget.ID = .python,
        processRunner: DeveloperSetupProcessRunning = DeveloperSetupProcessRunner(),
        pasteboard: DeveloperSetupPasteboardWriting? = nil,
        scriptURL: URL = RockxySetupScriptBuilder.generatedScriptURL(),
        generatedAt: @escaping () -> Date = Date.init,
        applicationLauncher: DeveloperApplicationLaunching? = nil,
        settingsRestorationMonitor: DeveloperApplicationSettingsRestorationMonitoring? = nil,
        preparationRegistry: DeveloperApplicationPreparationRegistry? = nil,
        applicationIsRunning: @escaping @MainActor (DeveloperApplicationInstallation) -> Bool = {
            DeveloperApplicationCaptureConfigurator.isRunning($0)
        },
        systemProxyConfiguredProvider: (@MainActor () async -> Bool)? = nil,
        applicationSupportURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    ) {
        self.coordinator = coordinator
        self.targetID = targetID
        self.processRunner = processRunner
        self.pasteboard = pasteboard ?? DeveloperSetupSystemPasteboard()
        self.scriptURL = scriptURL
        self.generatedAt = generatedAt
        self.applicationLauncher = applicationLauncher ?? DeveloperApplicationWorkspaceLauncher()
        self.settingsRestorationMonitor = settingsRestorationMonitor
            ?? DeveloperApplicationSettingsRestorationMonitor.shared
        self.preparationRegistry = preparationRegistry ?? .shared
        self.applicationIsRunning = applicationIsRunning
        self.systemProxyConfiguredProvider = systemProxyConfiguredProvider
        self.applicationSupportURL = applicationSupportURL
        context = Self.makeContext(coordinator: coordinator, targetID: targetID, generatedAt: generatedAt())
    }

    // MARK: Internal

    var targetID: SetupTarget.ID
    var selectedTerminalApp: SetupTerminalApp = .appleTerminal
    var selectedBrowserApp: SetupBrowserApp = .chromeNewProfile
    var statusMessage: String?
    var context: RockxySetupScriptContext

    let scriptURL: URL

    var target: SetupTarget {
        SetupTarget.target(for: targetID) ?? .python
    }

    var workflow: SetupWorkflow {
        DeveloperSetupWorkflowCatalog.workflow(for: targetID)
    }

    var guideContent: SetupGuideContent? {
        DeveloperSetupGuideCatalog.content(for: targetID)
    }

    /// Automatic Setup is only offered for shipped terminal-runtime targets.
    var isRuntimeTerminalTarget: Bool {
        target.isRuntimeTerminalTarget
    }

    /// The manual snippet Rockxy would show for a non-terminal target so the
    /// Manual Setup window never silently falls back to the generic terminal flow.
    var targetSnippetText: String? {
        guard let snippetID = workflow.defaultSnippetID else {
            return nil
        }
        return DeveloperSetupWorkflowCatalog.generatedSnippet(
            for: targetID,
            snippetID: snippetID,
            port: context.proxyPort,
            certificatePath: context.certificatePath
        )
    }

    var manualSourceCommand: String {
        RockxySetupScriptBuilder.sourceCommand(scriptURL: scriptURL)
    }

    var proxyEndpointText: String {
        "\(context.proxyHost):\(context.proxyPort)"
    }

    /// Describes the capability boundary instead of promising that one proxy mechanism covers
    /// every developer tool. The chosen app is inspected before launch and only recognized,
    /// declarative proxy settings are changed.
    var developerApplicationGuidanceText: String {
        String(
            localized: """
            Choose a fully quit developer application to open with Rockxy's scoped proxy and certificate \
            environment. When Rockxy detects a supported app-level proxy schema, it temporarily prepares that \
            application to use automatic proxy discovery with the active macOS System Proxy at \(proxyEndpointText). \
            Containers, emulators, devices, and already-running processes \
            remain separate capture boundaries.
            """,
            bundle: RockxyLocalization.bundle
        )
    }

    var certificateStatusText: String {
        if context.certificatePath != nil {
            return String(localized: "Certificate environment hints are ready.", bundle: RockxyLocalization.bundle)
        }
        return String(
            localized: "Export the Rockxy root certificate to add certificate environment hints.",
            bundle: RockxyLocalization.bundle
        )
    }

    static func makeContext(
        coordinator: MainContentCoordinator,
        targetID: SetupTarget.ID,
        generatedAt: Date
    )
        -> RockxySetupScriptContext
    {
        let settings = AppSettingsManager.shared.settings
        let port = DeveloperSetupViewModel.resolveSnippetPort(
            isProxyRunning: coordinator.isProxyRunning,
            activePort: coordinator.activeProxyPort,
            configuredPort: settings.proxyPort
        )
        let certificatePath = settings.lastExportedRootCAPath.flatMap { path -> String? in
            FileManager.default.fileExists(atPath: path) ? path : nil
        }

        return RockxySetupScriptContext(
            proxyHost: "127.0.0.1",
            proxyPort: port,
            certificatePath: certificatePath,
            generatedAt: generatedAt,
            appName: RockxyIdentity.current.displayName,
            targetID: targetID
        )
    }

    func applyRoute(
        _ route: DeveloperSetupRoute?,
        destination: DeveloperSetupRouteDestination
    ) {
        guard let route,
              route.destination == destination,
              route.generation > lastAppliedRouteGeneration else
        {
            return
        }
        lastAppliedRouteGeneration = route.generation
        targetID = route.targetID
        statusMessage = nil
        refresh()
    }

    func refresh() {
        context = Self.makeContext(coordinator: coordinator, targetID: targetID, generatedAt: generatedAt())
    }

    func prepareScript() throws {
        refresh()
        try RockxySetupScriptBuilder.writeScript(context: context, scriptURL: scriptURL)
    }

    func prepareScriptForDisplay() {
        do {
            try prepareScript()
            statusMessage = String(localized: "Setup script is ready.", bundle: RockxyLocalization.bundle)
        } catch {
            statusMessage = String(
                localized: "Could not prepare the setup script: \(error.localizedDescription)",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    func copyManualCommand() {
        do {
            try prepareScript()
            pasteboard.write(manualSourceCommand)
            statusMessage = String(localized: "Setup command copied.", bundle: RockxyLocalization.bundle)
        } catch {
            statusMessage = String(
                localized: "Could not prepare the setup script: \(error.localizedDescription)",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    func copyTargetSnippet() {
        guard let snippet = targetSnippetText else {
            statusMessage = String(
                localized: "No snippet is available for \(target.title).",
                bundle: RockxyLocalization.bundle
            )
            return
        }
        pasteboard.write(snippet)
        statusMessage = String(localized: "\(target.title) snippet copied.", bundle: RockxyLocalization.bundle)
    }

    func openPreparedTerminal() async {
        guard coordinator.isProxyRunning else {
            statusMessage = String(
                localized: "Start the Rockxy proxy before opening a prepared terminal.",
                bundle: RockxyLocalization.bundle
            )
            return
        }

        guard prepareScriptForLaunch() else {
            return
        }

        if selectedTerminalApp == .custom {
            pasteboard.write(manualSourceCommand)
            statusMessage = String(
                localized: "Setup command copied. Paste it into your terminal.",
                bundle: RockxyLocalization.bundle
            )
            return
        }

        let app = selectedTerminalApp
        let command = manualSourceCommand
        let runner = processRunner
        do {
            _ = try await Task.detached {
                try RockxySetupSessionLauncher.openTerminal(app, sourceCommand: command, runner: runner)
            }.value
            statusMessage = String(
                localized: "Prepared \(target.title) terminal session opened.",
                bundle: RockxyLocalization.bundle
            )
        } catch {
            statusMessage = launchFailureMessage(
                error,
                action: String(localized: "open the prepared terminal", bundle: RockxyLocalization.bundle)
            )
        }
    }

    func openDeveloperApplication(at appURL: URL) async {
        guard coordinator.isProxyRunning else {
            statusMessage = String(
                localized: "Start the Rockxy proxy before opening a developer application.",
                bundle: RockxyLocalization.bundle
            )
            return
        }
        refresh()
        do {
            let systemProxyConfigured = if let systemProxyConfiguredProvider {
                await systemProxyConfiguredProvider()
            } else {
                await coordinator.reconcileProxyOverrideStatus()
            }
            let workflow = DeveloperApplicationCaptureWorkflow(
                launcher: applicationLauncher,
                restorationMonitor: settingsRestorationMonitor,
                preparationRegistry: preparationRegistry,
                applicationIsRunning: applicationIsRunning,
                applicationSupportURL: applicationSupportURL
            )
            let outcome = try await workflow.open(
                appURL: appURL,
                context: context,
                systemProxyConfigured: systemProxyConfigured
            )
            switch outcome {
            case let .prepared(displayName, restorationMonitorActive):
                if restorationMonitorActive {
                    statusMessage = String(
                        localized: "\(displayName)'s recognized proxy settings were prepared temporarily and will be restored after it quits. A fresh instance was opened with Rockxy's scoped environment.",
                        bundle: RockxyLocalization.bundle
                    )
                } else {
                    statusMessage = String(
                        localized: "\(displayName) was opened with temporary proxy settings. Keep Rockxy open until the application quits so those settings can be restored safely.",
                        bundle: RockxyLocalization.bundle
                    )
                }
            case let .explicitProxyLaunch(displayName):
                statusMessage = String(
                    localized: "\(displayName) was opened with an explicit scoped proxy and Rockxy's environment. These launch settings remain active until the application quits.",
                    bundle: RockxyLocalization.bundle
                )
            case let .environmentOnly(displayName):
                statusMessage = String(
                    localized: "\(displayName) was opened with Rockxy's scoped environment. If it overrides macOS or environment proxy settings, configure that app-level proxy separately.",
                    bundle: RockxyLocalization.bundle
                )
            case let .launchPending(displayName, restorationMonitorActive):
                if restorationMonitorActive {
                    statusMessage = String(
                        localized: "macOS accepted the request to open \(displayName), but the application is still completing first-launch checks. Follow any macOS prompt and wait for it to open. Temporary settings recovery remains active.",
                        bundle: RockxyLocalization.bundle
                    )
                } else {
                    statusMessage = String(
                        localized: "macOS accepted the request to open \(displayName), but the application is still completing first-launch checks. Follow any macOS prompt and wait for it to open.",
                        bundle: RockxyLocalization.bundle
                    )
                }
            }
        } catch {
            statusMessage = launchFailureMessage(
                error,
                action: String(localized: "open the developer application", bundle: RockxyLocalization.bundle)
            )
        }
    }

    func openPreparedBrowser() async {
        guard selectedBrowserApp.isEnabled else {
            statusMessage = String(
                localized: "\(selectedBrowserApp.title) is not available.",
                bundle: RockxyLocalization.bundle
            )
            return
        }
        guard prepareScriptForLaunch() else {
            return
        }

        let app = selectedBrowserApp
        let host = context.proxyHost
        let port = context.proxyPort
        let runner = processRunner
        do {
            try await Task.detached {
                try RockxySetupSessionLauncher.openBrowser(app, proxyHost: host, proxyPort: port, runner: runner)
            }.value
            statusMessage = String(
                localized: "Prepared \(app.title) profile opened.",
                bundle: RockxyLocalization.bundle
            )
        } catch {
            statusMessage = launchFailureMessage(
                error,
                action: String(localized: "open the prepared browser", bundle: RockxyLocalization.bundle)
            )
        }
    }

    // MARK: Private

    private let coordinator: MainContentCoordinator
    private let processRunner: DeveloperSetupProcessRunning
    private let pasteboard: DeveloperSetupPasteboardWriting
    private let generatedAt: () -> Date
    private let applicationLauncher: DeveloperApplicationLaunching
    private let settingsRestorationMonitor: DeveloperApplicationSettingsRestorationMonitoring
    private let preparationRegistry: DeveloperApplicationPreparationRegistry
    private let applicationIsRunning: @MainActor (DeveloperApplicationInstallation) -> Bool
    private let systemProxyConfiguredProvider: (@MainActor () async -> Bool)?
    private let applicationSupportURL: URL
    private var lastAppliedRouteGeneration = 0

    private func prepareScriptForLaunch() -> Bool {
        do {
            try prepareScript()
            return true
        } catch {
            statusMessage = String(
                localized: "Could not prepare the setup script: \(error.localizedDescription)",
                bundle: RockxyLocalization.bundle
            )
            return false
        }
    }

    private func launchFailureMessage(_ error: Error, action: String) -> String {
        if let launchError = error as? DeveloperSetupLaunchError,
           let description = launchError.errorDescription
        {
            return String(localized: "Could not \(action): \(description)", bundle: RockxyLocalization.bundle)
        }
        return String(
            localized: "Could not \(action): \(error.localizedDescription)",
            bundle: RockxyLocalization.bundle
        )
    }
}
