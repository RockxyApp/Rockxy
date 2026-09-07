import Foundation
@testable import Rockxy
import Testing

// Regression tests for the helper proxy backup's owner identity in the core proxy engine layer.

// MARK: - HelperProxyBackupOwnerIdentityTests

/// Verifies the owner-identity fields the helper writes alongside a proxy backup, and that
/// backups written before those fields existed still decode. Uses mirror structs matching the
/// helper's `CrashRecovery` types, since the helper tool target is not linked to the test target.
struct HelperProxyBackupOwnerIdentityTests {
    // MARK: Internal

    @Test("Helper backups written before owner identity existed decode with no owner")
    func legacyBackupDecodesWithoutOwnerIdentity() throws {
        let legacy = LegacyProxyBackupMirror(
            services: [makeServiceBackup()],
            timestamp: Date(),
            rockxyPort: 9_090
        )

        let data = try PropertyListEncoder().encode(legacy)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(decoded.services.map(\.service) == ["Wi-Fi"])
        #expect(decoded.rockxyPort == 9_090)
        #expect(decoded.ownerPID == nil)
        #expect(decoded.ownerStartSignature == nil)
        #expect(decoded.recoveryPending == false)
    }

    @Test("Helper backups predating the persisted port still decode")
    func legacyBackupWithoutPortDecodes() throws {
        let legacy = LegacyProxyBackupMirror(
            services: [makeServiceBackup()],
            timestamp: Date(),
            rockxyPort: nil
        )

        let data = try PropertyListEncoder().encode(legacy)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(decoded.rockxyPort == nil)
        #expect(decoded.ownerPID == nil)
    }

    @Test("A legacy backup with residual ownership is restored rather than preserved")
    func legacyBackupIsRestoredWhenServicesAreStillOwned() throws {
        let legacy = LegacyProxyBackupMirror(
            services: [makeServiceBackup()],
            timestamp: Date(),
            rockxyPort: 9_090
        )
        let data = try PropertyListEncoder().encode(legacy)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        let ownerSessionIsLive = ProxyBackupOwnerIdentityPolicy.ownerSessionIsLive(
            recordedOwnerPID: decoded.ownerPID,
            recordedStartSignature: decoded.ownerStartSignature,
            ownerProcessIsAlive: true,
            liveStartSignature: "1788787973.748707",
            ownerPassesCallerValidation: true
        )

        #expect(!ownerSessionIsLive)
        #expect(ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: true,
            ownerSessionIsLive: ownerSessionIsLive
        ) == .restore)
    }

    @Test("Owner identity survives a plist roundtrip")
    func ownerIdentityRoundtrips() throws {
        let backup = ProxyBackupMirror(
            services: [makeServiceBackup()],
            timestamp: Date(),
            rockxyPort: 9_090,
            ownerPID: 4_242,
            ownerStartSignature: "1788787973.748707",
            recoveryPending: true
        )

        let data = try PropertyListEncoder().encode(backup)
        let decoded = try PropertyListDecoder().decode(ProxyBackupMirror.self, from: data)

        #expect(decoded.ownerPID == 4_242)
        #expect(decoded.ownerStartSignature == "1788787973.748707")
        #expect(decoded.recoveryPending)
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
        let pacEnabled: Bool
        let pacURL: String
        let autoDiscoveryEnabled: Bool
        let bypassDomains: [String]
    }

    /// Mirror of the helper's proxy backup shape before owner identity was recorded.
    private struct LegacyProxyBackupMirror: Codable {
        let services: [ServiceProxyBackupMirror]
        let timestamp: Date
        let rockxyPort: Int?
    }

    /// Mirror of CrashRecovery.ProxyBackup — must match the helper tool's struct layout,
    /// including its tolerance for missing optional keys.
    private struct ProxyBackupMirror: Codable {
        // MARK: Lifecycle

        init(
            services: [ServiceProxyBackupMirror],
            timestamp: Date,
            rockxyPort: Int?,
            ownerPID: Int32?,
            ownerStartSignature: String?,
            recoveryPending: Bool = false
        ) {
            self.services = services
            self.timestamp = timestamp
            self.rockxyPort = rockxyPort
            self.ownerPID = ownerPID
            self.ownerStartSignature = ownerStartSignature
            self.recoveryPending = recoveryPending
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            services = try container.decode([ServiceProxyBackupMirror].self, forKey: .services)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            rockxyPort = try container.decodeIfPresent(Int.self, forKey: .rockxyPort)
            ownerPID = try container.decodeIfPresent(Int32.self, forKey: .ownerPID)
            ownerStartSignature = try container.decodeIfPresent(String.self, forKey: .ownerStartSignature)
            recoveryPending = try container.decodeIfPresent(Bool.self, forKey: .recoveryPending) ?? false
        }

        // MARK: Internal

        let services: [ServiceProxyBackupMirror]
        let timestamp: Date
        let rockxyPort: Int?
        let ownerPID: Int32?
        let ownerStartSignature: String?
        let recoveryPending: Bool

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case services
            case timestamp
            case rockxyPort
            case ownerPID
            case ownerStartSignature
            case recoveryPending
        }
    }

    private func makeServiceBackup(service: String = "Wi-Fi") -> ServiceProxyBackupMirror {
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
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false,
            bypassDomains: []
        )
    }
}
