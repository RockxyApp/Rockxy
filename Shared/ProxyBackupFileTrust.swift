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
/// either. The chain is walked with `openat`, so the directory that was checked is the directory
/// the file is opened in. Every refusal is
/// thrown with the path and the failing condition so a caller can log it. Nothing here falls back
/// silently.
enum ProxyBackupFileTrust {
    // MARK: Internal

    enum Refusal: Error, Equatable, CustomStringConvertible {
        case notOwnedByTrustedUser(path: String, owner: UInt32)
        case writableByGroupOrOther(path: String, mode: UInt16)
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
            case let .symbolicLink(path):
                "\(path) is a symbolic link"
            case let .notRegularFile(path):
                "\(path) is not a regular file"
            case let .notDirectory(path):
                "\(path) is not a directory"
            case let .tooLarge(path, bytes):
                "\(path) is \(bytes) bytes, over the \(ProxyBackupFileTrust.maximumFileBytes) byte limit"
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
        close(try openVerifiedDirectory(at: url, trustedOwner: trustedOwner))
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
        return nil
    }
}
