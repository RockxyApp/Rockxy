import Foundation

// Custom name resolution for upstream connections.

// MARK: - DNSSpoofingEntry

/// Sends connections for hosts matching `hostPattern` to `address` (an IP or another
/// host name). Exact names and `*.example.com` style wildcards are supported.
struct DNSSpoofingEntry: Equatable, Sendable {
    let hostPattern: String
    let address: String
}

// MARK: - DNSSpoofingTable

/// Thread-safe snapshot the proxy consults before every upstream connection. Only the
/// connect address changes: the request URL, the Host header, TLS server name, and
/// certificate checks keep the original host, which is what separates this from
/// Map Remote.
final class DNSSpoofingTable: @unchecked Sendable {
    // MARK: Internal

    static let shared = DNSSpoofingTable()

    func update(_ entries: [DNSSpoofingEntry]) {
        lock.withLock { self.entries = entries }
    }

    /// The address to connect to for `host`, or `nil` when no entry matches. The first
    /// matching entry wins.
    func address(for host: String) -> String? {
        let entries = lock.withLock { self.entries }
        guard !entries.isEmpty else {
            return nil
        }
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return entries.first { HostPatternMatcher.matches(host: normalized, pattern: $0.hostPattern) }?.address
    }

    // MARK: Private

    private let lock = NSLock()
    private var entries: [DNSSpoofingEntry] = []
}

// MARK: - UpstreamConnectHost

/// The host an upstream connection actually dials: a DNS Spoofing address when one
/// matches, otherwise the emulator loopback alias, otherwise the request's own host.
enum UpstreamConnectHost {
    static func resolve(
        for host: String,
        clientHost: String?,
        table: DNSSpoofingTable = .shared
    )
        -> String
    {
        if let spoofed = table.address(for: host) {
            return spoofed
        }
        return EmulatorHostAlias.connectHost(for: host, clientHost: clientHost)
    }
}
