import Darwin
import Foundation

// MARK: - TLSServerName

/// The name to send as TLS SNI for an upstream host. IP literals are not valid SNI values and
/// NIOSSL refuses them, so HTTPS to an address such as `192.168.1.10` or `10.0.2.2` connects
/// without SNI instead of failing before the handshake starts.
enum TLSServerName {
    static func sni(for host: String) -> String? {
        ipAddressBytes(host) == nil ? host : nil
    }

    /// The network-order bytes of an IPv4 or IPv6 literal (brackets allowed), or nil for names.
    static func ipAddressBytes(_ host: String) -> [UInt8]? {
        let bare = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        var ipv4 = in_addr()
        if inet_pton(AF_INET, bare, &ipv4) == 1 {
            return withUnsafeBytes(of: &ipv4) { Array($0) }
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, bare, &ipv6) == 1 {
            return withUnsafeBytes(of: &ipv6) { Array($0) }
        }
        return nil
    }
}
