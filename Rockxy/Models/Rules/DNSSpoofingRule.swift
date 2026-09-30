import Foundation
import os

// Persisted DNS Spoofing rules.

// MARK: - DNSSpoofingRule

struct DNSSpoofingRule: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var isEnabled = true
    /// Host name to match: `api.example.com` or `*.example.com`.
    var host: String
    /// IP address or host name to connect to instead.
    var address: String

    var entry: DNSSpoofingEntry {
        DNSSpoofingEntry(
            hostPattern: host.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        )
    }
}

// MARK: - DNSSpoofingRuleValidator

enum DNSSpoofingRuleValidator {
    /// First problem with `rule`, or `nil` when it can be saved. With `reportsMissingFields`
    /// false, a field that is still empty is not reported, so an editor can keep Save disabled
    /// without flagging a form the user has not filled in yet.
    static func problem(
        with rule: DNSSpoofingRule,
        among rules: [DNSSpoofingRule],
        reportsMissingFields: Bool = true
    )
        -> String?
    {
        let host = rule.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let address = rule.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return reportsMissingFields
                ? String(localized: "Enter the host name to spoof.", bundle: RockxyLocalization.bundle)
                : nil
        }
        guard isBareName(host), HostPatternMatcher.isValid(pattern: host) else {
            return String(
                localized: "Enter only a host name, such as api.example.com or *.example.com, without a scheme, port, or path.",
                bundle: RockxyLocalization.bundle
            )
        }
        guard !address.isEmpty else {
            return reportsMissingFields
                ? String(localized: "Enter the address to connect to.", bundle: RockxyLocalization.bundle)
                : nil
        }
        let bareAddress = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard RemoteAccessAddressRange.addressBytes(bareAddress) != nil
            || (isBareName(bareAddress) && !bareAddress.contains("*") && !bareAddress.contains("?")) else
        {
            return String(
                localized: "Enter an IP address or a host name, without a scheme, port, or path.",
                bundle: RockxyLocalization.bundle
            )
        }
        guard bareAddress.lowercased() != host else {
            return String(localized: "The address is the same as the host.", bundle: RockxyLocalization.bundle)
        }
        guard !rules.contains(where: { $0.id != rule.id && $0.host.lowercased() == host }) else {
            return String(localized: "Another rule already spoofs this host.", bundle: RockxyLocalization.bundle)
        }
        return nil
    }

    private static func isBareName(_ value: String) -> Bool {
        !value.contains("/") && !value.contains(where: \.isWhitespace)
            && (value.contains("::") || !value.contains(":"))
    }
}

// MARK: - DNSSpoofingStore

/// Owns DNS Spoofing rules (persisted in user defaults) and keeps `DNSSpoofingTable`
/// in step, so a running proxy uses a change on its next upstream connection.
@MainActor @Observable
final class DNSSpoofingStore {
    // MARK: Lifecycle

    init(
        defaults: UserDefaults = .standard,
        table: DNSSpoofingTable = .shared,
        maxRules: @escaping @MainActor () -> Int = { ToolCapacityGate.shared.maxDNSSpoofingRules }
    ) {
        self.defaults = defaults
        self.table = table
        self.maxRules = maxRules
        load()
        publish()
    }

    // MARK: Internal

    static let shared = DNSSpoofingStore()

    private(set) var rules: [DNSSpoofingRule] = []

    var enabledCount: Int {
        rules.count(where: \.isEnabled)
    }

    /// Whether another rule may be added; editing an existing rule is always allowed.
    var canAddRule: Bool {
        rules.count < maxRules()
    }

    var ruleLimit: Int {
        maxRules()
    }

    /// Saves the rule. A new rule is refused (returns false) once the policy's limit is reached.
    @discardableResult
    func upsert(_ rule: DNSSpoofingRule) -> Bool {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            guard canAddRule else {
                return false
            }
            rules.append(rule)
        }
        persist()
        return true
    }

    func setEnabled(_ isEnabled: Bool, id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        rules[index].isEnabled = isEnabled
        persist()
    }

    func remove(ids: Set<UUID>) {
        rules.removeAll { ids.contains($0.id) }
        persist()
    }

    /// Replaces every rule, as a settings import does.
    func replaceAll(_ newRules: [DNSSpoofingRule]) {
        rules = newRules
        persist()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "DNSSpoofingStore")
    private static let storageKey = RockxyIdentity.current.defaultsKey("dnsSpoofingRules")

    private let defaults: UserDefaults
    private let table: DNSSpoofingTable
    private let maxRules: @MainActor () -> Int

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return
        }
        do {
            rules = try JSONDecoder().decode([DNSSpoofingRule].self, from: data)
        } catch {
            Self.logger.error("Failed to decode DNS spoofing rules: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            try defaults.set(JSONEncoder().encode(rules), forKey: Self.storageKey)
        } catch {
            Self.logger.error("Failed to save DNS spoofing rules: \(error.localizedDescription)")
        }
        publish()
    }

    private func publish() {
        table.update(rules.filter(\.isEnabled).map(\.entry))
    }
}
