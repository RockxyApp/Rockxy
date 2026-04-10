import Foundation
import Testing

// Regression tests for `ProxyConfiguratorBypass` in the core proxy engine layer.

// MARK: - ProxyBackupBypassTests

/// Tests for the ProxyBackup plist serialization shape, verifying that bypass domain
/// fields encode/decode correctly. Uses mirror structs matching CrashRecovery types
/// since the helper tool target is not linked to the test target.
struct ProxyBackupBypassTests {
    // MARK: Internal

    @Test("ProxyBackup encodes and decodes bypass domains")
    func backupRoundtripWithDomains() throws {
        let original = makeBackup(bypassDomains: ["localhost", "*.local"])

        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(decoded.services.count == 1)
        #expect(decoded.services[0].bypassDomains == ["localhost", "*.local"])
        #expect(decoded.services[0].service == "Wi-Fi")
    }

    @Test("ProxyBackup encodes and decodes empty bypass domains")
    func backupRoundtripEmptyDomains() throws {
        let original = makeBackup(bypassDomains: [])

        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(decoded.services.count == 1)
        #expect(decoded.services[0].bypassDomains.isEmpty)
    }

    @Test("ProxyBackup preserves all proxy fields alongside bypass domains")
    func backupPreservesAllFields() throws {
        let serviceBackup = ServiceProxyBackupMirror(
            service: "Ethernet",
            httpEnabled: true,
            httpHost: "proxy.corp.com",
            httpPort: 8_080,
            httpsEnabled: true,
            httpsHost: "proxy.corp.com",
            httpsPort: 8_443,
            socksEnabled: true,
            socksHost: "socks.corp.com",
            socksPort: 1_080,
            bypassDomains: ["localhost", "127.0.0.1", "*.internal.corp.com"]
        )
        let original = ProxyBackupMirror(
            services: [serviceBackup],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(decoded.services.count == 1)
        let decodedService = decoded.services[0]
        #expect(decodedService.service == "Ethernet")
        #expect(decodedService.httpEnabled == true)
        #expect(decodedService.httpHost == "proxy.corp.com")
        #expect(decodedService.httpPort == 8_080)
        #expect(decodedService.httpsEnabled == true)
        #expect(decodedService.httpsHost == "proxy.corp.com")
        #expect(decodedService.httpsPort == 8_443)
        #expect(decodedService.socksEnabled == true)
        #expect(decodedService.socksHost == "socks.corp.com")
        #expect(decodedService.socksPort == 1_080)
        #expect(decodedService.bypassDomains.count == 3)
        #expect(decodedService.bypassDomains.contains("*.internal.corp.com"))
    }

    @Test("Old single-service backup format fails to decode with new multi-service struct")
    func oldFormatDoesNotDecode() throws {
        // Mirror of the old single-service ProxyBackup shape.
        struct OldProxyBackup: Codable {
            let service: String
            let httpEnabled: Bool
            let httpHost: String
            let httpPort: Int
            let httpsEnabled: Bool
            let httpsHost: String
            let httpsPort: Int
            let socksEnabled: Bool
            let socksHost: String
            let socksPort: Int
            let timestamp: Date
            let bypassDomains: [String]
        }

        let old = OldProxyBackup(
            service: "Wi-Fi",
            httpEnabled: false,
            httpHost: "",
            httpPort: 0,
            httpsEnabled: false,
            httpsHost: "",
            httpsPort: 0,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            timestamp: Date(),
            bypassDomains: []
        )

        let data = try PropertyListEncoder().encode(old)

        let result = try? PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(result == nil, "Old single-service backups should not decode with the new multi-service struct")
    }

    @Test("ProxyBackup timestamp survives plist roundtrip")
    func backupTimestampRoundtrip() throws {
        let original = makeBackup(bypassDomains: ["test.local"])

        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(abs(decoded.timestamp.timeIntervalSince(original.timestamp)) < 1)
    }

    @Test("ProxyBackup with multiple services roundtrips correctly")
    func multiServiceRoundtrip() throws {
        let wifiBackup = ServiceProxyBackupMirror(
            service: "Wi-Fi",
            httpEnabled: true,
            httpHost: "127.0.0.1",
            httpPort: 9_090,
            httpsEnabled: false,
            httpsHost: "",
            httpsPort: 0,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            bypassDomains: ["localhost"]
        )
        let ethernetBackup = ServiceProxyBackupMirror(
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
            bypassDomains: ["*.internal.corp.com", "10.0.0.0/8"]
        )
        let original = ProxyBackupMirror(
            services: [wifiBackup, ethernetBackup],
            timestamp: Date()
        )

        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(decoded.services.count == 2)
        #expect(decoded.services[0].service == "Wi-Fi")
        #expect(decoded.services[0].httpEnabled == true)
        #expect(decoded.services[0].httpPort == 9_090)
        #expect(decoded.services[0].socksEnabled == false)
        #expect(decoded.services[0].bypassDomains == ["localhost"])
        #expect(decoded.services[1].service == "Ethernet")
        #expect(decoded.services[1].httpsEnabled == true)
        #expect(decoded.services[1].httpsPort == 8_443)
        #expect(decoded.services[1].socksEnabled == true)
        #expect(decoded.services[1].socksHost == "socks.corp.com")
        #expect(decoded.services[1].socksPort == 1_080)
        #expect(decoded.services[1].bypassDomains == ["*.internal.corp.com", "10.0.0.0/8"])
    }

    // MARK: Private

    /// Mirror of CrashRecovery.ServiceProxyBackup — must match the helper tool's struct layout.
    private struct ServiceProxyBackupMirror: Codable {
        let service: String
        let httpEnabled: Bool
        let httpHost: String
        let httpPort: Int
        let httpsEnabled: Bool
        let httpsHost: String
        let httpsPort: Int
        let socksEnabled: Bool
        let socksHost: String
        let socksPort: Int
        let bypassDomains: [String]
    }

    /// Mirror of CrashRecovery.ProxyBackup — must match the helper tool's struct layout.
    private struct ProxyBackupMirror: Codable {
        let services: [ServiceProxyBackupMirror]
        let timestamp: Date
    }

    private func makeServiceBackup(
        service: String = "Wi-Fi",
        bypassDomains: [String] = []
    )
        -> ServiceProxyBackupMirror
    {
        ServiceProxyBackupMirror(
            service: service,
            httpEnabled: false,
            httpHost: "",
            httpPort: 0,
            httpsEnabled: false,
            httpsHost: "",
            httpsPort: 0,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            bypassDomains: bypassDomains
        )
    }

    private func makeBackup(
        serviceBackups: [ServiceProxyBackupMirror]? = nil,
        bypassDomains: [String] = []
    )
        -> ProxyBackupMirror
    {
        let services = serviceBackups ?? [makeServiceBackup(bypassDomains: bypassDomains)]
        return ProxyBackupMirror(
            services: services,
            timestamp: Date()
        )
    }
}
