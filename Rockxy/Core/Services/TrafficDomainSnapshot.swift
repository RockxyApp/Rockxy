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

    /// Publishes the snapshot from an already-ordered domain list.
    ///
    /// The capture path uses this because `DomainGroupingIndex` maintains that order as
    /// nodes appear and leave. Deriving it here instead meant flattening the whole tree,
    /// deduplicating it, and re-collating every observed domain on each delivery batch --
    /// over a collection sized by the distinct hosts seen in the session, which the
    /// transaction cap does not bound, so evicting rows never made it cheaper.
    func update(appNodes: [AppInfo], domains: [String]) {
        appEntries = Self.mergeNameOnlyEntries(appNodes).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        self.domains = domains
    }

    /// Derives the domain list from a published tree, for the one-shot paths (import,
    /// Project activation, nearby transfer) that are not on the capture batch path.
    func update(appNodes: [AppInfo], domainTree: [DomainNode]) {
        var seen = Set<String>()
        update(
            appNodes: appNodes,
            domains: domainTree.flatMap(Self.flattenDomains)
                .filter { seen.insert($0).inserted }
                .sorted { DomainGrouping.isOrderedBefore(domain: $0, $1) }
        )
    }

    func reset() {
        appEntries = []
        domains = []
    }

    // MARK: Private

    private static func flattenDomains(from node: DomainNode) -> [String] {
        let ownValue = node.kind == .path ? [] : [node.selectionDomain]
        return ownValue + node.children.flatMap(flattenDomains)
    }

    /// Folds anonymous, name-only app buckets into the stable-identity bucket that shares their
    /// display name — but only when that name resolves to exactly one distinct identity. When two
    /// different identities share a display name the anonymous traffic cannot be attributed, so the
    /// name-only bucket is preserved untouched (fail closed; no guessed attribution).
    private static func mergeNameOnlyEntries(_ appNodes: [AppInfo]) -> [AppInfo] {
        var identifiersByName: [String: Set<String>] = [:]
        for entry in appNodes {
            guard let identifier = entry.identity?.identifier else {
                continue
            }
            identifiersByName[normalizedName(entry.name), default: []].insert(identifier)
        }

        var result: [AppInfo] = []
        var indexByIdentifier: [String: Int] = [:]
        var pendingMerges: [(identifier: String, entry: AppInfo)] = []

        for entry in appNodes {
            if let identifier = entry.identity?.identifier {
                indexByIdentifier[identifier] = result.count
                result.append(entry)
                continue
            }
            let key = normalizedName(entry.name)
            if let identifiers = identifiersByName[key],
               identifiers.count == 1,
               let identifier = identifiers.first
            {
                pendingMerges.append((identifier, entry))
            } else {
                result.append(entry)
            }
        }

        for pending in pendingMerges {
            guard let index = indexByIdentifier[pending.identifier] else {
                result.append(pending.entry)
                continue
            }
            result[index] = merge(result[index], absorbing: pending.entry)
        }
        return result
    }

    private static func merge(_ base: AppInfo, absorbing other: AppInfo) -> AppInfo {
        var seen = Set<String>()
        var combinedDomains: [String] = []
        for domain in base.domains + other.domains where seen.insert(domain.lowercased()).inserted {
            combinedDomains.append(domain)
        }
        combinedDomains.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return AppInfo(
            name: base.name,
            domains: combinedDomains,
            requestCount: base.requestCount + other.requestCount,
            identity: base.identity
        )
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
