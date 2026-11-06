import Foundation
@testable import Rockxy
import Testing

// The app's own read of the direct proxy backup must pass the same trust gate and content
// validation the watchdog applies, so launch recovery never restores from a record the watchdog
// refused. The owner is the user (`geteuid()`), because the app writes this file as the user.

// MARK: - DirectBackupTrustGateTests

struct DirectBackupTrustGateTests {
    // MARK: Internal

    @Test("A legitimate user-owned backup is loaded exactly as written")
    func legitimateRecordLoads() throws {
        let file = try Self.write(Self.backup())

        guard case let .loaded(backup) = SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid()) else {
            Issue.record("a legitimate record was not loaded")
            return
        }
        #expect(backup.rockxyPort == 9_090)
        #expect(backup.services.map(\.service) == ["Wi-Fi"])
    }

    @Test("A record narrowed to no services still loads, because recovery legitimately produces one")
    func narrowedRecordLoads() throws {
        let file = try Self.write(Self.backup(services: []))

        guard case .loaded = SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid()) else {
            Issue.record("a narrowed record was refused")
            return
        }
    }

    @Test("No file is reported as missing, not as a refusal")
    func missingRecord() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectBackupTrustGateTests-\(UUID().uuidString)/none.plist")

        guard case .missing = SystemProxyManager.readDirectBackup(at: url, trustedOwner: geteuid()) else {
            Issue.record("expected missing")
            return
        }
    }

    @Test("A record owned by someone other than the user is refused")
    func foreignOwnerIsRefused() throws {
        let file = try Self.write(Self.backup())

        // Root's uid stands in for "not the user": the user-owned file must not be believed as
        // a root-owned one, which is also what trusting the helper default here would have done.
        Self.expectRefused(SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid() == 0 ? 501 : 0))
    }

    @Test("A group- or world-writable record is refused")
    func looseFileModeIsRefused() throws {
        let file = try Self.write(Self.backup(), fileMode: 0o664)

        Self.expectRefused(SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid()))
    }

    @Test("A record in a group-writable directory is refused")
    func looseDirectoryIsRefused() throws {
        let file = try Self.write(Self.backup(), directoryMode: 0o775)

        Self.expectRefused(SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid()))
    }

    @Test("A symbolic link in place of the record is refused")
    func symlinkIsRefused() throws {
        let target = try Self.write(Self.backup())
        let link = target.deletingLastPathComponent().appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        Self.expectRefused(SystemProxyManager.readDirectBackup(at: link, trustedOwner: geteuid()))
    }

    @Test("A record over the size limit is refused")
    func oversizedRecordIsRefused() throws {
        let file = try Self.write(Data(repeating: 65, count: ProxyBackupFileTrust.maximumFileBytes + 1))

        Self.expectRefused(SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid()))
    }

    @Test("A record that does not decode is refused rather than half read")
    func undecodableRecordIsRefused() throws {
        let file = try Self.write(Data("not a plist".utf8))

        Self.expectRefused(SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid()))
    }

    @Test("A record with an out-of-range owned port is refused")
    func badPortIsRefused() throws {
        let file = try Self.write(Self.backup(port: 70_000))

        Self.expectRefused(SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid()))
    }

    @Test("A record with more services than any Mac has is refused")
    func tooManyServicesIsRefused() throws {
        let services = (0 ... ProxyBackupContentValidation.maximumServiceCount).map { Self.service("Service \($0)") }
        let file = try Self.write(Self.backup(services: services))

        Self.expectRefused(SystemProxyManager.readDirectBackup(at: file, trustedOwner: geteuid()))
    }

    @Test("A record with an over-long service name or bypass list is refused")
    func oversizedContentIsRefused() throws {
        let longName = String(repeating: "a", count: ProxyBackupContentValidation.maximumServiceNameLength + 1)
        let nameFile = try Self.write(Self.backup(services: [Self.service(longName)]))
        Self.expectRefused(SystemProxyManager.readDirectBackup(at: nameFile, trustedOwner: geteuid()))

        let bypass = Array(repeating: "example.test", count: ProxyBackupContentValidation.maximumBypassDomainCount + 1)
        let bypassFile = try Self.write(Self.backup(services: [Self.service("Wi-Fi", bypass: bypass)]))
        Self.expectRefused(SystemProxyManager.readDirectBackup(at: bypassFile, trustedOwner: geteuid()))
    }

    // MARK: Private

    private static func expectRefused(_ read: DirectBackupRead, sourceLocation: SourceLocation = #_sourceLocation) {
        if case .refused = read {
            return
        }
        Issue.record("expected a refusal, got \(read)", sourceLocation: sourceLocation)
    }

    private static func service(_ name: String, bypass: [String] = []) -> DirectServiceBackup {
        DirectServiceBackup(
            service: name,
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
            bypassDomains: bypass
        )
    }

    private static func backup(port: Int = 9_090, services: [DirectServiceBackup]? = nil) -> Data {
        let record = DirectProxyBackup(
            services: services ?? [service("Wi-Fi")],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            rockxyPort: port
        )
        // Encoding a plain value cannot fail; an empty Data would fail the test loudly anyway.
        return (try? PropertyListEncoder().encode(record)) ?? Data()
    }

    private static func write(_ data: Data, fileMode: Int = 0o600, directoryMode: Int = 0o700) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectBackupTrustGateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryMode]
        )
        let file = directory.appendingPathComponent("proxy-backup-direct.plist")
        try data.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: fileMode], ofItemAtPath: file.path)
        return file
    }
}
