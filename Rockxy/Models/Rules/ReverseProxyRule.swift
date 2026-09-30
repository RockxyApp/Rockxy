import Foundation
import Network
import os

// Persisted reverse proxy rules and their live listener status.

// MARK: - ReverseProxyRule

struct ReverseProxyRule: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var isEnabled = true
    var localPort: Int
    var remoteScheme: ReverseProxyTarget.Scheme = .https
    var remoteHost: String
    var remotePort: Int
    var preserveHostHeader = false

    var target: ReverseProxyTarget {
        ReverseProxyTarget(
            id: id,
            localPort: localPort,
            scheme: remoteScheme,
            host: remoteHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: remotePort,
            preserveHostHeader: preserveHostHeader
        )
    }

    /// The URL a client uses instead of the real server.
    var localURLString: String {
        "http://127.0.0.1:\(localPort)"
    }

    var remoteURLString: String {
        "\(remoteScheme.rawValue)://\(target.authority)"
    }
}

// MARK: - ReverseProxyRuleStatus

enum ReverseProxyRuleStatus: Equatable {
    case disabled
    case proxyStopped
    case listening
    case portInUse
    case failed(String)

    // MARK: Internal

    var title: String {
        switch self {
        case .disabled: String(localized: "Off", bundle: RockxyLocalization.bundle)
        case .proxyStopped: String(localized: "Starts with the proxy", bundle: RockxyLocalization.bundle)
        case .listening: String(localized: "Listening", bundle: RockxyLocalization.bundle)
        case .portInUse: String(localized: "Port in use", bundle: RockxyLocalization.bundle)
        case let .failed(message): message
        }
    }
}

// MARK: - ReverseProxyRuleValidator

enum ReverseProxyRuleValidator {
    static let localPortRange = 1_024 ... 65_535

    /// First problem with `rule`, or `nil` when it can be saved. With `reportsMissingFields`
    /// false, an empty remote host is not reported, so an editor can keep Save disabled
    /// without flagging a form the user has not filled in yet.
    static func problem(
        with rule: ReverseProxyRule,
        among rules: [ReverseProxyRule],
        proxyPort: Int,
        reportsMissingFields: Bool = true
    )
        -> String?
    {
        let host = rule.remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard localPortRange.contains(rule.localPort) else {
            return String(localized: "Choose a local port from 1024 to 65535.", bundle: RockxyLocalization.bundle)
        }
        guard rule.localPort != proxyPort else {
            return String(
                localized: "The local port is Rockxy's proxy port. Choose another port.",
                bundle: RockxyLocalization.bundle
            )
        }
        guard !rules.contains(where: { $0.id != rule.id && $0.localPort == rule.localPort }) else {
            return String(
                localized: "Another reverse proxy already uses this local port.",
                bundle: RockxyLocalization.bundle
            )
        }
        guard !host.isEmpty else {
            return reportsMissingFields
                ? String(localized: "Enter the remote host.", bundle: RockxyLocalization.bundle)
                : nil
        }
        guard !host.contains("/"), !host.contains("://"), !host.contains(where: \.isWhitespace) else {
            return String(
                localized: "Enter only the host name, without a scheme or path.",
                bundle: RockxyLocalization.bundle
            )
        }
        // A colon is only valid inside an IPv6 literal (`::1`, `[2001:db8::1]`).
        if host.contains(":"), IPv6Address(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))) == nil {
            return String(
                localized: "Enter the port in the Remote Port field, not in the host.",
                bundle: RockxyLocalization.bundle
            )
        }
        guard (1 ... 65_535).contains(rule.remotePort) else {
            return String(localized: "Choose a remote port from 1 to 65535.", bundle: RockxyLocalization.bundle)
        }
        if isLoopback(host), rule.remotePort == rule.localPort || rule.remotePort == proxyPort {
            return String(
                localized: "This rule would forward to itself. Point it at the real server.",
                bundle: RockxyLocalization.bundle
            )
        }
        return nil
    }

    static func isLoopback(_ host: String) -> Bool {
        let lowered = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return lowered == "localhost" || lowered == "::1" || lowered.hasPrefix("127.")
    }
}

// MARK: - ReverseProxyStore

/// Owns reverse proxy rules (persisted in user defaults) and the live status the
/// proxy reports for each listener. Rule changes post
/// `reverseProxyRulesDidChange` so a running proxy can reconcile its listeners.
@MainActor @Observable
final class ReverseProxyStore {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: Internal

    static let shared = ReverseProxyStore()

    private(set) var rules: [ReverseProxyRule] = []
    private(set) var statuses: [UUID: ReverseProxyRuleStatus] = [:]

    var enabledTargets: [ReverseProxyTarget] {
        rules.filter(\.isEnabled).map(\.target)
    }

    func status(for rule: ReverseProxyRule) -> ReverseProxyRuleStatus {
        guard rule.isEnabled else {
            return .disabled
        }
        return statuses[rule.id] ?? .proxyStopped
    }

    func upsert(_ rule: ReverseProxyRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persistAndNotify()
    }

    func setEnabled(_ isEnabled: Bool, id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        rules[index].isEnabled = isEnabled
        persistAndNotify()
    }

    func remove(ids: Set<UUID>) {
        rules.removeAll { ids.contains($0.id) }
        for id in ids {
            statuses.removeValue(forKey: id)
        }
        persistAndNotify()
    }

    /// Replaces every rule, as a settings import does.
    func replaceAll(_ newRules: [ReverseProxyRule]) {
        let kept = Set(newRules.map(\.id))
        statuses = statuses.filter { kept.contains($0.key) }
        rules = newRules
        persistAndNotify()
    }

    /// Records the outcome of reconciling listeners with the running proxy.
    func applyListenerResult(targets: [ReverseProxyTarget], failures: [UUID: ReverseProxyBindFailure]) {
        var next: [UUID: ReverseProxyRuleStatus] = [:]
        for target in targets {
            switch failures[target.id] {
            case nil:
                next[target.id] = .listening
            case .proxyNotRunning:
                next[target.id] = .proxyStopped
            case .portInUse:
                next[target.id] = .portInUse
            case let .bindFailed(message):
                next[target.id] = .failed(message)
            }
        }
        statuses = next
    }

    func markProxyStopped() {
        statuses = [:]
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ReverseProxyStore")
    private static let storageKey = RockxyIdentity.current.defaultsKey("reverseProxyRules")

    private let defaults: UserDefaults

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return
        }
        do {
            rules = try JSONDecoder().decode([ReverseProxyRule].self, from: data)
        } catch {
            Self.logger.error("Failed to decode reverse proxy rules: \(error.localizedDescription)")
        }
    }

    private func persistAndNotify() {
        do {
            try defaults.set(JSONEncoder().encode(rules), forKey: Self.storageKey)
        } catch {
            Self.logger.error("Failed to save reverse proxy rules: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: .reverseProxyRulesDidChange, object: nil)
    }
}
