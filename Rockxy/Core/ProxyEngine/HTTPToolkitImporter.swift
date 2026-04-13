import Foundation
import os

// MARK: - HTTPToolkitImporter

/// Imports SSL proxy settings from HTTPToolkit's exported JSON format.
/// Supports dictionary with various host-list keys or a flat string array.
enum HTTPToolkitImporter {
    // MARK: Internal

    enum ImportError: LocalizedError {
        case invalidFormat
        case noHostsFound

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                String(localized: "The file is not a valid HTTPToolkit settings export.")
            case .noHostsFound:
                String(localized: "No usable SSL hosts found in the imported file.")
            }
        }
    }

    static func importRules(from data: Data) throws -> [SSLProxyingRule] {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }

        let rules = extractFromDictionary(dict)
        guard !rules.isEmpty else {
            throw ImportError.noHostsFound
        }
        return rules
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HTTPToolkitImporter"
    )

    private static let knownKeys: Set<String> = ["whitelistedHosts", "interceptedHosts", "hosts"]

    private static func extractFromDictionary(_ dict: [String: Any]) -> [SSLProxyingRule] {
        var allHosts: [String] = []

        for key in knownKeys {
            if let hosts = dict[key] as? [String] {
                allHosts.append(contentsOf: hosts)
            }
        }

        let rules = deduplicate(allHosts)
        logger.info("Imported \(rules.count) rules from HTTPToolkit format")
        return rules
    }

    private static func deduplicate(_ domains: [String]) -> [SSLProxyingRule] {
        var seen = Set<String>()
        var rules: [SSLProxyingRule] = []

        for domain in domains {
            let trimmed = domain.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            rules.append(SSLProxyingRule(domain: trimmed, listType: .include))
        }

        return rules
    }
}
