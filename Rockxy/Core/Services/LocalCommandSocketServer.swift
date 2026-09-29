import Darwin
import Foundation
import os

// A Unix-domain socket that answers one newline-terminated request per connection. The socket
// file is readable and writable only by the current user, lives in the app's private support
// folder, and each connection's peer must run as the same user.

// MARK: - LocalCommandSocketServer

final class LocalCommandSocketServer: @unchecked Sendable {
    // MARK: Lifecycle

    init(handler: @escaping @Sendable (Data) async -> Data) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    // MARK: Internal

    enum StartError: LocalizedError {
        case pathTooLong
        case socketFailed(Int32)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .pathTooLong:
                String(localized: "The command-line socket path is too long.", bundle: RockxyLocalization.bundle)
            case let .socketFailed(code):
                String(
                    localized: "The command-line socket could not be opened (\(String(cString: strerror(code)))).",
                    bundle: RockxyLocalization.bundle
                )
            }
        }
    }

    /// Largest request accepted from a client.
    static let maxRequestSize = 64 * 1_024

    private(set) var path: String?

    func start(path: String) throws {
        stop()
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            throw StartError.pathTooLong
        }
        removeStaleSocket(at: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw StartError.socketFailed(errno)
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, length) }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw StartError.socketFailed(code)
        }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw StartError.socketFailed(code)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection(on: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        lock.withLock {
            listenSource = source
            self.path = path
        }
        Self.logger.info("Command-line control listening")
    }

    func stop() {
        let (source, oldPath) = lock.withLock { () -> (DispatchSourceRead?, String?) in
            let current = (listenSource, path)
            listenSource = nil
            path = nil
            return current
        }
        source?.cancel()
        if let oldPath {
            unlink(oldPath)
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CommandLineControl")

    private let handler: @Sendable (Data) async -> Data
    private let queue = DispatchQueue(label: "\(RockxyIdentity.current.logSubsystem).command-line-control")
    private let lock = NSLock()
    private var listenSource: DispatchSourceRead?

    /// Removes a leftover socket file from a previous run, and nothing that is not a socket.
    private func removeStaleSocket(at path: String) {
        var info = stat()
        if lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK {
            unlink(path)
        }
    }

    private func acceptConnection(on listener: Int32) {
        let client = accept(listener, nil, nil)
        guard client >= 0 else {
            return
        }
        _ = fcntl(client, F_SETFD, FD_CLOEXEC)
        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(client, &peerUID, &peerGID) == 0, peerUID == getuid() else {
            Self.logger.warning("Refused a command-line connection from another user")
            close(client)
            return
        }
        guard let request = readRequest(from: client) else {
            close(client)
            return
        }
        let handler = handler
        Task {
            var response = await handler(request)
            response.append(0x0A)
            response.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else {
                    return
                }
                var offset = 0
                while offset < buffer.count {
                    let written = write(client, base + offset, buffer.count - offset)
                    guard written > 0 else {
                        break
                    }
                    offset += written
                }
            }
            close(client)
        }
    }

    /// Reads up to the first newline, or `nil` when the request is too large or never ends.
    private func readRequest(from client: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.count <= Self.maxRequestSize {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else {
                return nil
            }
            if let newline = buffer[0 ..< count].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[0 ..< newline])
                return data
            }
            data.append(contentsOf: buffer[0 ..< count])
        }
        return nil
    }
}
