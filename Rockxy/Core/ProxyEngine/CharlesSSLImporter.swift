import Foundation
import os

// MARK: - CharlesSSLImporter

/// Imports SSL proxy settings from Charles Proxy's exported XML plist format.
enum CharlesSSLImporter {
    // MARK: Internal

    enum ImportError: LocalizedError {
        case invalidFormat
        case noLocationsFound

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                String(localized: "The file is not a valid Charles Proxy SSL settings export.")
            case .noLocationsFound:
                String(localized: "No SSL proxy locations found in the file.")
            }
        }
    }

    static func importRules(from data: Data) throws -> [SSLProxyingRule] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any] else
        {
            throw ImportError.invalidFormat
        }

        guard let locations = root["location"] as? [[String: Any]], !locations.isEmpty else {
            throw ImportError.noLocationsFound
        }

        var seen = Set<String>()
        var rules: [SSLProxyingRule] = []

        for location in locations {
            guard let host = location["host"] as? String else {
                continue
            }
            let trimmed = host.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                continue
            }
            let domain = trimmed
            let key = domain.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            rules.append(SSLProxyingRule(domain: domain, listType: .include))
        }

        guard !rules.isEmpty else {
            throw ImportError.noLocationsFound
        }

        logger.info("Imported \(rules.count) rules from Charles Proxy format")
        return rules
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "CharlesSSLImporter"
    )
}
