import Foundation
import os

/// Resolves the actual port the proxy should bind to, handling automatic fallback
/// when the user's preferred port is occupied by another process.
///
/// Resolution is session-only — the fallback port is never persisted back to settings.
/// On the next launch or proxy restart, Rockxy retries the preferred port first.
enum ProxyPortResolver {
    // MARK: Internal

    /// The outcome of port resolution.
    struct Resolution {
        /// The port the proxy server should bind to.
        let port: Int
        /// `true` when the resolved port differs from the user's preferred port.
        let isFallback: Bool
    }

    /// Resolves an available port starting from the user's preferred port.
    ///
    /// - Parameters:
    ///   - preferred: The user's configured port from settings.
    ///   - address: The listen address (e.g. `"127.0.0.1"` or `"0.0.0.0"`).
    ///   - autoSelect: When `true`, scans for the next available port if `preferred` is occupied.
    ///   - listenIPv6: Accepted for API completeness; current implementation checks IPv4 only,
    ///     matching the proxy server's bind behavior.
    /// - Returns: A ``Resolution`` containing the port to use and whether fallback occurred.
    /// - Throws: ``ProxyServerError/portInUse(_:)`` if the preferred port is occupied
    ///   and `autoSelect` is `false`, or if no available port can be found.
    static func resolve(
        preferred: Int,
        address: String,
        autoSelect: Bool,
        listenIPv6: Bool = false
    )
        throws -> Resolution
    {
        if isPortAvailable(port: preferred, address: address) {
            return Resolution(port: preferred, isFallback: false)
        }

        guard autoSelect else {
            throw ProxyServerError.portInUse(preferred)
        }

        logger.info("Preferred port \(preferred) is occupied, scanning for available port")

        let nearbyEnd = min(preferred + 100, 65_535)
        for candidate in (preferred + 1) ... nearbyEnd where isPortAvailable(port: candidate, address: address) {
            return Resolution(port: candidate, isFallback: true)
        }

        for candidate in 49_152 ... 65_535 where isPortAvailable(port: candidate, address: address) {
            return Resolution(port: candidate, isFallback: true)
        }

        throw ProxyServerError.portInUse(preferred)
    }

    /// Tests whether a given port is available for binding.
    ///
    /// Uses a connect-probe: if a TCP connection to `address:port` succeeds, the port
    /// is already occupied. If it fails, the port is available.
    static func isPortAvailable(port: Int, address: String) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return true
        }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(address == "0.0.0.0" ? "127.0.0.1" : address)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result != 0
    }

    // MARK: Private

    private static let logger = Logger(subsystem: "com.amunx.Rockxy", category: "ProxyPortResolver")
}
