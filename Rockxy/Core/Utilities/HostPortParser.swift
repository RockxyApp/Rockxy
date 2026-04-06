import Foundation
import os

enum HostPortParser {
    // MARK: Internal

    struct ParsedTarget {
        let host: String
        let port: Int
    }

    enum ParseError: Error, LocalizedError {
        case emptyURI
        case emptyHost
        case invalidHostCharacters
        case malformedIPv6
        case invalidPort(String)
        case portOutOfRange(Int)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .emptyURI:
                "URI is empty"
            case .emptyHost:
                "Host is empty"
            case .invalidHostCharacters:
                "Host contains invalid characters"
            case .malformedIPv6:
                "Malformed IPv6 address (missing closing bracket)"
            case let .invalidPort(value):
                "Invalid port: \(value)"
            case let .portOutOfRange(port):
                "Port out of range: \(port)"
            }
        }
    }

    static func parse(_ uri: String, defaultPort: Int = 443) throws -> ParsedTarget {
        let trimmed = uri.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw ParseError.emptyURI
        }

        var host: String
        var portValue: Int = defaultPort

        if trimmed.hasPrefix("[") {
            guard let closingBracket = trimmed.firstIndex(of: "]") else {
                throw ParseError.malformedIPv6
            }
            host = String(trimmed[trimmed.index(after: trimmed.startIndex) ..< closingBracket])
            let afterBracket = trimmed.index(after: closingBracket)
            if afterBracket < trimmed.endIndex, trimmed[afterBracket] == ":" {
                let portString = String(trimmed[trimmed.index(after: afterBracket)...])
                guard !portString.isEmpty, portString.allSatisfy(\.isASCII), portString.allSatisfy(\.isNumber) else {
                    throw ParseError.invalidPort(portString)
                }
                guard let parsed = Int(portString) else {
                    throw ParseError.invalidPort(portString)
                }
                portValue = parsed
            }
        } else if let lastColon = trimmed.lastIndex(of: ":") {
            host = String(trimmed[trimmed.startIndex ..< lastColon])
            let portString = String(trimmed[trimmed.index(after: lastColon)...])
            guard let parsed = Int(portString) else {
                throw ParseError.invalidPort(portString)
            }
            portValue = parsed
        } else {
            host = trimmed
        }

        guard !host.isEmpty else {
            throw ParseError.emptyHost
        }
        let hasInvalidChars = host.unicodeScalars.contains { $0.value < 0x20 || $0 == " " }
        if hasInvalidChars {
            logger.error("SECURITY: Host contains invalid characters")
            throw ParseError.invalidHostCharacters
        }

        guard (1 ... 65535).contains(portValue) else {
            throw ParseError.portOutOfRange(portValue)
        }

        return ParsedTarget(host: host, port: portValue)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "HostPortParser")
}
