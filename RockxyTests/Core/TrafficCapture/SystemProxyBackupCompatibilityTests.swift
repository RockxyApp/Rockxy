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
        #expect(decoded.pacEnabled == false)
        #expect(decoded.pacURL.isEmpty)
        #expect(decoded.autoDiscoveryEnabled == false)
        #expect(decoded.bypassDomains == ["localhost"])
    }

    @Test("DirectServiceBackup preserves alternate proxy fields in roundtrip")
    func roundtripsAlternateProxyFields() throws {
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
            pacEnabled: true,
            pacURL: "https://proxy.corp.com/config.pac",
            autoDiscoveryEnabled: true,
            bypassDomains: ["*.corp.internal"]
        )

        let data = try PropertyListEncoder().encode(original)
        let decoded = try PropertyListDecoder().decode(DirectServiceBackup.self, from: data)

        #expect(decoded.socksEnabled == true)
        #expect(decoded.socksHost == "socks.corp.com")
        #expect(decoded.socksPort == 1_080)
        #expect(decoded.pacEnabled == true)
        #expect(decoded.pacURL == "https://proxy.corp.com/config.pac")
        #expect(decoded.autoDiscoveryEnabled == true)
        #expect(decoded.bypassDomains == ["*.corp.internal"])
    }

    @Test("Backup recovery follows live ownership instead of backup age")
    func backupRecoveryUsesLiveOwnership() {
        #expect(ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: true,
            ownerSessionIsLive: true
        ) == .preserve)
        #expect(ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: true,
            ownerSessionIsLive: false
        ) == .restore)
        #expect(ProxyBackupRecoveryPolicy.action(
            residualOwnedServicesExist: false,
            ownerSessionIsLive: false
        ) == .clear)
    }

    @Test("Direct backups written before recovery markers decode as not pending")
    func decodesLegacyDirectBackupWithoutRecoveryMarker() throws {
        let legacy = OldDirectProxyBackup(
            services: [],
            timestamp: Date(),
            rockxyPort: 9_090
        )

        let data = try PropertyListEncoder().encode(legacy)
        let decoded = try PropertyListDecoder().decode(DirectProxyBackup.self, from: data)

        #expect(decoded.rockxyPort == 9_090)
        #expect(decoded.recoveryPending == false)
        #expect(decoded.ownerPID == nil)
        #expect(decoded.ownerStartSignature == nil)
    }

    @Test("A direct backup belongs only to the exact process instance that created it")
    func directBackupOwnerIdentityIsExact() {
        let backup = DirectProxyBackup(
            services: [],
            timestamp: Date(),
            rockxyPort: 9_090,
            ownerPID: 4_242,
            ownerStartSignature: "start-a"
        )

        #expect(DirectProxyBackupOwnerPolicy.belongsToSession(
            backup,
            processIdentifier: 4_242,
            processStartSignature: "start-a"
        ))
        #expect(!DirectProxyBackupOwnerPolicy.belongsToSession(
            backup,
            processIdentifier: 4_243,
            processStartSignature: "start-b"
        ))
        #expect(!DirectProxyBackupOwnerPolicy.belongsToSession(
            backup,
            processIdentifier: 4_242,
            processStartSignature: "start-b"
        ))
        #expect(DirectProxyBackupOwnerPolicy.ownerIsLive(
            backup,
            processIsAlive: { $0 == 4_242 },
            liveStartSignature: { _ in "start-a" }
        ))
        #expect(!DirectProxyBackupOwnerPolicy.ownerIsLive(
            backup,
            processIsAlive: { $0 == 4_242 },
            liveStartSignature: { _ in "start-b" }
        ))
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

    private struct OldDirectProxyBackup: Codable {
        let services: [DirectServiceBackup]
        let timestamp: Date
        let rockxyPort: Int
    }
}

// MARK: - ProxyBackupExtensionTests

/// What survives an override attempt extending a backup it did not write. This is the moment a
/// reclaim used to lose the record of the override it was reclaiming — after which nothing on the
/// machine could prove those settings were Rockxy's, and the service was abandoned rather than
/// undone.
struct ProxyBackupExtensionTests {
    // MARK: Internal

    @Test("Adding a service keeps every record the backup already held")
    func addingAServiceKeepsThePriorJournal() {
        let existing = DirectProxyBackup(
            services: [serviceBackup(service: "Wi-Fi")],
            timestamp: Date(timeIntervalSince1970: 1_000),
            rockxyPort: 9_090,
            ownerPID: 4_242,
            ownerStartSignature: "start-a",
            recoveryPending: true,
            journal: [applicationEntry(service: "Wi-Fi", port: 9_090)]
        )

        let extended = DirectProxyBackup.extending(
            existing,
            with: [serviceBackup(service: "Ethernet")],
            rockxyPort: 9_090,
            now: Date(timeIntervalSince1970: 2_000)
        )

        #expect(extended.services.map(\.service) == ["Wi-Fi", "Ethernet"])
        #expect(extended.journal == existing.journal)
        #expect(extended.recoveryPending)
        #expect(extended.timestamp == existing.timestamp)
        #expect(extended.ownerPID == 4_242)
        #expect(extended.ownerStartSignature == "start-a")
    }

    @Test("Taking the same services on a different port keeps every record too")
    func changingThePortKeepsThePriorJournal() {
        let existing = DirectProxyBackup(
            services: [serviceBackup(service: "Wi-Fi")],
            timestamp: Date(timeIntervalSince1970: 1_000),
            rockxyPort: 9_090,
            journal: [applicationEntry(service: "Wi-Fi", port: 9_090)]
        )

        let extended = DirectProxyBackup.extending(
            existing,
            with: [],
            rockxyPort: 9_091,
            now: Date(timeIntervalSince1970: 2_000)
        )

        #expect(extended.rockxyPort == 9_091)
        // The record still names the port its own commands were issued on, which is what a later
        // attempt compares the live settings against.
        #expect(extended.journal.first?.appliedOverridePort == 9_090)
        #expect(extended.journal == existing.journal)
    }

    @Test("A first attempt starts with no record and no recovery under way")
    func aFirstAttemptStartsClean() {
        let created = DirectProxyBackup.extending(
            nil,
            with: [serviceBackup(service: "Wi-Fi")],
            rockxyPort: 9_090,
            now: Date(timeIntervalSince1970: 2_000),
            ownerPID: 4_242,
            ownerStartSignature: "start-a"
        )

        #expect(created.journal.isEmpty)
        #expect(!created.recoveryPending)
        #expect(created.timestamp == Date(timeIntervalSince1970: 2_000))
        #expect(created.ownerPID == 4_242)
        #expect(created.ownerStartSignature == "start-a")
    }

    @Test("Nothing recorded is dropped on the way through")
    func carriedForwardKeepsBothHalves() {
        let journal = [applicationEntry(service: "Wi-Fi", port: 9_090)]
        let carried = ProxyBackupExtension.carriedForward(journal: journal, recoveryPending: true)

        #expect(carried.journal == journal)
        #expect(carried.recoveryPending)

        let fresh = ProxyBackupExtension.carriedForward(journal: nil, recoveryPending: nil)
        #expect(fresh.journal.isEmpty)
        #expect(!fresh.recoveryPending)
    }

    // MARK: Private

    private func serviceBackup(service: String) -> DirectServiceBackup {
        DirectServiceBackup(
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

    private func applicationEntry(service: String, port: Int) -> ProxyServiceRecoveryJournalEntry {
        let captured = ProxyServiceRestorationState(
            service: service,
            http: ProxyEndpointState(enabled: false, host: "", port: 0),
            https: ProxyEndpointState(enabled: false, host: "", port: 0),
            socks: ProxyEndpointState(enabled: false, host: "", port: 0),
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false,
            bypassDomains: []
        )
        return ProxyServiceRecoveryJournalEntry(
            overrideApplicationFor: captured,
            stage: .applying,
            port: port
        )
    }
}

// MARK: - DirectProxyBackupJournalCompatibilityTests

/// The recovery journal is additive: a backup written before it existed still decodes, and one
/// written with it round-trips so a retry can read the intent the previous attempt recorded.
struct DirectProxyBackupJournalCompatibilityTests {
    // MARK: Internal

    @Test("Direct backups written before the journal existed decode with no journal")
    func legacyDirectBackupDecodesWithoutJournal() throws {
        let legacy = LegacyPendingDirectProxyBackup(
            services: [makeServiceBackup()],
            timestamp: Date(),
            rockxyPort: 9_090,
            recoveryPending: true
        )

        let data = try PropertyListEncoder().encode(legacy)
        let decoded = try PropertyListDecoder().decode(DirectProxyBackup.self, from: data)

        #expect(decoded.recoveryPending)
        #expect(decoded.journal.isEmpty)
        #expect(decoded.services.map(\.service) == ["Wi-Fi"])
    }

    @Test("A journal round-trips with the backup that carries it")
    func journalRoundtripsWithTheBackup() throws {
        let live = restorationState(host: "127.0.0.1", port: 9_090, enabled: true)
        let target = restorationState(host: "proxy.corp.example", port: 8_080, enabled: true)
        let entry = ProxyServiceRecoveryJournalEntry(
            service: "Wi-Fi",
            stage: .inFlight,
            expectedPreStepState: live,
            target: target
        )
        let backup = DirectProxyBackup(
            services: [makeServiceBackup()],
            timestamp: Date(),
            rockxyPort: 9_090,
            recoveryPending: true,
            journal: [entry]
        )

        let data = try PropertyListEncoder().encode(backup)
        let decoded = try PropertyListDecoder().decode(DirectProxyBackup.self, from: data)

        #expect(decoded.journal == [entry])
        #expect(decoded.journal.first?.stage == .inFlight)
    }

    @Test("A journal this build cannot read costs the backup its journal, never its services")
    func unreadableJournalKeepsTheRestorePoint() throws {
        let unreadable = DirectProxyBackupWithForeignJournal(
            services: [makeServiceBackup()],
            timestamp: Date(),
            rockxyPort: 9_090,
            recoveryPending: true,
            journal: ["not a journal entry"]
        )

        let data = try PropertyListEncoder().encode(unreadable)
        let decoded = try PropertyListDecoder().decode(DirectProxyBackup.self, from: data)

        #expect(decoded.services.map(\.service) == ["Wi-Fi"])
        #expect(decoded.journal.isEmpty)
        #expect(decoded.recoveryPending)
    }

    @Test("One unreadable journal record never costs the records beside it")
    func oneUnreadableRecordKeepsTheOthers() throws {
        let live = restorationState(host: "127.0.0.1", port: 9_090, enabled: true)
        let target = restorationState(host: "proxy.corp.example", port: 8_080, enabled: true)
        let good = ProxyServiceRecoveryJournalEntry(
            service: "Wi-Fi",
            stage: .inFlight,
            expectedPreStepState: live,
            target: target
        )
        let mixed = DirectProxyBackupWithMixedJournal(
            services: [makeServiceBackup()],
            timestamp: Date(),
            rockxyPort: 9_090,
            recoveryPending: true,
            readableEntry: good
        )

        let data = try PropertyListEncoder().encode(mixed)
        let decoded = try PropertyListDecoder().decode(DirectProxyBackup.self, from: data)

        // The unusable record is dropped and nothing else is. A service whose record is still
        // good keeps the evidence that authorizes its restore.
        #expect(decoded.journal == [good])
        #expect(decoded.services.map(\.service) == ["Wi-Fi"])
    }

    // MARK: Private

    /// A backup whose journal holds one record this build cannot read beside one it can.
    private struct DirectProxyBackupWithMixedJournal: Encodable {
        // MARK: Internal

        let services: [DirectServiceBackup]
        let timestamp: Date
        let rockxyPort: Int
        let recoveryPending: Bool
        let readableEntry: ProxyServiceRecoveryJournalEntry

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(services, forKey: .services)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(rockxyPort, forKey: .rockxyPort)
            try container.encode(recoveryPending, forKey: .recoveryPending)
            var journal = container.nestedUnkeyedContainer(forKey: .journal)
            try journal.encode("not a journal entry")
            try journal.encode(readableEntry)
        }

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case services
            case timestamp
            case rockxyPort
            case recoveryPending
            case journal
        }
    }

    /// The direct backup shape from before the recovery journal was added.
    private struct LegacyPendingDirectProxyBackup: Codable {
        let services: [DirectServiceBackup]
        let timestamp: Date
        let rockxyPort: Int
        let recoveryPending: Bool
    }

    /// A backup whose journal key holds something this build's decoder cannot make sense of.
    private struct DirectProxyBackupWithForeignJournal: Codable {
        let services: [DirectServiceBackup]
        let timestamp: Date
        let rockxyPort: Int
        let recoveryPending: Bool
        let journal: [String]
    }

    private func makeServiceBackup(service: String = "Wi-Fi") -> DirectServiceBackup {
        DirectServiceBackup(
            service: service,
            httpEnabled: true,
            httpHost: "proxy.corp.example",
            httpPort: 8_080,
            httpsEnabled: true,
            httpsHost: "secure.corp.example",
            httpsPort: 8_443,
            socksEnabled: false,
            socksHost: "",
            socksPort: 0,
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false,
            bypassDomains: ["localhost"]
        )
    }

    private func restorationState(host: String, port: Int, enabled: Bool) -> ProxyServiceRestorationState {
        ProxyServiceRestorationState(
            service: "Wi-Fi",
            http: ProxyEndpointState(enabled: enabled, host: host, port: port),
            https: ProxyEndpointState(enabled: enabled, host: host, port: port),
            socks: ProxyEndpointState(enabled: false, host: "", port: 0),
            pacEnabled: false,
            pacURL: "",
            autoDiscoveryEnabled: false,
            bypassDomains: ["localhost"]
        )
    }
}
