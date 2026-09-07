import Foundation
@testable import Rockxy
import Testing

// Regression tests for `SystemProxyManager` in the core traffic capture layer.

// MARK: - SystemProxyManagerTests

// Tests for SystemProxyManager: error descriptions, state management,
// network service parsing logic, and proxy status output parsing.
// Since SystemProxyManager shells out to /usr/sbin/networksetup, direct
// integration tests are impractical. We verify the parsing patterns and state
// transitions using standalone helper functions that replicate the private logic.

struct SystemProxyManagerTests {
    // MARK: Internal

    // MARK: - SystemProxyError

    @Test("SystemProxyError.networkSetupFailed includes command and exit code")
    func networkSetupFailedDescription() {
        let error = SystemProxyError.networkSetupFailed(
            command: "-setwebproxy Wi-Fi 127.0.0.1 9090",
            output: "permission denied",
            exitCode: 1
        )

        let description = error.errorDescription ?? ""
        #expect(description.contains("-setwebproxy"))
        #expect(description.contains("permission denied"))
        #expect(description.contains("1"))
    }

    @Test("SystemProxyError.noActiveNetworkService has meaningful description")
    func noActiveNetworkServiceDescription() {
        let error = SystemProxyError.noActiveNetworkService
        let description = error.errorDescription ?? ""
        #expect(description.contains("active network service"))
    }

    @Test("SystemProxyError.unexpectedOutput includes the output text")
    func unexpectedOutputDescription() {
        let error = SystemProxyError.unexpectedOutput("garbled data here")
        let description = error.errorDescription ?? ""
        #expect(description.contains("garbled data here"))
    }

    @Test("All SystemProxyError cases conform to LocalizedError with non-nil descriptions")
    func allCasesHaveDescriptions() {
        let cases: [SystemProxyError] = [
            .networkSetupFailed(command: "test", output: "out", exitCode: 42),
            .noActiveNetworkService,
            .proxyActivationNotConfirmed(port: 8_888),
            .proxyRestoreFailed,
            .previousHelperUnavailable,
            .unexpectedOutput("bad"),
        ]

        for error in cases {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(description?.isEmpty == false)
        }
    }

    // MARK: - State Management

    @Test("routing readiness requires every fallback service to match")
    func routingReadinessRejectsPartialFallbackMatch() {
        let matching = ServiceProxySnapshot(
            httpEnabled: true,
            httpHost: "127.0.0.1",
            httpPort: 8_888,
            httpsEnabled: true,
            httpsHost: "127.0.0.1",
            httpsPort: 8_888,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false
        )
        let foreign = ServiceProxySnapshot(
            httpEnabled: true,
            httpHost: "127.0.0.1",
            httpPort: 9_090,
            httpsEnabled: true,
            httpsHost: "127.0.0.1",
            httpsPort: 9_090,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false
        )

        #expect(SystemProxyManager.proxySnapshotsMatchRockxy(port: 8_888, snapshots: [matching]))
        #expect(!SystemProxyManager.proxySnapshotsMatchRockxy(port: 8_888, snapshots: [matching, foreign]))
        #expect(!SystemProxyManager.proxySnapshotsMatchRockxy(port: 8_888, snapshots: []))
    }

    @Test("effective routing requires exact HTTP and HTTPS host and port")
    func effectiveRoutingRequiresExactMatch() {
        let matching: [String: Any] = [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": 8_888,
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": 8_888
        ]
        var foreign = matching
        foreign["HTTPSPort"] = 9_090

        #expect(SystemProxyManager.effectiveProxyDictionaryMatchesRockxy(
            port: 8_888,
            settings: matching
        ))
        #expect(!SystemProxyManager.effectiveProxyDictionaryMatchesRockxy(
            port: 8_888,
            settings: foreign
        ))
    }

    @Test("routing readiness rejects alternate automatic and SOCKS routes")
    func routingReadinessRejectsAlternateRoutes() {
        let matching = ServiceProxySnapshot(
            httpEnabled: true,
            httpHost: "127.0.0.1",
            httpPort: 8_888,
            httpsEnabled: true,
            httpsHost: "127.0.0.1",
            httpsPort: 8_888,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false
        )

        let variants = [
            ServiceProxySnapshot(
                httpEnabled: matching.httpEnabled,
                httpHost: matching.httpHost,
                httpPort: matching.httpPort,
                httpsEnabled: matching.httpsEnabled,
                httpsHost: matching.httpsHost,
                httpsPort: matching.httpsPort,
                socksEnabled: true,
                socksHost: "foreign.proxy",
                socksPort: 1_080,
                pacEnabled: false,
                pacURL: "",
                autoDiscoveryEnabled: false
            ),
            ServiceProxySnapshot(
                httpEnabled: matching.httpEnabled,
                httpHost: matching.httpHost,
                httpPort: matching.httpPort,
                httpsEnabled: matching.httpsEnabled,
                httpsHost: matching.httpsHost,
                httpsPort: matching.httpsPort,
                socksEnabled: false,
                socksHost: "",
                socksPort: 0,
                pacEnabled: true,
                pacURL: "https://proxy.example/proxy.pac",
                autoDiscoveryEnabled: false
            ),
            ServiceProxySnapshot(
                httpEnabled: matching.httpEnabled,
                httpHost: matching.httpHost,
                httpPort: matching.httpPort,
                httpsEnabled: matching.httpsEnabled,
                httpsHost: matching.httpsHost,
                httpsPort: matching.httpsPort,
                socksEnabled: false,
                socksHost: "",
                socksPort: 0,
                pacEnabled: false,
                pacURL: "",
                autoDiscoveryEnabled: true
            ),
        ]

        for variant in variants {
            #expect(!SystemProxyManager.proxySnapshotsMatchRockxy(port: 8_888, snapshots: [variant]))
        }
    }

    @Test("effective routing rejects PAC, auto discovery, SOCKS, and global bypass")
    func effectiveRoutingRejectsAlternateRoutesAndGlobalBypass() {
        let matching: [String: Any] = [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": 8_888,
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": 8_888,
        ]
        let conflictingValues: [(String, Any)] = [
            ("SOCKSEnable", 1),
            ("ProxyAutoConfigEnable", 1),
            ("ProxyAutoDiscoveryEnable", 1),
            ("ExceptionsList", ["localhost", "*"]),
        ]

        for (key, value) in conflictingValues {
            var settings = matching
            settings[key] = value
            #expect(!SystemProxyManager.effectiveProxyDictionaryMatchesRockxy(
                port: 8_888,
                settings: settings
            ))
        }
    }

    @Test("routing reclaim preserves the original ownership method and backup")
    func reclaimModePreservesOriginalOwnership() {
        #expect(SystemProxyManager.reclaimMode(
            directRestorePending: true,
            directBackupExists: true,
            usingHelper: false,
            isEnabled: false
        ) == .direct)
        #expect(SystemProxyManager.reclaimMode(
            directRestorePending: false,
            directBackupExists: false,
            usingHelper: true,
            isEnabled: false
        ) == .helper)
        #expect(SystemProxyManager.reclaimMode(
            directRestorePending: false,
            directBackupExists: false,
            usingHelper: false,
            isEnabled: false
        ) == .none)
    }

    @Test("systemProxyEnabled defaults to false")
    func defaultStateIsFalse() {
        let manager = SystemProxyManager.shared
        #expect(manager.systemProxyEnabled == false)
    }

    @Test("helper emergency restore runs immediately when this session used helper")
    func helperEmergencyRestoreWhenUsingHelper() {
        #expect(SystemProxyManager.shouldAttemptHelperEmergencyRestore(
            wasUsingHelper: true,
            helperBackupExists: false,
            loopbackProxyDetected: false
        ))
    }

    @Test("helper emergency restore runs for stale helper backup still pointing to loopback")
    func helperEmergencyRestoreWhenBackupAndLoopbackExist() {
        #expect(SystemProxyManager.shouldAttemptHelperEmergencyRestore(
            wasUsingHelper: false,
            helperBackupExists: true,
            loopbackProxyDetected: true
        ))
    }

    @Test("helper emergency restore skips stale backup when system proxy no longer points at Rockxy")
    func helperEmergencyRestoreSkipsWhenLoopbackMissing() {
        #expect(SystemProxyManager.shouldAttemptHelperEmergencyRestore(
            wasUsingHelper: false,
            helperBackupExists: true,
            loopbackProxyDetected: false
        ) == false)
    }

    @Test("direct proxy watchdog exits once backup is gone")
    func directProxyWatchdogExitsWhenBackupRemoved() {
        #expect(SystemProxyManager.directProxyWatchdogAction(
            parentAlive: true,
            backupExists: false
        ) == .exit)
    }

    @Test("direct proxy watchdog keeps waiting while parent is alive")
    func directProxyWatchdogWaitsForParentExit() {
        #expect(SystemProxyManager.directProxyWatchdogAction(
            parentAlive: true,
            backupExists: true
        ) == .wait)
    }

    @Test("direct proxy watchdog restores after parent exits with backup present")
    func directProxyWatchdogRestoresOnParentExit() {
        #expect(SystemProxyManager.directProxyWatchdogAction(
            parentAlive: false,
            backupExists: true
        ) == .restore)
    }

    @Test("direct restore clears backup only after commands succeed and proxy ownership is gone")
    func directRestoreClearsBackupOnlyWhenOwnershipIsGone() {
        #expect(SystemProxyManager.shouldClearDirectBackupAfterRestoreAttempt(
            commandsSucceeded: true,
            proxyStillPointsAtRockxy: false
        ))
    }

    @Test("direct restore keeps backup when proxy still points at Rockxy")
    func directRestoreKeepsBackupWhileProxyStillOwned() {
        #expect(SystemProxyManager.shouldClearDirectBackupAfterRestoreAttempt(
            commandsSucceeded: true,
            proxyStillPointsAtRockxy: true
        ) == false)
    }

    @Test("direct restore keeps backup when restore commands fail")
    func directRestoreKeepsBackupOnCommandFailure() {
        #expect(SystemProxyManager.shouldClearDirectBackupAfterRestoreAttempt(
            commandsSucceeded: false,
            proxyStillPointsAtRockxy: false
        ) == false)
    }

    @Test("helper override confirmation requires active state on the requested port")
    func helperOverrideConfirmationRequiresExactLiveState() {
        #expect(SystemProxyManager.helperOverrideIsConfirmed(
            requestedPort: 8_888,
            status: (isOverridden: true, port: 8_888)
        ))
        #expect(SystemProxyManager.helperOverrideIsConfirmed(
            requestedPort: 8_888,
            status: (isOverridden: false, port: 8_888)
        ) == false)
        #expect(SystemProxyManager.helperOverrideIsConfirmed(
            requestedPort: 8_888,
            status: (isOverridden: true, port: 9_090)
        ) == false)
        #expect(SystemProxyManager.helperOverrideIsConfirmed(
            requestedPort: 8_888,
            status: nil
        ) == false)
    }

    @Test("activation confirmation tolerates delayed system configuration propagation")
    func activationConfirmationRetries() async {
        let counter = ActivationProbeCounter(succeedsOnAttempt: 3)

        let confirmed = await ProxyActivationConfirmation.confirm(
            maxAttempts: 4,
            delay: .zero
        ) {
            await counter.probe()
        }

        #expect(confirmed)
        #expect(await counter.attempts == 3)
    }

    @Test("activation confirmation fails after the bounded attempt count")
    func activationConfirmationIsBounded() async {
        let counter = ActivationProbeCounter(succeedsOnAttempt: 5)

        let confirmed = await ProxyActivationConfirmation.confirm(
            maxAttempts: 2,
            delay: .zero
        ) {
            await counter.probe()
        }

        #expect(!confirmed)
        #expect(await counter.attempts == 2)
    }

    // MARK: - Proxy Override Reconciliation

    @Test("An override on the active proxy port reports both override and capture readiness")
    func overrideOnActivePortIsCaptureReady() {
        let reconciliation = MainContentCoordinator.reconcileProxyOverride(
            overridePort: 8_888,
            activeProxyPort: 8_888
        )

        #expect(reconciliation == ProxyOverrideReconciliation(
            isOverridden: true,
            matchesActiveProxyPort: true
        ))
    }

    @Test("An override on a different port stays an override but is not capture ready")
    func overrideOnDifferentPortIsNotCaptureReady() {
        let reconciliation = MainContentCoordinator.reconcileProxyOverride(
            overridePort: 9_090,
            activeProxyPort: 8_888
        )

        #expect(reconciliation.isOverridden)
        #expect(!reconciliation.matchesActiveProxyPort)
    }

    @Test("No override reports neither an override nor capture readiness")
    func absentOverrideReportsNothing() {
        let reconciliation = MainContentCoordinator.reconcileProxyOverride(
            overridePort: nil,
            activeProxyPort: 8_888
        )

        #expect(!reconciliation.isOverridden)
        #expect(!reconciliation.matchesActiveProxyPort)
    }

    @Test("Override ownership resolves the port from direct backups and helper status")
    func overridePortIsResolvedFromOwnership() {
        let backup = DirectProxyBackup(
            services: [],
            timestamp: Date(timeIntervalSince1970: 0),
            rockxyPort: 9_090
        )

        #expect(MainContentCoordinator.proxyOverridePort(for: .none) == nil)
        #expect(MainContentCoordinator.proxyOverridePort(for: .direct(backup: backup)) == 9_090)
        #expect(MainContentCoordinator.proxyOverridePort(for: .helper(port: 8_888)) == 8_888)
    }

    @Test("direct proxy watchdog launchctl submission uses helper entrypoint and backup path")
    func directProxyWatchdogSubmitArguments() {
        let arguments = SystemProxyManager.directWatchdogSubmitArguments(
            label: "com.amunx.rockxy.community.direct-proxy-watchdog",
            executablePath: "/tmp/RockxyHelperTool",
            parentPID: 4_242,
            backupPath: "/tmp/proxy-backup-direct.plist"
        )

        #expect(arguments == [
            "submit",
            "-l",
            "com.amunx.rockxy.community.direct-proxy-watchdog",
            "--",
            "/tmp/RockxyHelperTool",
            "--rockxy-direct-proxy-watchdog",
            "4242",
            "/tmp/proxy-backup-direct.plist",
        ])
    }

    // MARK: - Network Service Parsing Logic

    @Test("Parse typical networksetup service order output")
    func parseTypicalServiceOrder() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (2) Ethernet
        (Hardware Port: Ethernet, Device: en1)

        (3) Thunderbolt Bridge
        (Hardware Port: Thunderbolt Bridge, Device: bridge0)

        """

        let services = Self.parseNetworkServices(from: output)

        #expect(services.count == 3)
        #expect(services[0] == "Wi-Fi")
        #expect(services[1] == "Ethernet")
        #expect(services[2] == "Thunderbolt Bridge")
    }

    @Test("Parse output with single service")
    func parseSingleService() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        """

        let services = Self.parseNetworkServices(from: output)

        #expect(services.count == 1)
        #expect(services[0] == "Wi-Fi")
    }

    @Test("Parse output with no services returns empty array")
    func parseEmptyOutput() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        """

        let services = Self.parseNetworkServices(from: output)
        #expect(services.isEmpty)
    }

    @Test("Parse completely empty string returns empty array")
    func parseBlankString() {
        let services = Self.parseNetworkServices(from: "")
        #expect(services.isEmpty)
    }

    @Test("Parse output skips Hardware Port lines")
    func parseSkipsHardwarePortLines() {
        let output = """
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)
        """

        let services = Self.parseNetworkServices(from: output)

        #expect(services.count == 1)
        #expect(services[0] == "Wi-Fi")
    }

    @Test("Parse output with numbered services in double digits")
    func parseDoubleDigitServiceNumbers() {
        let output = """
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (10) USB Ethernet
        (Hardware Port: USB Ethernet, Device: en5)

        (11) iPhone USB
        (Hardware Port: iPhone USB, Device: en6)

        """

        let services = Self.parseNetworkServices(from: output)

        #expect(services.count == 3)
        #expect(services[0] == "Wi-Fi")
        #expect(services[1] == "USB Ethernet")
        #expect(services[2] == "iPhone USB")
    }

    @Test("Parse output ignores lines without leading parenthesis")
    func parseIgnoresNonServiceLines() {
        let output = """
        Some header text
        (1) Wi-Fi
        random noise
          indented (2) should not match because paren is not at start after trim
        (2) Ethernet
        """

        let services = Self.parseNetworkServices(from: output)

        #expect(services.count == 2)
        #expect(services[0] == "Wi-Fi")
        #expect(services[1] == "Ethernet")
    }

    @Test("Parse output with service name containing special characters")
    func parseServiceNameWithSpecialChars() {
        let output = """
        (1) Wi-Fi (AirPort)
        (Hardware Port: Wi-Fi, Device: en0)

        (2) USB 10/100/1000 LAN
        (Hardware Port: USB 10/100/1000 LAN, Device: en7)

        """

        let services = Self.parseNetworkServices(from: output)

        #expect(services.count == 2)
        #expect(services[0] == "Wi-Fi (AirPort)")
        #expect(services[1] == "USB 10/100/1000 LAN")
    }

    // MARK: - Proxy Status Parsing Logic

    @Test("Parse web proxy enabled status")
    func parseProxyEnabled() {
        let output = """
        Enabled: Yes
        Server: 127.0.0.1
        Port: 9090
        Authenticated Proxy Enabled: 0
        """

        let enabled = Self.parseProxyEnabled(from: output)
        #expect(enabled == true)
    }

    @Test("Parse web proxy disabled status")
    func parseProxyDisabled() {
        let output = """
        Enabled: No
        Server:
        Port: 0
        Authenticated Proxy Enabled: 0
        """

        let enabled = Self.parseProxyEnabled(from: output)
        #expect(enabled == false)
    }

    @Test("Parse proxy status with extra whitespace")
    func parseProxyStatusWithWhitespace() {
        let output = """
          Enabled:   Yes
          Server: 127.0.0.1
          Port: 9090
        """

        let enabled = Self.parseProxyEnabled(from: output)
        #expect(enabled == true)
    }

    @Test("Parse proxy status with missing Enabled line returns false")
    func parseProxyStatusMissingEnabledLine() {
        let output = """
        Server: 127.0.0.1
        Port: 9090
        """

        let enabled = Self.parseProxyEnabled(from: output)
        #expect(enabled == false)
    }

    @Test("Parse proxy status with empty output returns false")
    func parseProxyStatusEmptyOutput() {
        let enabled = Self.parseProxyEnabled(from: "")
        #expect(enabled == false)
    }

    @Test("Parse proxy status case insensitive for yes/no value")
    func parseProxyStatusCaseInsensitive() {
        let yesUpper = "Enabled: YES\nServer: 127.0.0.1\nPort: 9090"
        let yesMixed = "Enabled: yEs\nServer: 127.0.0.1\nPort: 9090"

        #expect(Self.parseProxyEnabled(from: yesUpper) == true)
        #expect(Self.parseProxyEnabled(from: yesMixed) == true)
    }

    // MARK: - List All Network Services Parsing

    @Test("Parse listallnetworkservices output skips header and disabled entries")
    func parseAllServicesOutput() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi
        *Bluetooth PAN
        Thunderbolt Bridge
        """

        let services = Self.parseAllNetworkServices(from: output)

        #expect(services.count == 2)
        #expect(services[0] == "Wi-Fi")
        #expect(services[1] == "Thunderbolt Bridge")
    }

    @Test("Parse listallnetworkservices with only disabled services returns empty")
    func parseAllServicesAllDisabled() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        *Bluetooth PAN
        *Thunderbolt Bridge
        """

        let services = Self.parseAllNetworkServices(from: output)
        #expect(services.isEmpty)
    }

    @Test("Parse listallnetworkservices with mixed enabled and disabled services")
    func parseAllServicesMixed() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi
        *Bluetooth PAN
        Ethernet
        *Thunderbolt Bridge
        USB 10/100/1000 LAN
        """

        let services = Self.parseAllNetworkServices(from: output)

        #expect(services.count == 3)
        #expect(services[0] == "Wi-Fi")
        #expect(services[1] == "Ethernet")
        #expect(services[2] == "USB 10/100/1000 LAN")
    }

    @Test("Parse listallnetworkservices with empty output returns empty")
    func parseAllServicesEmpty() {
        let services = Self.parseAllNetworkServices(from: "")
        #expect(services.isEmpty)
    }

    // MARK: - Network Service Map Parsing

    @Test("Parse network service order into device-to-service map")
    func parseNetworkServiceMap() {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (2) Ethernet
        (Hardware Port: Ethernet, Device: en1)

        (3) Thunderbolt Bridge
        (Hardware Port: Thunderbolt Bridge, Device: bridge0)

        """

        let map = Self.parseNetworkServiceMap(from: output)

        #expect(map["en0"] == "Wi-Fi")
        #expect(map["en1"] == "Ethernet")
        #expect(map["bridge0"] == "Thunderbolt Bridge")
        #expect(map.count == 3)
    }

    @Test("Parse network service map with USB LAN adapter")
    func parseNetworkServiceMapUSB() {
        let output = """
        (1) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)

        (2) USB 10/100/1000 LAN
        (Hardware Port: USB 10/100/1000 LAN, Device: en7)

        """

        let map = Self.parseNetworkServiceMap(from: output)

        #expect(map["en0"] == "Wi-Fi")
        #expect(map["en7"] == "USB 10/100/1000 LAN")
    }

    @Test("Parse network service map with empty output returns empty map")
    func parseNetworkServiceMapEmpty() {
        let map = Self.parseNetworkServiceMap(from: "")
        #expect(map.isEmpty)
    }

    // MARK: Private

    // MARK: - Helpers

    /// Replicates the private `parseNetworkServices(from:)` logic from `SystemProxyManager`
    /// to verify correctness of the parsing pattern.
    private static func parseNetworkServices(from output: String) -> [String] {
        var services: [String] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let openParen = trimmed.firstIndex(of: "("),
               let closeParen = trimmed.firstIndex(of: ")"),
               openParen == trimmed.startIndex
            {
                let afterParen = trimmed.index(after: closeParen)
                let serviceName = String(trimmed[afterParen...]).trimmingCharacters(in: .whitespaces)
                if !serviceName.isEmpty {
                    services.append(serviceName)
                }
            }
        }

        return services
    }

    /// Replicates the proxy-enabled parsing logic from `isSystemProxyEnabled()`.
    private static func parseProxyEnabled(from output: String) -> Bool {
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                let value = trimmed.replacingOccurrences(of: "Enabled:", with: "").trimmingCharacters(in: .whitespaces)
                return value.lowercased() == "yes"
            }
        }
        return false
    }

    /// Replicates the `listallnetworkservices` fallback parsing from `detectAllEnabledServices()`.
    private static func parseAllNetworkServices(from output: String) -> [String] {
        var services: [String] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("An asterisk"), !trimmed.hasPrefix("*") {
                services.append(trimmed)
            }
        }
        return services
    }

    /// Replicates the `parseNetworkServiceMap(from:)` logic from `SystemProxyManager`.
    private static func parseNetworkServiceMap(from output: String) -> [String: String] {
        var result: [String: String] = [:]
        var lastServiceName: String?
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("(Hardware Port:"), let serviceName = lastServiceName {
                if let deviceRange = trimmed.range(of: "Device: ") {
                    let afterDevice = trimmed[deviceRange.upperBound...]
                    let device = String(afterDevice.prefix(while: { $0 != ")" }))
                    if !device.isEmpty {
                        result[device] = serviceName
                    }
                }
            } else if let openParen = trimmed.firstIndex(of: "("),
                      let closeParen = trimmed.firstIndex(of: ")"),
                      openParen == trimmed.startIndex
            {
                let afterParen = trimmed.index(after: closeParen)
                let serviceName = String(trimmed[afterParen...]).trimmingCharacters(in: .whitespaces)
                if !serviceName.isEmpty {
                    lastServiceName = serviceName
                }
            }
        }

        return result
    }
}

private actor ActivationProbeCounter {
    init(succeedsOnAttempt: Int) {
        self.succeedsOnAttempt = succeedsOnAttempt
    }

    private(set) var attempts = 0
    private let succeedsOnAttempt: Int

    func probe() -> Bool {
        attempts += 1
        return attempts >= succeedsOnAttempt
    }
}
