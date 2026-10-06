import Foundation
import NIOCore
import NIOSSL
import os

// MARK: - TLSKeyLogWriter

/// Appends TLS session secrets in the NSS key log format (the `SSLKEYLOGFILE` format read by
/// Wireshark) for every handshake Rockxy terminates or originates while logging is on.
///
/// The file lets anyone holding a packet capture decrypt it, so logging is off by default,
/// the file is created readable by the current user only, and nothing is installed on a TLS
/// configuration while logging is off.
final class TLSKeyLogWriter: @unchecked Sendable {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    static let shared = TLSKeyLogWriter()

    var destination: URL? {
        lock.withLock { url }
    }

    /// Adds the key log callback to `configuration` when logging is on.
    static func apply(to configuration: inout TLSConfiguration, writer: TLSKeyLogWriter = .shared) {
        guard writer.destination != nil else {
            return
        }
        configuration.keyLogCallback = { [weak writer] line in
            writer?.append(line)
        }
    }

    /// Starts appending to `url`, or stops logging when `url` is `nil`.
    func setDestination(_ url: URL?) throws {
        var handle: FileHandle?
        if let url {
            let manager = FileManager.default
            if !manager.fileExists(atPath: url.path) {
                guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
                }
            }
            let opened = try FileHandle(forWritingTo: url)
            try opened.seekToEnd()
            handle = opened
        }
        let previous: FileHandle? = lock.withLock {
            let old = fileHandle
            fileHandle = handle
            self.url = url
            return old
        }
        queue.async {
            try? previous?.close()
        }
    }

    /// Waits until every queued line is written. For tests.
    func flush() {
        queue.sync {}
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "TLSKeyLog")

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.rockxy.tls-key-log")
    private var fileHandle: FileHandle?
    private var url: URL?

    private func append(_ line: ByteBuffer) {
        guard let handle = lock.withLock({ fileHandle }) else {
            return
        }
        var data = Data(line.readableBytesView)
        data.append(0x0A)
        queue.async {
            do {
                try handle.write(contentsOf: data)
            } catch {
                Self.logger.error("TLS key log write failed: \(error.localizedDescription)")
            }
        }
    }
}
