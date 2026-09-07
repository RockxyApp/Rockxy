import Foundation

enum ProxyBypassDomainValidator {
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
