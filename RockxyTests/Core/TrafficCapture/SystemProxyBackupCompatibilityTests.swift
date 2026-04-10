import Foundation
@testable import Rockxy
import Testing

// Regression tests for `SystemProxyBackupCompatibility` in the core traffic capture layer.

struct SystemProxyBackupCompatibilityTests {
    // MARK: Internal

    @Test("DirectServiceBackup decodes old backups without SOCKS fields")
    func decodesLegacyBackupShape() throws {
        let oldBackup = OldDirectServiceBackup(
            service: "Wi-Fi",
            httpEnabled: true,
            httpHost: "127.0.0.1",
            httpPort: 9_090,
            httpsEnabled: true,
            httpsHost: "127.0.0.1",
            httpsPort: 9_090,
            bypassDomains: ["localhost"]
        )

        let data = try PropertyListEncoder().encode(oldBackup)
        let decoded = try PropertyListDecoder().decode(DirectServiceBackup.self, from: data)

        #expect(decoded.service == "Wi-Fi")
        #expect(decoded.httpEnabled == true)
        #expect(decoded.httpsEnabled == true)
        #expect(decoded.socksEnabled == false)
        #expect(decoded.socksHost.isEmpty)
        #expect(decoded.socksPort == 0)
        #expect(decoded.bypassDomains == ["localhost"])
    }

    @Test("DirectServiceBackup preserves SOCKS fields in roundtrip")
    func roundtripsSocksFields() throws {
        let original = DirectServiceBackup(
            service: "Ethernet",
            httpEnabled: false,
            httpHost: "",
            httpPort: 0,
            httpsEnabled: true,
            httpsHost: "proxy.corp.com",
            httpsPort: 8_443,
            socksEnabled: true,
            socksHost: "socks.corp.com",
            socksPort: 1_080,
            bypassDomains: ["*.corp.internal"]
        )

        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(DirectServiceBackup.self, from: data)

        #expect(decoded.socksEnabled == true)
        #expect(decoded.socksHost == "socks.corp.com")
        #expect(decoded.socksPort == 1_080)
        #expect(decoded.bypassDomains == ["*.corp.internal"])
    }

    // MARK: Private

    private struct OldDirectServiceBackup: Codable {
        let service: String
        let httpEnabled: Bool
        let httpHost: String
        let httpPort: Int
        let httpsEnabled: Bool
        let httpsHost: String
        let httpsPort: Int
        let bypassDomains: [String]
    }
}
