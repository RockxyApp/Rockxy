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

    // MARK: Extended ACLs

    //
    // These build real ACLs with `/bin/chmod +a`. The tests that need one are disabled, with the
    // reason below, on an environment whose temporary directory refuses to hold an ACL.

    @Test("A chain with no extended ACL loads")
    func noACLLoads() throws {
        let file = try Self.makeFile(in: Self.makeRoot().appendingPathComponent("leaf"))
        #expect(throws: Never.self) {
            try ProxyBackupFileTrust.readTrustedFile(at: file, trustedOwner: getuid())
        }
    }

    @Test(
        "An ACL that grants the current user write on the directory is refused",
        .enabled(if: Self.aclsAreSupported, "the temporary directory cannot hold an extended ACL")
    )
    func writeACLOnDirectoryRefused() throws {
        let file = try Self.makeFile()
        let directory = file.deletingLastPathComponent()
        try Self.addACL("\(NSUserName()) allow add_file,write", to: directory)

        guard case let .writableByExtendedACL(path, entry) = Self.refusal(for: file) else {
            Issue.record("expected writableByExtendedACL")
            return
        }
        #expect(path == Self.resolved(directory))
        #expect(entry.contains("write"))
    }

    @Test(
        "An ACL on an ANCESTOR that grants delete_child is refused",
        .enabled(if: Self.aclsAreSupported, "the temporary directory cannot hold an extended ACL")
    )
    func writeACLOnAncestorRefused() throws {
        let root = try Self.makeRoot()
        let file = try Self.makeFile(in: root.appendingPathComponent("leaf"))
        try Self.addACL("\(NSUserName()) allow delete_child", to: root)

        guard case let .writableByExtendedACL(path, _) = Self.refusal(for: file) else {
            Issue.record("expected writableByExtendedACL")
            return
        }
        #expect(path == Self.resolved(root))
        #expect(throws: ProxyBackupFileTrust.Refusal.self) {
            try ProxyBackupFileTrust.verifyDirectory(
                at: file.deletingLastPathComponent(),
                trustedOwner: getuid()
            )
        }
    }

    @Test(
        "An ACL that lets someone rewrite the ACL itself is refused",
        .enabled(if: Self.aclsAreSupported, "the temporary directory cannot hold an extended ACL")
    )
    func writeSecurityACLRefused() throws {
        let file = try Self.makeFile()
        try Self.addACL("\(NSUserName()) allow writesecurity", to: file.deletingLastPathComponent())
        guard case .writableByExtendedACL = Self.refusal(for: file) else {
            Issue.record("expected writableByExtendedACL")
            return
        }
    }

    @Test(
        "An ACL that grants write on the file itself is refused",
        .enabled(if: Self.aclsAreSupported, "the temporary directory cannot hold an extended ACL")
    )
    func writeACLOnFileRefused() throws {
        let file = try Self.makeFile()
        try Self.addACL("\(NSUserName()) allow write,append", to: file)
        guard case let .writableByExtendedACL(path, _) = Self.refusal(for: file) else {
            Issue.record("expected writableByExtendedACL")
            return
        }
        #expect(path == file.path)
    }

    @Test(
        "A read-only allow ACL and a deny ACL are accepted: neither can modify anything",
        .enabled(if: Self.aclsAreSupported, "the temporary directory cannot hold an extended ACL")
    )
    func readOnlyAndDenyACLsLoad() throws {
        let file = try Self.makeFile()
        let directory = file.deletingLastPathComponent()
        try Self.addACL("\(NSUserName()) allow read,list,search,readattr", to: directory)
        try Self.addACL("\(NSUserName()) deny write,delete", to: directory)
        #expect(throws: Never.self) {
            try ProxyBackupFileTrust.readTrustedFile(at: file, trustedOwner: getuid())
        }
    }

    @Test("The stock system directories the helper's locations sit under pass the gate")
    func realSystemChainPasses() {
        for path in ["/", "/private/var", "/Library"] {
            #expect(throws: Never.self, "\(path)") {
                try ProxyBackupFileTrust.verifyDirectory(at: URL(fileURLWithPath: path), trustedOwner: 0)
            }
        }
    }

    // MARK: Hosts and PAC URLs

    /// Hosts and PAC URLs are what a restore writes back, so the record bounds them too. An
    /// endpoint that is switched off keeps whatever host was last written, so empty is ordinary.
    @Test("An ordinary record's hosts and PAC URL are accepted, including empty ones")
    func plausibleHostsAndPACURLsAreAccepted() {
        #expect(Self.validate(serviceHosts: ["127.0.0.1", "proxy.corp.example", ""]) == nil)
        #expect(Self.validate(pacURLs: ["http://wpad.corp.example/proxy.pac", ""]) == nil)
        #expect(Self.validate(pacURLs: ["https://wpad.corp.example/proxy.pac"]) == nil)
        #expect(Self.validate(pacURLs: ["file:///etc/proxy.pac"]) == nil)
    }

    /// A host that starts with a dash would be read as a flag by `networksetup`, which takes
    /// these values as arguments.
    @Test("A host that is overlong, spaced, or dash-led is refused")
    func implausibleHostsAreRefused() {
        #expect(Self.validate(serviceHosts: [String(repeating: "a", count: 256)]) != nil)
        #expect(Self.validate(serviceHosts: ["proxy .corp.example"]) != nil)
        #expect(Self.validate(serviceHosts: ["-proxy.corp.example"]) != nil)
        #expect(Self.validate(serviceHosts: ["proxy\u{0}.example"]) != nil)
    }

    /// A PAC URL is remote JavaScript that decides where every request goes, so a record carrying
    /// one with no scheme, an unexpected scheme, or past the length bound is not usable.
    @Test("A PAC URL with no scheme, an odd scheme, or past the bound is refused")
    func implausiblePACURLsAreRefused() {
        #expect(Self.validate(pacURLs: ["wpad.corp.example/proxy.pac"]) != nil)
        #expect(Self.validate(pacURLs: ["javascript:alert(1)"]) != nil)
        #expect(Self.validate(pacURLs: ["ftp://wpad.corp.example/proxy.pac"]) != nil)
        #expect(Self.validate(pacURLs: ["http://e.example/" + String(repeating: "a", count: 2_048)]) != nil)
        #expect(Self.validate(pacURLs: ["http://wpad.corp.example/a b.pac"]) != nil)
    }

    // MARK: Private

    private struct ACLSetupFailure: Error {
        let status: Int32
    }

    /// True when a throwaway directory under the temporary location accepts a real ACL.
    private static let aclsAreSupported: Bool = {
        let probe = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProxyBackupFileTrustTests-acl-probe-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)) != nil else {
            return false
        }
        defer { try? FileManager.default.removeItem(at: probe) }
        return (try? addACL("\(NSUserName()) deny delete", to: probe)) != nil
    }()

    private static func addACL(_ rule: String, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", rule, url.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ACLSetupFailure(status: process.terminationStatus)
        }
    }

    private static func validate(
        ownedPort: Int? = 9_090,
        services: [String] = ["Wi-Fi"],
        servicePorts: [Int] = [],
        serviceHosts: [String] = [],
        pacURLs: [String] = [],
        bypassCount: Int = 0,
        allowsEmpty: Bool = false
    )
        -> String?
    {
        ProxyBackupContentValidation.failure(
            ownedPort: ownedPort,
            serviceNames: services,
            servicePorts: servicePorts,
            serviceHosts: serviceHosts,
            pacURLs: pacURLs,
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
