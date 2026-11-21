import Foundation

enum ProxyBypassDomainValidator {
    /// The largest total one bypass list may occupy, counting the newline `networksetup` prints
    /// after each domain.
    ///
    /// The helper's 500-domain cap does not bound the reply: 500 entries at the 253-byte maximum
    /// below is roughly 127 KB, which is past the 64 KiB pipe buffer that
    /// `networksetup -getproxybypassdomains` would block on and past what any caller should ask a
    /// command runner to buffer. Bounding the total instead keeps every supported list inside
    /// `BoundedHelperCommand.standardOutputLimit`, so the supported API cannot by itself produce a
    /// reading the command layer refuses. 64 KiB is the pipe buffer, and it still allows all 500
    /// domains averaging 130 bytes — an order of magnitude above the hostnames and CIDR blocks a
    /// real bypass list holds.
    static let maximumTotalBytes = 65_536

    static func isValid(_ domain: String) -> Bool {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == domain, trimmed.count <= 253 else {
            return false
        }
        guard trimmed != "*" else {
            return false
        }

        guard trimmed.unicodeScalars.allSatisfy({ scalar in
            scalar.isASCII && allowedScalars.contains(scalar)
        }) else {
            return false
        }

        return !trimmed.contains("/") || ipv4CIDR(trimmed) != nil
    }

    /// Whether `domains` fits `maximumTotalBytes` once `networksetup`'s per-line newline is
    /// counted. Checked alongside the count cap, not instead of it.
    static func fitsTotalByteBound(_ domains: [String]) -> Bool {
        domains.reduce(0) { $0 + $1.utf8.count + 1 } <= maximumTotalBytes
    }

    static func ipv4CIDR(_ value: String) -> (network: UInt32, mask: UInt32)? {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              let address = ipv4Address(String(components[0])),
              let prefix = Int(components[1]),
              (1 ... 32).contains(prefix)
        else {
            return nil
        }

        let mask = UInt32.max << UInt32(32 - prefix)
        return (address & mask, mask)
    }

    static func ipv4Address(_ value: String) -> UInt32? {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return nil
        }

        var address: UInt32 = 0
        for octet in octets {
            guard !octet.isEmpty,
                  octet.allSatisfy(\.isNumber),
                  let value = UInt32(octet),
                  value <= 255
            else {
                return nil
            }
            address = (address << 8) | value
        }
        return address
    }

    private static let allowedScalars = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_*:[]/"
    )
}
