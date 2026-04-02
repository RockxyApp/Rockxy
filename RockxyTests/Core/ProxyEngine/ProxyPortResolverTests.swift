import Foundation
@testable import Rockxy
import Testing

// MARK: - ProxyPortResolverTests

// Regression tests for `ProxyPortResolver` in the proxy engine layer.

struct ProxyPortResolverTests {
    // MARK: - Port Availability

    @Test("isPortAvailable returns true for unoccupied port")
    func availablePortReturnsTrue() {
        let available = ProxyPortResolver.isPortAvailable(port: 59100, address: "127.0.0.1")
        #expect(available == true)
    }

    @Test("isPortAvailable returns false for occupied port")
    func occupiedPortReturnsFalse() throws {
        let listener = try TCPListener(port: 0, address: "127.0.0.1")
        defer { listener.close() }

        let available = ProxyPortResolver.isPortAvailable(port: listener.boundPort, address: "127.0.0.1")
        #expect(available == false)
    }

    // MARK: - Resolution

    @Test("resolve returns preferred port when available")
    func resolvePreferredWhenAvailable() throws {
        let resolution = try ProxyPortResolver.resolve(
            preferred: 59200,
            address: "127.0.0.1",
            autoSelect: true
        )

        #expect(resolution.port == 59200)
        #expect(resolution.isFallback == false)
    }

    @Test("resolve falls back when preferred port is occupied and autoSelect is enabled")
    func resolveFallbackWhenOccupied() throws {
        let listener = try TCPListener(port: 0, address: "127.0.0.1")
        defer { listener.close() }

        let resolution = try ProxyPortResolver.resolve(
            preferred: listener.boundPort,
            address: "127.0.0.1",
            autoSelect: true
        )

        #expect(resolution.port != listener.boundPort)
        #expect(resolution.isFallback == true)
        #expect(resolution.port > 0)
        #expect(resolution.port <= 65535)
    }

    @Test("resolve throws portInUse when preferred is occupied and autoSelect is disabled")
    func resolveThrowsWhenNoAutoSelect() throws {
        let listener = try TCPListener(port: 0, address: "127.0.0.1")
        defer { listener.close() }

        #expect(throws: ProxyServerError.self) {
            try ProxyPortResolver.resolve(
                preferred: listener.boundPort,
                address: "127.0.0.1",
                autoSelect: false
            )
        }
    }

    // MARK: - Persistence Model

    @Test("preferred port in settings is unchanged after fallback resolution")
    func persistenceUnchangedAfterFallback() throws {
        let originalSettings = AppSettingsStorage.load()
        let originalPort = originalSettings.proxyPort
        defer {
            var restore = AppSettingsStorage.load()
            restore.proxyPort = originalPort
            AppSettingsStorage.save(restore)
        }

        var settings = AppSettings()
        settings.proxyPort = 59300
        AppSettingsStorage.save(settings)

        let listener = try TCPListener(port: 59300, address: "127.0.0.1")
        defer { listener.close() }

        let resolution = try ProxyPortResolver.resolve(
            preferred: 59300,
            address: "127.0.0.1",
            autoSelect: true
        )

        #expect(resolution.isFallback == true)

        let reloaded = AppSettingsStorage.load()
        #expect(reloaded.proxyPort == 59300)
    }
}

// MARK: - TCPListener

/// Minimal TCP listener for testing port availability.
/// Binds to a local port and keeps it occupied until `close()` is called.
private final class TCPListener {
    // MARK: Lifecycle

    init(port: Int, address: String) throws {
        let socketFd = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw TCPListenerError.socketCreationFailed
        }

        var reuse: Int32 = 1
        setsockopt(socketFd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(address)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(socketFd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(socketFd)
            throw TCPListenerError.bindFailed
        }

        guard listen(socketFd, 1) == 0 else {
            Darwin.close(socketFd)
            throw TCPListenerError.listenFailed
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(socketFd, sockPtr, &boundLen)
            }
        }

        fd = socketFd
        boundPort = Int(in_port_t(bigEndian: boundAddr.sin_port))
    }

    // MARK: Internal

    let boundPort: Int

    func close() {
        Darwin.close(fd)
    }

    // MARK: Private

    private let fd: Int32
}

// MARK: - TCPListenerError

private enum TCPListenerError: Error {
    case socketCreationFailed
    case bindFailed
    case listenFailed
}
