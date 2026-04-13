import Foundation
import os

// MARK: - ProxymanSSLImporter

/// Imports SSL proxy settings from exported JSON format.
/// Supports structured format with include/exclude keys or a flat string array.
enum ProxymanSSLImporter {
    // MARK: Internal

    enum ImportError: LocalizedError {
        case invalidFormat
        case noHostsFound

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                String(localized: "The file is not a valid SSL settings export.")
            case .noHostsFound:
                String(localized: "No usable hosts found in the imported file.")
            }
        }
    }

    static func importRules(from data: Data) throws -> [SSLProxyingRule] {
        if let structured = try? JSONDecoder().decode(StructuredExport.self, from: data),
           structured.includeDomains != nil || structured.excludeDomains != nil
        {
            let rules = buildRules(from: structured)
            guard !rules.isEmpty else {
                throw ImportError.noHostsFound
            }
            return rules
        }

        if let flat = try? JSONDecoder().decode([String].self, from: data) {
            let rules = deduplicateAsInclude(flat)
            guard !rules.isEmpty else {
                throw ImportError.noHostsFound
            }
            return rules
        }

        throw ImportError.invalidFormat
    }

    // MARK: Private

    private struct StructuredExport: Codable {
        var includeDomains: [String]?
        var excludeDomains: [String]?
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ProxymanSSLImporter"
    )

    private static func buildRules(from export: StructuredExport) -> [SSLProxyingRule] {
        var includeSeen = Set<String>()
        var excludeSeen = Set<String>()
        var rules: [SSLProxyingRule] = []

        for domain in export.includeDomains ?? [] {
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.lowercased()
            guard !includeSeen.contains(key) else {
                continue
            }
            includeSeen.insert(key)
            rules.append(SSLProxyingRule(domain: trimmed, listType: .include))
        }

        for domain in export.excludeDomains ?? [] {
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.lowercased()
            guard !excludeSeen.contains(key) else {
                continue
            }
            excludeSeen.insert(key)
            rules.append(SSLProxyingRule(domain: trimmed, listType: .exclude))
        }

        logger.info("Imported \(rules.count) rules from structured format")
        return rules
    }

    private static func deduplicateAsInclude(_ domains: [String]) -> [SSLProxyingRule] {
        var seen = Set<String>()
        var rules: [SSLProxyingRule] = []

        for domain in domains {
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
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

        logger.info("Imported \(rules.count) rules from flat array format")
        return rules
    }
}
