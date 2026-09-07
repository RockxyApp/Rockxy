import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ProxyRestoreCommandBuilder` in the core traffic capture layer.

struct ProxyRestoreCommandBuilderTests {
    @Test("PAC and auto discovery output parsing follows networksetup format")
    func parsesAutomaticProxyOutput() {
        let enabledPAC = ProxyRestoreCommandBuilder.parsePACOutput(
            "URL: https://proxy.example/config.pac\nEnabled: Yes\n"
        )
        let disabledPAC = ProxyRestoreCommandBuilder.parsePACOutput(
            "URL: (null)\nEnabled: No\n"
        )

        #expect(enabledPAC.enabled)
        #expect(enabledPAC.url == "https://proxy.example/config.pac")
        #expect(!disabledPAC.enabled)
        #expect(disabledPAC.url.isEmpty)
        #expect(ProxyRestoreCommandBuilder.parseAutoDiscoveryOutput("Auto Proxy Discovery: On\n"))
        #expect(!ProxyRestoreCommandBuilder.parseAutoDiscoveryOutput("Auto Proxy Discovery: Off\n"))
    }

    @Test("disabled snapshot only turns proxy states off")
    func disabledSnapshotOnlyTurnsStatesOff() {
        let snapshot = ServiceProxySnapshot(
            httpEnabled: false,
            httpHost: "",
            httpPort: 0,
            httpsEnabled: false,
            httpsHost: "",
            httpsPort: 0,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false
        )

        let commands = ProxyRestoreCommandBuilder.commands(service: "Wi-Fi", snapshot: snapshot)

        #expect(commands == [
            ["-setwebproxystate", "Wi-Fi", "off"],
            ["-setsecurewebproxystate", "Wi-Fi", "off"],
            ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
            ["-setautoproxystate", "Wi-Fi", "off"],
            ["-setproxyautodiscovery", "Wi-Fi", "off"],
        ])
    }

    @Test("disabled snapshot restores stored endpoints without enabling them")
    func disabledSnapshotRestoresStoredEndpoints() {
        let snapshot = ServiceProxySnapshot(
            httpEnabled: false,
            httpHost: "127.0.0.1",
            httpPort: 9_090,
            httpsEnabled: false,
            httpsHost: "127.0.0.1",
            httpsPort: 9_090,
            socksEnabled: false,
            socksHost: "127.0.0.1",
            socksPort: 1_080,
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false
        )

        let commands = ProxyRestoreCommandBuilder.commands(service: "Wi-Fi", snapshot: snapshot)

        #expect(Array(commands.suffix(6)) == [
            ["-setwebproxy", "Wi-Fi", "127.0.0.1", "9090"],
            ["-setwebproxystate", "Wi-Fi", "off"],
            ["-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "9090"],
            ["-setsecurewebproxystate", "Wi-Fi", "off"],
            ["-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "1080"],
            ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
        ])
        #expect(!commands.contains(["-setwebproxystate", "Wi-Fi", "on"]))
        #expect(!commands.contains(["-setsecurewebproxystate", "Wi-Fi", "on"]))
        #expect(!commands.contains(["-setsocksfirewallproxystate", "Wi-Fi", "on"]))
    }

    @Test("enabled snapshot restores hosts and re-enables matching states")
    func enabledSnapshotRestoresHosts() {
        let snapshot = ServiceProxySnapshot(
            httpEnabled: true,
            httpHost: "corp-proxy.local",
            httpPort: 8_080,
            httpsEnabled: true,
            httpsHost: "corp-secure.local",
            httpsPort: 8_443,
            socksEnabled: true,
            socksHost: "corp-socks.local",
            socksPort: 1_080,
            pacEnabled: true,
            pacURL: "https://proxy.corp.example/config.pac",
            autoDiscoveryEnabled: true
        )

        let commands = ProxyRestoreCommandBuilder.commands(service: "Wi-Fi", snapshot: snapshot)

        #expect(commands == [
            ["-setwebproxystate", "Wi-Fi", "off"],
            ["-setsecurewebproxystate", "Wi-Fi", "off"],
            ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
            ["-setautoproxystate", "Wi-Fi", "off"],
            ["-setproxyautodiscovery", "Wi-Fi", "off"],
            ["-setwebproxy", "Wi-Fi", "corp-proxy.local", "8080"],
            ["-setwebproxystate", "Wi-Fi", "on"],
            ["-setsecurewebproxy", "Wi-Fi", "corp-secure.local", "8443"],
            ["-setsecurewebproxystate", "Wi-Fi", "on"],
            ["-setsocksfirewallproxy", "Wi-Fi", "corp-socks.local", "1080"],
            ["-setsocksfirewallproxystate", "Wi-Fi", "on"],
            ["-setautoproxyurl", "Wi-Fi", "https://proxy.corp.example/config.pac"],
            ["-setautoproxystate", "Wi-Fi", "on"],
            ["-setproxyautodiscovery", "Wi-Fi", "on"],
        ])
    }
}
