import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ProxyRestoreCommandBuilder` in the core traffic capture layer.

struct ProxyRestoreCommandBuilderTests {
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
            socksPort: 0
        )

        let commands = ProxyRestoreCommandBuilder.commands(service: "Wi-Fi", snapshot: snapshot)

        #expect(commands == [
            ["-setwebproxystate", "Wi-Fi", "off"],
            ["-setsecurewebproxystate", "Wi-Fi", "off"],
            ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
        ])
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
            socksPort: 1_080
        )

        let commands = ProxyRestoreCommandBuilder.commands(service: "Wi-Fi", snapshot: snapshot)

        #expect(commands == [
            ["-setwebproxystate", "Wi-Fi", "off"],
            ["-setsecurewebproxystate", "Wi-Fi", "off"],
            ["-setsocksfirewallproxystate", "Wi-Fi", "off"],
            ["-setwebproxy", "Wi-Fi", "corp-proxy.local", "8080"],
            ["-setwebproxystate", "Wi-Fi", "on"],
            ["-setsecurewebproxy", "Wi-Fi", "corp-secure.local", "8443"],
            ["-setsecurewebproxystate", "Wi-Fi", "on"],
            ["-setsocksfirewallproxy", "Wi-Fi", "corp-socks.local", "1080"],
            ["-setsocksfirewallproxystate", "Wi-Fi", "on"],
        ])
    }
}
