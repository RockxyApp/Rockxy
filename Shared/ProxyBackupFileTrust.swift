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
/// user, are real (not symlinks), and are not writable by group or other. Every refusal is
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

    /// Checks one directory: a real directory, owned by `trustedOwner`, not group/other writable.
    static func verifyDirectory(at url: URL, trustedOwner: uid_t = 0) throws {
        let path = url.path
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw Refusal.unreadable(path: path, errnoCode: errno)
        }
        try verifyDirectory(info, path: path, trustedOwner: trustedOwner)
    }

    /// Reads `url` only if its directory and the file are trusted, and never more than
    /// `maximumFileBytes`. The file is opened without following symlinks and judged by `fstat` on
    /// the open descriptor, so what is checked is what is read.
    static func readTrustedFile(at url: URL, trustedOwner: uid_t = 0) throws -> Data {
        let path = url.path
        try verifyDirectory(at: url.deletingLastPathComponent(), trustedOwner: trustedOwner)

        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
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

    private static func verifyDirectory(_ info: stat, path: String, trustedOwner: uid_t) throws {
        if (info.st_mode & S_IFMT) == S_IFLNK {
            throw Refusal.symbolicLink(path: path)
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw Refusal.notDirectory(path: path)
        }
        guard info.st_uid == trustedOwner else {
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
