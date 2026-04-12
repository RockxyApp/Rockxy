import Foundation

// MARK: - TrafficDomainSnapshot

/// Lightweight read-only snapshot of observed apps and domains from live traffic.
/// Updated by `MainContentCoordinator` on each batch; read by secondary windows
/// (like the SSL Proxying List) that need traffic context without a coordinator reference.
@MainActor @Observable
final class TrafficDomainSnapshot {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = TrafficDomainSnapshot()

    /// Apps observed in captured traffic, each carrying its list of contacted domains.
    private(set) var appEntries: [AppInfo] = []

    /// All unique domains observed across all traffic, sorted alphabetically.
    private(set) var domains: [String] = []

    /// Look up observed domains for a given app name.
    func domains(forApp name: String) -> [String] {
        appEntries.first { $0.name == name }?.domains ?? []
    }

    func update(appNodes: [AppInfo], domainTree: [DomainNode]) {
        appEntries = appNodes.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var seen = Set<String>()
        domains = domainTree.map(\.domain)
            .filter { seen.insert($0).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func reset() {
        appEntries = []
        domains = []
    }
}
