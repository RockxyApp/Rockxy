import CommonCrypto
import Foundation
import MachO

// Identifies the executable a live helper process is actually running, so an app update can be
// proven to have taken effect instead of being inferred from version metadata.

// MARK: - HelperExecutableIdentity

/// What a helper process reports about its own executable.
///
/// Version and build numbers describe what a binary *claims*; they are read out of an
/// `Info.plist` and two different binaries can carry identical values. The digest is the actual
/// bytes launchd started, and the launch identity distinguishes one run of that binary from the
/// next — which is the only way to tell a helper that restarted from one that merely answered
/// again. Neither value authorizes anything: this is evidence collected *after* the existing
/// signing and `SMAppService` gates, never a substitute for them.
struct HelperExecutableIdentity: Equatable, Sendable {
    /// Lowercase hex SHA-256 of the running executable's bytes.
    let executableDigest: String

    /// A UUID minted once per helper process launch. Two answers carrying the same value came
    /// from the same process, however much its metadata may have changed in between.
    let launchIdentity: String

    /// The helper's own process identifier. Diagnostic only — a PID is recyclable.
    let processIdentifier: Int32

    /// Canonicalized path of the running executable. Diagnostic provenance; it names a location,
    /// not an identity, so it is never compared to decide convergence.
    let executablePath: String

    let buildNumber: Int
    let protocolVersion: Int

    /// Whether this answer carries enough to be compared at all. An empty digest is what a helper
    /// reports when it could not read its own executable, and treating that as a match would
    /// accept every binary.
    var isWellFormed: Bool {
        HelperExecutableDigest.isWellFormedDigest(executableDigest)
            && !launchIdentity.isEmpty
            && processIdentifier > 0
            && buildNumber > 0
            && protocolVersion > 0
    }
}

// MARK: - HelperExecutableDigest

/// Streams a SHA-256 over an executable on disk, under a fixed byte ceiling.
///
/// The read is chunked and bounded so a path that unexpectedly names something enormous cannot
/// turn a launch-time check into an unbounded read. Comparison is exact string equality on the
/// lowercase hex form; there is no prefix or fuzzy match anywhere.
enum HelperExecutableDigest {
    // MARK: Internal

    enum Failure: Error, Equatable {
        case unreadable(path: String)
        case tooLarge(path: String)
    }

    /// Far above any real helper executable, and far below anything that could stall a launch.
    static let maximumExecutableByteCount = 256 * 1_024 * 1_024

    static func sha256Hex(
        atPath path: String,
        maximumByteCount: Int = maximumExecutableByteCount
    )
        throws -> String
    {
        guard !path.isEmpty, let handle = FileHandle(forReadingAtPath: path) else {
            throw Failure.unreadable(path: path)
        }
        defer { try? handle.close() }

        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        var totalByteCount = 0
        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: chunkByteCount)
            } catch {
                throw Failure.unreadable(path: path)
            }
            guard let chunk, !chunk.isEmpty else {
                break
            }
            totalByteCount += chunk.count
            guard totalByteCount <= maximumByteCount else {
                throw Failure.tooLarge(path: path)
            }
            chunk.withUnsafeBytes { buffer in
                _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
            }
        }

        guard totalByteCount > 0 else {
            // An empty file is not a helper executable, and hashing it would produce a perfectly
            // valid-looking digest for nothing at all.
            throw Failure.unreadable(path: path)
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a value has the exact shape this comparison accepts: 64 lowercase hex characters.
    static func isWellFormedDigest(_ value: String) -> Bool {
        value.count == expectedDigestCharacterCount
            && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Resolves symlinks and relative components so a diagnostic path names one location.
    static func canonicalPath(_ path: String) -> String {
        guard !path.isEmpty else {
            return path
        }
        return URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    // MARK: Private

    private static let chunkByteCount = 1 << 20
    private static let expectedDigestCharacterCount = Int(CC_SHA256_DIGEST_LENGTH) * 2
}

// MARK: - HelperExecutableLocation

/// Resolves the executable path of the *current* process.
///
/// `Bundle.main` is unreliable for a bare Mach-O launch daemon, and `CommandLine.arguments[0]` is
/// whatever the launcher chose to pass. `_NSGetExecutablePath` asks the dynamic loader what it
/// actually mapped, which is the only answer a caller cannot influence.
enum HelperExecutableLocation {
    static func currentProcessExecutablePath() -> String {
        var bufferSize = UInt32(PATH_MAX) * 4
        var buffer = [CChar](repeating: 0, count: Int(bufferSize) + 1)
        if _NSGetExecutablePath(&buffer, &bufferSize) == 0 {
            let resolved = String(cString: buffer)
            if !resolved.isEmpty {
                return HelperExecutableDigest.canonicalPath(resolved)
            }
        }
        if let executablePath = Bundle.main.executablePath, !executablePath.isEmpty {
            return HelperExecutableDigest.canonicalPath(executablePath)
        }
        return HelperExecutableDigest.canonicalPath(CommandLine.arguments.first ?? "")
    }
}
