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

    @Test("A group-writable ANCESTOR of the directory is refused even when directory and file are owner-only")
    func groupWritableAncestorRefused() throws {
        let root = try Self.makeRoot()
        let ancestor = root.appendingPathComponent("ancestor")
        let file = try Self.makeFile(in: ancestor.appendingPathComponent("leaf"))
        #expect(throws: Never.self) {
            try ProxyBackupFileTrust.readTrustedFile(at: file, trustedOwner: getuid())
        }

        #expect(chmod(ancestor.path, 0o775) == 0)
        let refusal = Self.refusal(for: file)
        guard case let .writableByGroupOrOther(path, mode) = refusal else {
            Issue.record("expected writableByGroupOrOther, got \(String(describing: refusal))")
            return
        }
        #expect(path == Self.resolved(ancestor))
        #expect(mode & 0o020 != 0)
    }

    @Test("A symlinked path is judged by the directories it resolves through, not by the link")
    func symlinkedAncestorIsJudgedByItsTarget() throws {
        let root = try Self.makeRoot()
        _ = try Self.makeFile(in: root.appendingPathComponent("clean/leaf"))
        _ = try Self.makeFile(in: root.appendingPathComponent("loose/leaf"))
        #expect(chmod(root.appendingPathComponent("loose").path, 0o775) == 0)
        let cleanLink = root.appendingPathComponent("clean-link")
        let looseLink = root.appendingPathComponent("loose-link")
        try FileManager.default.createSymbolicLink(
            at: cleanLink,
            withDestinationURL: root.appendingPathComponent("clean")
        )
        try FileManager.default.createSymbolicLink(
            at: looseLink,
            withDestinationURL: root.appendingPathComponent("loose")
        )

        // A link to a trustworthy chain is as good as the chain (macOS itself reaches the temp
        // directory through /var -> /private/var), and a link to a loose one inherits the refusal.
        #expect(throws: Never.self) {
            try ProxyBackupFileTrust.readTrustedFile(
                at: cleanLink.appendingPathComponent("leaf/proxy-backup.plist"),
                trustedOwner: getuid()
            )
        }
        let refusal = Self.refusal(for: looseLink.appendingPathComponent("leaf/proxy-backup.plist"))
        guard case let .writableByGroupOrOther(path, _) = refusal else {
            Issue.record("expected writableByGroupOrOther, got \(String(describing: refusal))")
            return
        }
        #expect(path == Self.resolved(root.appendingPathComponent("loose")))
    }

    @Test("An ancestor owned by neither the trusted owner nor root is refused")
    func foreignOwnedAncestorRefused() throws {
        let file = try Self.makeFile()
        // The test user's own directories are neither root's nor uid+1's, so with another trusted
        // owner the first user-owned ancestor is where the walk must stop.
        let refusal = Self.refusal(for: file, owner: getuid() &+ 1)
        guard case let .notOwnedByTrustedUser(path, owner) = refusal else {
            Issue.record("expected notOwnedByTrustedUser, got \(String(describing: refusal))")
            return
        }
        #expect(owner == getuid())
        #expect(path.count < Self.resolved(file.deletingLastPathComponent()).count)
    }

    @Test("verifyDirectory walks the ancestors too")
    func verifyDirectoryChecksAncestors() throws {
        let root = try Self.makeRoot()
        let ancestor = root.appendingPathComponent("ancestor")
        let directory = ancestor.appendingPathComponent("leaf")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        #expect(throws: Never.self) {
            try ProxyBackupFileTrust.verifyDirectory(at: directory, trustedOwner: getuid())
        }
        #expect(chmod(ancestor.path, 0o770) == 0)
        #expect(throws: ProxyBackupFileTrust.Refusal.self) {
            try ProxyBackupFileTrust.verifyDirectory(at: directory, trustedOwner: getuid())
        }
    }

    @Test("A directory component swapped for a symlink to a path outside the chain is not followed")
    func fileIsOpenedRelativeToTheVerifiedDirectory() throws {
        // `openat` against the verified descriptor means the file is looked up in the directory
        // that was checked. A symlink where the file should be is refused, never followed out.
        let root = try Self.makeRoot()
        let outside = try Self.makeFile(in: root.appendingPathComponent("outside"))
        let file = try Self.makeFile(in: root.appendingPathComponent("inside"))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        guard case .symbolicLink = Self.refusal(for: file) else {
            Issue.record("expected symbolicLink")
            return
        }
    }

    @Test("Only an I/O failure is transient; every verdict on the file or its location is not")
    func transientRefusalsAreOnlyIOFailures() {
        #expect(ProxyBackupFileTrust.Refusal.unreadable(path: "/x", errnoCode: EIO).isTransient)
        let verdicts: [ProxyBackupFileTrust.Refusal] = [
            .notOwnedByTrustedUser(path: "/x", owner: 501),
            .writableByGroupOrOther(path: "/x", mode: 0o775),
            .symbolicLink(path: "/x"),
            .notRegularFile(path: "/x"),
            .notDirectory(path: "/x"),
            .tooLarge(path: "/x", bytes: 1)
        ]
        for verdict in verdicts {
            #expect(!verdict.isTransient, "\(verdict)")
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

    /// A fresh owner-only directory to build a chain of ancestors under.
    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProxyBackupFileTrustTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    /// The path the gate reports, which is the resolved one (`/var` is a link to `/private/var`).
    /// Resolves the way the gate does. `ProxyBackupFileTrust` uses `realpath`, which always
    /// resolves every component; Foundation's `resolvingSymlinksInPath()` does not, and on this
    /// platform left `/var/...` unresolved where the gate reported `/private/var/...`. Comparing
    /// a refusal's path against a differently-resolved expectation failed a refusal that had in
    /// fact happened, which is the worst kind of false negative on this code.
    private static func resolved(_ url: URL) -> String {
        url.path.withCString { raw in
            guard let resolved = realpath(raw, nil) else {
                return url.path
            }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    /// An owner-only `proxy-backup.plist` in `directory`, creating the chain above it owner-only.
    private static func makeFile(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let file = directory.appendingPathComponent("proxy-backup.plist")
        try Data(repeating: 65, count: 100).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
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
