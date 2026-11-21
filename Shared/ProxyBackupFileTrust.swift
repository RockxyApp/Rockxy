import Foundation

// MARK: - ProxyBackupFileTrust

/// Decides whether a proxy backup or apply-debt file may be believed, and reads it with a bound.
///
/// The helper runs as root and writes whatever these files say onto every network service, so a
/// file anyone else could have written is a man-in-the-middle primitive. The helper's own
/// directory is root-only on a default install; this makes the reader enforce that instead of
/// assuming it, because the compatibility location lives in a shared parent that a loosened
/// system could let an admin-group process write to.
///
/// A file is trusted only when its directory and the file itself are both owned by the trusted
/// user, are real (not symlinks), and are not writable by group or other, and when every ancestor
/// of that directory is owned by the trusted user or root and is not writable by group or other
/// either, and when none of those directories (nor the file) carries an extended ACL that grants
/// modifying access to anyone but root. The chain is walked with `openat`, so the directory that was checked is the
/// directory
/// the file is opened in. Every refusal is
/// thrown with the path and the failing condition so a caller can log it. Nothing here falls back
/// silently.
enum ProxyBackupFileTrust {
    // MARK: Internal

    enum Refusal: Error, Equatable, CustomStringConvertible {
        case notOwnedByTrustedUser(path: String, owner: UInt32)
        case writableByGroupOrOther(path: String, mode: UInt16)
        case writableByExtendedACL(path: String, entry: String)
        case symbolicLink(path: String)
        case notRegularFile(path: String)
        case notDirectory(path: String)
        case tooLarge(path: String, bytes: Int64)
        case unreadable(path: String, errnoCode: Int32)

        // MARK: Internal

        /// True only for a failure that may clear by itself (an I/O error, a file mid-replacement).
        /// Every other refusal is a verdict about the file or its location and will repeat until
        /// somebody changes it, so a caller that retries one forever is polling for nothing.
        var isTransient: Bool {
            if case .unreadable = self {
                return true
            }
            return false
        }

        var description: String {
            switch self {
            case let .notOwnedByTrustedUser(path, owner):
                "\(path) is owned by uid \(owner), not the trusted owner"
            case let .writableByGroupOrOther(path, mode):
                "\(path) is writable by group or other (mode \(String(mode, radix: 8)))"
            case let .writableByExtendedACL(path, entry):
                "\(path) has an extended ACL entry that lets someone other than root modify it (\(entry))"
            case let .symbolicLink(path):
                "\(path) is a symbolic link"
            case let .notRegularFile(path):
                "\(path) is not a regular file"
            case let .notDirectory(path):
                "\(path) is not a directory"
            case let .tooLarge(path, bytes):
                "\(path) is over the size limit (byte count: \(bytes), maximum byte count: \(ProxyBackupFileTrust.maximumFileBytes))"
            case let .unreadable(path, code):
                "\(path) could not be read: \(String(cString: strerror(code)))"
            }
        }
    }

    /// Upper bound on a backup or debt file.
    ///
    /// The largest legitimate payload is a backup of every network service: a Mac with a dozen
    /// services (Wi-Fi, Ethernet, VPNs, Thunderbolt bridges) at roughly 1 KB of endpoints each,
    /// plus a bypass list that rarely passes a few hundred entries at about 40 bytes each, plus
    /// one recovery-journal entry per service, is well under 200 KB even in plist XML. 512 KiB
    /// leaves more than 2x headroom for an unusually busy machine while still refusing a file
    /// padded to exhaust the helper's memory. The apply-debt record is a few hundred bytes and
    /// shares the bound.
    static let maximumFileBytes = 512 * 1_024

    /// Checks one directory and every ancestor above it. See `openVerifiedDirectory`.
    static func verifyDirectory(at url: URL, trustedOwner: uid_t = 0) throws {
        try close(openVerifiedDirectory(at: url, trustedOwner: trustedOwner))
    }

    /// Reads `url` only if its whole directory chain and the file are trusted, and never more than
    /// `maximumFileBytes`. The directory chain is walked with `openat` and the file is then opened
    /// relative to the verified directory descriptor without following symlinks and judged by
    /// `fstat` on the open descriptor, so what is checked is what is read: no path is resolved a
    /// second time between the check and the use.
    static func readTrustedFile(at url: URL, trustedOwner: uid_t = 0) throws -> Data {
        let path = url.path
        let directoryDescriptor = try openVerifiedDirectory(
            at: url.deletingLastPathComponent(),
            trustedOwner: trustedOwner
        )
        defer { close(directoryDescriptor) }

        let descriptor = openat(
            directoryDescriptor,
            url.lastPathComponent,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw Refusal.symbolicLink(path: path)
            }
            throw Refusal.unreadable(path: path, errnoCode: errno)
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw Refusal.unreadable(path: path, errnoCode: errno)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw Refusal.notRegularFile(path: path)
        }
        guard info.st_uid == trustedOwner else {
            throw Refusal.notOwnedByTrustedUser(path: path, owner: info.st_uid)
        }
        guard info.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
            throw Refusal.writableByGroupOrOther(path: path, mode: info.st_mode & 0o7777)
        }
        try verifyNoForeignWriteACL(descriptor, path: path)
        guard info.st_size <= Int64(maximumFileBytes) else {
            throw Refusal.tooLarge(path: path, bytes: info.st_size)
        }

        // The size above can be stale if the file grows, so the read itself is bounded too.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw Refusal.unreadable(path: path, errnoCode: errno)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
            if data.count > maximumFileBytes {
                throw Refusal.tooLarge(path: path, bytes: Int64(data.count))
            }
        }
        return data
    }

    // MARK: Private

    /// Permissions that let a principal change the object, its contents, its children, or the
    /// rules that govern it. `WRITE_SECURITY` and `CHANGE_OWNER` count because holding either
    /// is the ability to grant oneself everything else.
    private static let modifyingACLPermissions: UInt64 = [
        ACL_WRITE_DATA, ACL_ADD_FILE, ACL_APPEND_DATA, ACL_ADD_SUBDIRECTORY, ACL_DELETE,
        ACL_DELETE_CHILD, ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_WRITE_SECURITY,
        ACL_CHANGE_OWNER
    ].reduce(0) { $0 | UInt64($1.rawValue) }

    /// The well-known GUID of uid 0: the fixed prefix `FFFFEEEE-DDDD-CCCC-BBBB-AAAA` followed by
    /// the uid as 32 big-endian bits. Compared as bytes so no directory-service lookup (which a
    /// helper may not be able to reach, and which could be answered by something other than root)
    /// stands between an ACL entry and the verdict. Group GUIDs use a different prefix, so a
    /// `wheel` entry is not mistaken for root.
    private static let rootUserGUID: [UInt8] = [
        0xFF, 0xFF, 0xEE, 0xEE, 0xDD, 0xDD, 0xCC, 0xCC, 0xBB, 0xBB, 0xAA, 0xAA, 0x00, 0x00, 0x00, 0x00
    ]

    /// Resolves `url` once, then opens every component of the RESOLVED path with
    /// `O_NOFOLLOW | O_DIRECTORY` relative to the previous component's descriptor, judging each
    /// directory by `fstat` on the descriptor it just opened. Returns the leaf directory's
    /// descriptor, still open, for the caller to open the file relative to.
    ///
    /// Why every ancestor: `lstat` on a directory describes the directory it resolves to and says
    /// nothing about the path taken to reach it. A leaf directory that is root-owned and 0700 is
    /// only as trustworthy as every directory above it, because whoever can write one of those can
    /// rename the leaf away or swap a component for a symlink. Checking the leaf alone passes
    /// silently if a location ever sits under a group-writable ancestor, a symlink to another
    /// volume, or a directory an installer created `0775`.
    ///
    /// The leaf must be owned by `trustedOwner`. Each ancestor must be owned by `trustedOwner` or
    /// root: the system's own `/`, `/Library`, `/Users` are root's, a home directory is the user's.
    /// None may be writable by group or other. Components are opened without following symlinks,
    /// so a component swapped for a link after the resolution fails closed instead of being
    /// followed; a symlink in the requested path (`/var`, a relocated home) is resolved up front
    /// and its target chain is what gets verified.
    private static func openVerifiedDirectory(at url: URL, trustedOwner: uid_t) throws -> Int32 {
        let requested = url.path
        guard let resolvedPointer = realpath(requested, nil) else {
            throw Refusal.unreadable(path: requested, errnoCode: errno)
        }
        let resolved = String(cString: resolvedPointer)
        free(resolvedPointer)

        let components = resolved.split(separator: "/").map(String.init)
        var current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else {
            throw Refusal.unreadable(path: "/", errnoCode: errno)
        }
        do {
            try verifyDescriptor(current, path: "/", trustedOwner: trustedOwner, isLeaf: components.isEmpty)
            var walked = ""
            for (index, name) in components.enumerated() {
                walked += "/" + name
                let next = openat(current, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else {
                    throw openFailure(errno, parent: current, name: name, path: walked)
                }
                close(current)
                current = next
                try verifyDescriptor(
                    next,
                    path: walked,
                    trustedOwner: trustedOwner,
                    isLeaf: index == components.count - 1
                )
            }
        } catch {
            close(current)
            throw error
        }
        return current
    }

    private static func openFailure(_ code: Int32, parent: Int32, name: String, path: String) -> Refusal {
        switch code {
        case ELOOP:
            return .symbolicLink(path: path)
        case ENOTDIR:
            // `O_DIRECTORY | O_NOFOLLOW` on a symlink may report either; look at the entry itself.
            var info = stat()
            if fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
                return .symbolicLink(path: path)
            }
            return .notDirectory(path: path)
        default:
            return .unreadable(path: path, errnoCode: code)
        }
    }

    private static func verifyDescriptor(
        _ descriptor: Int32,
        path: String,
        trustedOwner: uid_t,
        isLeaf: Bool
    )
        throws
    {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw Refusal.unreadable(path: path, errnoCode: errno)
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw Refusal.notDirectory(path: path)
        }
        let ownerIsAcceptable = isLeaf
            ? info.st_uid == trustedOwner
            : (info.st_uid == trustedOwner || info.st_uid == 0)
        guard ownerIsAcceptable else {
            throw Refusal.notOwnedByTrustedUser(path: path, owner: info.st_uid)
        }
        guard info.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
            throw Refusal.writableByGroupOrOther(path: path, mode: info.st_mode & 0o7777)
        }
        try verifyNoForeignWriteACL(descriptor, path: path)
    }

    /// Refuses an object whose extended ACL lets anyone but root modify it.
    ///
    /// POSIX mode bits are not the whole access decision on macOS: an `allow` ACL entry can give
    /// write, append, delete, or the right to rewrite the ACL itself to a user or group while the
    /// mode reads `0755`. Policy: any `ACL_EXTENDED_ALLOW` entry carrying a modifying permission
    /// (see `modifyingACLPermissions`) whose qualifier is not uid 0 fails the gate. Read-only
    /// allows and `deny` entries are ignored (a deny only narrows access; ignoring it is the
    /// conservative reading). Inherit-only entries still count, since they stamp the grant onto
    /// every child created later. A qualifier that cannot be resolved to a uid is treated as foreign.
    ///
    /// The ACL is read with `acl_get_fd_np(fd, ACL_TYPE_EXTENDED)` on the descriptor the walk
    /// already opened and `fstat`ed, so it describes that inode and no path is resolved again.
    /// "No ACL" (`ENOENT`) and a filesystem that cannot carry ACLs (`ENOTSUP`) pass; any other
    /// error fails closed.
    private static func verifyNoForeignWriteACL(_ descriptor: Int32, path: String) throws {
        errno = 0
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT || errno == ENOTSUP {
                return
            }
            throw Refusal.unreadable(path: path, errnoCode: errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }

        var entry: acl_entry_t?
        var selector = Int32(ACL_FIRST_ENTRY.rawValue)
        while acl_get_entry(acl, selector, &entry) == 0, let current = entry {
            selector = Int32(ACL_NEXT_ENTRY.rawValue)

            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(current, &tag) == 0 else {
                throw Refusal.writableByExtendedACL(path: path, entry: "unreadable entry")
            }
            guard tag == ACL_EXTENDED_ALLOW else {
                continue
            }
            var permissions: UInt64 = 0
            guard acl_get_permset_mask_np(current, &permissions) == 0 else {
                throw Refusal.writableByExtendedACL(path: path, entry: "unreadable permissions")
            }
            guard permissions & modifyingACLPermissions != 0 else {
                continue
            }
            if !aclQualifierIsRootUser(current) {
                throw Refusal.writableByExtendedACL(path: path, entry: aclEntryDescription(permissions))
            }
        }
    }

    private static func aclQualifierIsRootUser(_ entry: acl_entry_t) -> Bool {
        guard let raw = acl_get_qualifier(entry) else {
            return false
        }
        defer { acl_free(raw) }
        let bytes = UnsafeRawBufferPointer(start: raw, count: rootUserGUID.count)
        return Array(bytes) == rootUserGUID
    }

    private static func aclEntryDescription(_ permissions: UInt64) -> String {
        let names: [(acl_perm_t, String)] = [
            (ACL_WRITE_DATA, "write"), (ACL_ADD_FILE, "add_file"), (ACL_APPEND_DATA, "append"),
            (ACL_ADD_SUBDIRECTORY, "add_subdirectory"), (ACL_DELETE, "delete"),
            (ACL_DELETE_CHILD, "delete_child"), (ACL_WRITE_ATTRIBUTES, "writeattr"),
            (ACL_WRITE_EXTATTRIBUTES, "writeextattr"), (ACL_WRITE_SECURITY, "writesecurity"),
            (ACL_CHANGE_OWNER, "chown")
        ]
        let granted = names.filter { permissions & UInt64($0.0.rawValue) != 0 }.map(\.1)
        return "allow " + granted.joined(separator: ",")
    }
}

// MARK: - ProxyBackupContentValidation

/// Sanity limits on a decoded backup or debt, applied before anything reaches a network service.
/// Trust in the file decides who may have written it; these decide whether what it says is
/// plausible, so a corrupt or hostile record is refused rather than half applied.
enum ProxyBackupContentValidation {
    /// More services than any Mac carries; a larger list is padding, not a backup.
    static let maximumServiceCount = 64
    static let maximumServiceNameLength = 256
    static let maximumBypassDomainCount = 2_048
    /// A hostname cannot exceed 253 characters; the few spare bytes keep an IPv6 literal in scope.
    static let maximumHostLength = 255
    /// A PAC URL is remote JavaScript that decides where every request goes, so it is the single
    /// highest-value field in the record and the one worth bounding hardest.
    static let maximumPACURLLength = 2_048
    /// Schemes `networksetup` accepts for an automatic proxy configuration. Anything else in a
    /// record means the record is not describing a proxy configuration macOS produced.
    static let allowedPACSchemes: Set<String> = ["http", "https", "file"]

    /// Returns the reason a record is not plausible, or nil when it is.
    ///
    /// `allowsEmptyServices` is true only for the authoritative copy: recovery's own bookkeeping
    /// can legitimately narrow a backup to nothing while a session still runs, and refusing that
    /// would strand the record and block every later restore. An empty list writes nothing, so
    /// the only copies that must refuse it are the ones whose provenance is weaker.
    static func failure(
        ownedPort: Int?,
        serviceNames: [String],
        servicePorts: [Int] = [],
        serviceHosts: [String] = [],
        pacURLs: [String] = [],
        largestBypassListCount: Int = 0,
        allowsEmptyServices: Bool = false
    )
        -> String?
    {
        if let ownedPort, !(1 ... 65_535).contains(ownedPort) {
            return "owned port \(ownedPort) is outside 1-65535"
        }
        if serviceNames.isEmpty, !allowsEmptyServices {
            return "service list is empty"
        }
        if serviceNames.count > maximumServiceCount {
            return "service list has \(serviceNames.count) entries, over \(maximumServiceCount)"
        }
        if serviceNames.contains(where: { $0.isEmpty || $0.count > maximumServiceNameLength }) {
            return "a service name is empty or longer than \(maximumServiceNameLength) characters"
        }
        // Disabled services are stored with port 0, so the per-service range starts there.
        if let port = servicePorts.first(where: { !(0 ... 65_535).contains($0) }) {
            return "a service port \(port) is outside 0-65535"
        }
        if largestBypassListCount > maximumBypassDomainCount {
            return "a bypass list has \(largestBypassListCount) entries, over \(maximumBypassDomainCount)"
        }
        // Hosts and PAC URLs are what the restore actually writes back, so bound them too. An
        // endpoint that is switched off keeps whatever host was last written, including none, so
        // an empty value is ordinary and only a present one is judged.
        if let host = serviceHosts.first(where: { !$0.isEmpty && hostFailureReason($0) != nil }) {
            return "a proxy host \(hostFailureReason(host) ?? "is not usable")"
        }
        if let url = pacURLs.first(where: { !$0.isEmpty && pacURLFailureReason($0) != nil }) {
            return "a PAC URL \(pacURLFailureReason(url) ?? "is not usable")"
        }
        return nil
    }

    /// Why a non-empty proxy host cannot be written back, or nil when it can.
    ///
    /// A leading `-` matters beyond tidiness: these values become `networksetup` arguments, and an
    /// argument that starts with a dash is read as a flag.
    static func hostFailureReason(_ host: String) -> String? {
        if host.utf8.count > maximumHostLength {
            return "is longer than \(maximumHostLength) characters"
        }
        if host.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return "contains whitespace"
        }
        if host.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            return "contains a control character"
        }
        if host.hasPrefix("-") {
            return "starts with a dash, which networksetup would read as a flag"
        }
        return nil
    }

    /// Why a non-empty PAC URL cannot be written back, or nil when it can.
    static func pacURLFailureReason(_ pacURL: String) -> String? {
        if pacURL.utf8.count > maximumPACURLLength {
            return "is longer than \(maximumPACURLLength) characters"
        }
        if pacURL.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return "contains whitespace"
        }
        if pacURL.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            return "contains a control character"
        }
        guard let scheme = URL(string: pacURL)?.scheme?.lowercased() else {
            return "has no scheme"
        }
        guard allowedPACSchemes.contains(scheme) else {
            return "uses the \(scheme) scheme, which is not one macOS configures"
        }
        return nil
    }
}
