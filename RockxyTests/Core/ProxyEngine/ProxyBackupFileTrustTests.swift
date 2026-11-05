import Foundation
@testable import Rockxy
import Testing

/// Behavioral tests for the gate the helper reads proxy backups and apply-debt records through.
/// The trusted owner is the test process's own uid, so a "wrong owner" is any other uid.
struct ProxyBackupFileTrustTests {
    // MARK: Internal

    @Test("A legitimate owner-only file loads")
    func ownerOnlyFileLoads() throws {
        let file = try Self.makeFile(directoryMode: 0o700, fileMode: 0o600)
        let data = try ProxyBackupFileTrust.readTrustedFile(at: file, trustedOwner: getuid())
        #expect(data.count == 100)
    }

    @Test("A legacy 0755 directory with a 0644 file still loads")
    func legacyModesLoad() throws {
        let file = try Self.makeFile(directoryMode: 0o755, fileMode: 0o644)
        #expect(throws: Never.self) {
            try ProxyBackupFileTrust.readTrustedFile(at: file, trustedOwner: getuid())
        }
    }

    @Test("A file exactly at the size limit loads")
    func fileAtLimitLoads() throws {
        let file = try Self.makeFile(bytes: ProxyBackupFileTrust.maximumFileBytes)
        let data = try ProxyBackupFileTrust.readTrustedFile(at: file, trustedOwner: getuid())
        #expect(data.count == ProxyBackupFileTrust.maximumFileBytes)
    }

    @Test("A file one byte over the limit is refused")
    func oversizedFileRefused() throws {
        let file = try Self.makeFile(bytes: ProxyBackupFileTrust.maximumFileBytes + 1)
        let refusal = Self.refusal(for: file)
        guard case .tooLarge = refusal else {
            Issue.record("expected tooLarge, got \(String(describing: refusal))")
            return
        }
    }

    @Test("A file owned by another user is refused")
    func wrongOwnerRefused() throws {
        let file = try Self.makeFile()
        let refusal = Self.refusal(for: file, owner: getuid() &+ 1)
        guard case .notOwnedByTrustedUser = refusal else {
            Issue.record("expected notOwnedByTrustedUser, got \(String(describing: refusal))")
            return
        }
    }

    @Test("A group-writable file is refused")
    func groupWritableFileRefused() throws {
        let refusal = try Self.refusal(for: Self.makeFile(fileMode: 0o660))
        guard case .writableByGroupOrOther = refusal else {
            Issue.record("expected writableByGroupOrOther, got \(String(describing: refusal))")
            return
        }
    }

    @Test("An other-writable file is refused")
    func otherWritableFileRefused() throws {
        let refusal = try Self.refusal(for: Self.makeFile(fileMode: 0o602))
        guard case .writableByGroupOrOther = refusal else {
            Issue.record("expected writableByGroupOrOther, got \(String(describing: refusal))")
            return
        }
    }

    @Test("A group-writable directory is refused even when the file is owner-only")
    func groupWritableDirectoryRefused() throws {
        let refusal = try Self.refusal(for: Self.makeFile(directoryMode: 0o770, fileMode: 0o600))
        guard case .writableByGroupOrOther = refusal else {
            Issue.record("expected writableByGroupOrOther, got \(String(describing: refusal))")
            return
        }
    }

    @Test("A symbolic link is refused")
    func symlinkRefused() throws {
        let real = try Self.makeFile()
        let link = real.deletingLastPathComponent().appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let refusal = Self.refusal(for: link)
        guard case .symbolicLink = refusal else {
            Issue.record("expected symbolicLink, got \(String(describing: refusal))")
            return
        }
    }

    @Test("A missing file is refused as unreadable")
    func missingFileRefused() throws {
        let file = try Self.makeFile()
        try FileManager.default.removeItem(at: file)
        let refusal = Self.refusal(for: file)
        guard case .unreadable = refusal else {
            Issue.record("expected unreadable, got \(String(describing: refusal))")
            return
        }
    }

    @Test("Out-of-range owned ports are refused and valid ones are not")
    func ownedPortRange() {
        for port in [0, -1, 65_536, 70_000] {
            #expect(Self.validate(ownedPort: port) != nil, "port \(port)")
        }
        for port in [1, 9_090, 65_535] {
            #expect(Self.validate(ownedPort: port) == nil, "port \(port)")
        }
        #expect(Self.validate(ownedPort: nil) == nil)
    }

    @Test("An empty service list is refused unless the copy is authoritative")
    func emptyServiceList() {
        #expect(Self.validate(services: []) != nil)
        #expect(Self.validate(services: [], allowsEmpty: true) == nil)
    }

    @Test("An oversized service list is refused even for the authoritative copy")
    func oversizedServiceList() {
        let names = (0 ... ProxyBackupContentValidation.maximumServiceCount).map { "Service \($0)" }
        #expect(Self.validate(services: names, allowsEmpty: true) != nil)
    }

    @Test("Empty or oversized service names, bad service ports, and huge bypass lists are refused")
    func otherContentLimits() {
        #expect(Self.validate(services: [""]) != nil)
        #expect(Self.validate(services: [String(repeating: "a", count: 257)]) != nil)
        #expect(Self.validate(servicePorts: [0, 99_999]) != nil)
        #expect(Self.validate(servicePorts: [0, 80, 65_535]) == nil)
        let tooMany = ProxyBackupContentValidation.maximumBypassDomainCount + 1
        #expect(Self.validate(bypassCount: tooMany) != nil)
    }

    // MARK: Private

    private static func validate(
        ownedPort: Int? = 9_090,
        services: [String] = ["Wi-Fi"],
        servicePorts: [Int] = [],
        bypassCount: Int = 0,
        allowsEmpty: Bool = false
    )
        -> String?
    {
        ProxyBackupContentValidation.failure(
            ownedPort: ownedPort,
            serviceNames: services,
            servicePorts: servicePorts,
            largestBypassListCount: bypassCount,
            allowsEmptyServices: allowsEmpty
        )
    }

    private static func refusal(for file: URL, owner: uid_t = getuid()) -> ProxyBackupFileTrust.Refusal? {
        do {
            _ = try ProxyBackupFileTrust.readTrustedFile(at: file, trustedOwner: owner)
            return nil
        } catch {
            return error as? ProxyBackupFileTrust.Refusal
        }
    }

    private static func makeFile(
        directoryMode: Int = 0o700,
        fileMode: Int = 0o600,
        bytes: Int = 100
    )
        throws -> URL
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProxyBackupFileTrustTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryMode]
        )
        let file = directory.appendingPathComponent("proxy-backup.plist")
        try Data(repeating: 65, count: bytes).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: fileMode], ofItemAtPath: file.path)
        return file
    }
}
