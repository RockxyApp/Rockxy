import Darwin
import Foundation

// MARK: - RemoteAccessMode

/// Which remote devices may use the proxy when it listens on every interface.
/// Connections from this Mac are always accepted.
enum RemoteAccessMode: String, CaseIterable, Sendable {
    case allowAll
    case disallowAll
    case listedDevices
}

// MARK: - RemoteAccessAddressRange

/// One allowed address or CIDR range, such as `192.168.1.20`, `10.0.0.0/8`, or `fe80::/10`.
struct RemoteAccessAddressRange: Equatable, Sendable {
    // MARK: Lifecycle

    /// Returns `nil` when `entry` is not an IPv4/IPv6 address or a valid CIDR range.
    init?(_ entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let bytes = Self.addressBytes(String(first)) else {
            return nil
        }
        let maxBits = bytes.count * 8
        var prefix = maxBits
        if parts.count == 2 {
            guard let value = Int(parts[1]), (0 ... maxBits).contains(value) else {
                return nil
            }
            prefix = value
        }
        self.bytes = bytes
        self.prefixLength = prefix
    }

    // MARK: Internal

    let bytes: [UInt8]
    let prefixLength: Int

    /// Parses an IPv4 or IPv6 literal. IPv4-mapped IPv6 addresses (`::ffff:a.b.c.d`)
    /// are returned as IPv4 so a client reported either way matches an IPv4 entry.
    static func addressBytes(_ text: String) -> [UInt8]? {
        let literal = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        let withoutZone = literal.split(separator: "%", maxSplits: 1).first.map(String.init) ?? literal
        var v4 = in_addr()
        if inet_pton(AF_INET, withoutZone, &v4) == 1 {
            return withUnsafeBytes(of: &v4) { Array($0) }
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, withoutZone, &v6) == 1 else {
            return nil
        }
        let raw = withUnsafeBytes(of: &v6) { Array($0) }
        if raw[0 ..< 10].allSatisfy({ $0 == 0 }), raw[10] == 0xFF, raw[11] == 0xFF {
            return Array(raw[12 ..< 16])
        }
        return raw
    }

    func contains(_ address: [UInt8]) -> Bool {
        guard address.count == bytes.count else {
            return false
        }
        var remaining = prefixLength
        for index in bytes.indices where remaining > 0 {
            let bits = min(8, remaining)
            let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - bits))
            if address[index] & mask != bytes[index] & mask {
                return false
            }
            remaining -= bits
        }
        return true
    }
}

// MARK: - RemoteAccessGate

/// Thread-safe accept check consulted by every listener before it builds a connection's
/// pipeline. Loopback and this Mac's own addresses always pass; other clients pass
/// according to the mode. Devices refused while the mode is `listedDevices` are
/// reported once each so the app can offer to allow them.
final class RemoteAccessGate: @unchecked Sendable {
    // MARK: Internal

    enum Decision: Equatable {
        case allow
        case deny
    }

    static let shared = RemoteAccessGate()

    /// Called off the main thread, at most once per refused address until the policy changes.
    var onListedDeviceRefused: (@Sendable (String) -> Void)? {
        get {
            lock.withLock { refusedHandler }
        }
        set {
            lock.withLock { refusedHandler = newValue }
        }
    }

    func update(mode: RemoteAccessMode, allowedEntries: [String]) {
        let ranges = allowedEntries.compactMap(RemoteAccessAddressRange.init)
        lock.withLock {
            self.mode = mode
            self.ranges = ranges
            reportedAddresses.removeAll()
        }
    }

    /// - Parameters:
    ///   - clientAddress: The connection's remote IP.
    ///   - localAddress: The IP the connection reached; a client using the same IP is this Mac.
    func decision(clientAddress: String?, localAddress: String?) -> Decision {
        let (mode, ranges) = lock.withLock { (self.mode, self.ranges) }
        if mode == .allowAll {
            return .allow
        }
        guard let clientAddress, let clientBytes = RemoteAccessAddressRange.addressBytes(clientAddress) else {
            return .deny
        }
        if Self.isThisMac(clientBytes, localAddress: localAddress) {
            return .allow
        }
        if mode == .listedDevices, ranges.contains(where: { $0.contains(clientBytes) }) {
            return .allow
        }
        if mode == .listedDevices {
            reportRefused(clientAddress)
        }
        return .deny
    }

    // MARK: Private

    private let lock = NSLock()
    private var mode: RemoteAccessMode = .allowAll
    private var ranges: [RemoteAccessAddressRange] = []
    private var reportedAddresses: Set<String> = []
    private var refusedHandler: (@Sendable (String) -> Void)?

    private static func isThisMac(_ client: [UInt8], localAddress: String?) -> Bool {
        if client.count == 4, client[0] == 127 {
            return true
        }
        if client.count == 16, client == Array(repeating: 0, count: 15) + [1] {
            return true
        }
        if let localAddress, RemoteAccessAddressRange.addressBytes(localAddress) == client {
            return true
        }
        return interfaceAddresses().contains(client)
    }

    private static func interfaceAddresses() -> Set<[UInt8]> {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            return []
        }
        defer { freeifaddrs(head) }
        var result: Set<[UInt8]> = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            if let address = entry.pointee.ifa_addr {
                switch Int32(address.pointee.sa_family) {
                case AF_INET:
                    address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        var value = $0.pointee.sin_addr
                        result.insert(withUnsafeBytes(of: &value) { Array($0) })
                    }
                case AF_INET6:
                    address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        var value = $0.pointee.sin6_addr
                        result.insert(withUnsafeBytes(of: &value) { Array($0) })
                    }
                default:
                    break
                }
            }
            cursor = entry.pointee.ifa_next
        }
        return result
    }

    private func reportRefused(_ address: String) {
        let handler: (@Sendable (String) -> Void)? = lock.withLock {
            guard reportedAddresses.insert(address).inserted else {
                return nil
            }
            return refusedHandler
        }
        handler?(address)
    }
}

// MARK: - RemoteAccessRefusedError

/// Fails a listener's connection setup for a device Access Control does not allow.
struct RemoteAccessRefusedError: Error {}
