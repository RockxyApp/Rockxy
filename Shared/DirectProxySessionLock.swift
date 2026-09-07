import Darwin
import Foundation

// MARK: - DirectProxySessionLock

/// Serializes system-proxy ownership and recovery across app, watchdog, and helper processes.
///
/// Atomic replacement keeps one plist internally consistent, but it does not make a
/// read-capture-publish-mutate sequence atomic. Holding this advisory lock for the complete
/// sequence prevents two app instances, or an old watchdog and a new app instance, from each
/// acting on a different generation of the same system-wide proxy configuration.
enum DirectProxySessionLock {
    enum LockError: LocalizedError {
        case timedOut

        var errorDescription: String? {
            switch self {
            case .timedOut:
                "Timed out waiting for another proxy operation to finish"
            }
        }
    }

    static func withExclusiveAccess<T>(
        backupURL: URL,
        _ operation: () throws -> T
    ) throws -> T {
        _ = backupURL
        return try withGlobalExclusiveAccess(operation)
    }

    static func withExclusiveAccess<T>(
        userID: uid_t,
        _ operation: () throws -> T
    ) throws -> T {
        _ = userID
        return try withGlobalExclusiveAccess(operation)
    }

    /// Reports whether any local login account has a direct-mode restore point. Callers hold the
    /// global lock, so this inventory cannot race a current build publishing or clearing one.
    static func anyDirectBackupExists() -> Bool {
        setpwent()
        defer { endpwent() }
        while let passwordRecord = getpwent() {
            let userID = passwordRecord.pointee.pw_uid
            if let url = directBackupURL(userID: userID),
               FileManager.default.fileExists(atPath: url.path)
            {
                return true
            }
        }
        return false
    }

    private static func withGlobalExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
        // `/Users/Shared` is a stable, root-owned directory readable by every login user. Locking
        // its descriptor gives all sessions one kernel-backed mutex without creating a mutable
        // world-writable lock file that another process could unlink and replace.
        let descriptor = open("/Users/Shared", O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_uid == 0,
              status.st_mode & S_IFMT == S_IFDIR
        else {
            throw POSIXError(.EPERM)
        }

        let deadline = ProcessInfo.processInfo.systemUptime + acquisitionTimeout
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let lockError = errno
            if lockError == EINTR {
                continue
            }
            guard lockError == EWOULDBLOCK || lockError == EAGAIN else {
                throw POSIXError(POSIXErrorCode(rawValue: lockError) ?? .EIO)
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw LockError.timedOut
            }
            Thread.sleep(forTimeInterval: retryInterval)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try operation()
    }

    /// A legitimate proxy mutation may span several `networksetup` commands, so contenders wait
    /// briefly. The wait is still bounded: a foreign or wedged process can hold an advisory lock,
    /// and neither app shutdown nor either recovery watchdog may block behind it forever. Recovery
    /// callers preserve their restore point and retry from their own lifecycle after this throws.
    private static let acquisitionTimeout: TimeInterval = 5
    private static let retryInterval: TimeInterval = 0.05

    /// The unprivileged direct-mode restore point for one login user. The privileged helper uses
    /// this only after authenticating that user's XPC connection and acquiring the same lock.
    static func directBackupURL(userID: uid_t) -> URL? {
        guard let passwordRecord = getpwuid(userID) else {
            return nil
        }
        let homeDirectory = String(cString: passwordRecord.pointee.pw_dir)
        guard !homeDirectory.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(RockxyIdentity.current.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("proxy-backup-direct.plist")
    }
}
