import Foundation

// Builds the sidebar domain hierarchy from captured traffic.

// MARK: - DomainNode

/// Represents a group in the sidebar domain source list.
/// Domain and host nodes aggregate related hosts; path nodes aggregate request paths
/// without hiding the underlying requests from the main traffic table.
struct DomainNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case domain
        case host
        case path
    }

    let id: String
    let domain: String
    var requestCount: Int
    var children: [DomainNode]
    var kind: Kind = .domain
    var filterDomain: String?
    var pathPrefix: String?
    var errorCount: Int = 0
    var methods: Set<String> = []
    var firstSeenSequence = Int.max

    var selectionDomain: String {
        filterDomain ?? domain
    }

    static func == (lhs: DomainNode, rhs: DomainNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - DomainGroupingIndex

struct DomainGroupingIndex {
    // MARK: Internal

    private(set) var supportsIncrementalRemoval = true

    func contains(_ transaction: HTTPTransaction) -> Bool {
        contributions[ObjectIdentifier(transaction)] != nil
    }

    mutating func removeAll() {
        nodesByID.removeAll(keepingCapacity: true)
        childIDsByParentID.removeAll(keepingCapacity: true)
        rootIDs.removeAll(keepingCapacity: true)
        parentIDs.removeAll(keepingCapacity: true)
        methodCounts.removeAll(keepingCapacity: true)
        sequenceCounts.removeAll(keepingCapacity: true)
        contributions.removeAll(keepingCapacity: true)
        supportsIncrementalRemoval = true
    }

    mutating func add(_ transaction: HTTPTransaction) {
        let objectID = ObjectIdentifier(transaction)
        if contributions[objectID] != nil {
            supportsIncrementalRemoval = false
        }
        let specs = DomainGrouping.nodeSpecs(for: transaction)
        let method = transaction.request.method
        let sequence = transaction.sequenceNumber
        let isError = DomainGrouping.isError(transaction)
        var nodeIDs: [String] = []
        for spec in specs {
            var node = nodesByID[spec.id] ?? DomainNode(
                id: spec.id, domain: spec.title, requestCount: 0, children: [],
                kind: spec.kind, filterDomain: spec.filterDomain,
                pathPrefix: spec.pathPrefix, firstSeenSequence: sequence
            )
            node.requestCount += 1
            if isError {
                node.errorCount += 1
            }
            node.methods.insert(method)
            node.firstSeenSequence = min(node.firstSeenSequence, sequence)
            nodesByID[spec.id] = node
            methodCounts[spec.id, default: [:]][method, default: 0] += 1
            sequenceCounts[spec.id, default: [:]][sequence, default: 0] += 1
            nodeIDs.append(node.id)
            if let parent = spec.parentID {
                parentIDs[spec.id] = parent
                childIDsByParentID[parent, default: []].insert(spec.id)
            } else {
                rootIDs.insert(spec.id)
            }
        }
        if contributions[objectID] == nil {
            contributions[objectID] = Contribution(
                url: transaction.request.url, nodeIDs: nodeIDs, method: method,
                sequence: sequence, isError: isError
            )
        }
    }

    @discardableResult
    mutating func remove(_ transactions: [HTTPTransaction]) -> Bool {
        guard supportsIncrementalRemoval else {
            return false
        }
        var dirtyOrdering: Set<String> = []
        var changed = false
        for transaction in transactions {
            guard let contribution = contributions.removeValue(forKey: ObjectIdentifier(transaction)) else {
                continue
            }
            subtract(contribution, dirtyOrdering: &dirtyOrdering)
            changed = true
        }
        reconcileOrdering(dirtyOrdering)
        return changed
    }

    @discardableResult
    mutating func update(_ transactions: [HTTPTransaction]) -> Bool {
        guard supportsIncrementalRemoval else {
            return false
        }
        var dirtyOrdering: Set<String> = []
        var changed = false
        for transaction in transactions {
            let id = ObjectIdentifier(transaction)
            guard var old = contributions[id] else {
                add(transaction)
                changed = true
                continue
            }
            let isError = DomainGrouping.isError(transaction)
            if old.url == transaction.request.url, old.method == transaction.request.method,
               old.sequence == transaction.sequenceNumber
            {
                if old.isError != isError {
                    let delta = isError ? 1 : -1
                    for nodeID in old.nodeIDs {
                        nodesByID[nodeID]?.errorCount += delta
                    }
                    old.isError = isError
                    contributions[id] = old
                    changed = true
                }
                continue
            }
            contributions.removeValue(forKey: id)
            subtract(old, dirtyOrdering: &dirtyOrdering)
            add(transaction)
            changed = true
        }
        reconcileOrdering(dirtyOrdering)
        return changed
    }

    func makeTree(alphabetical: Bool = false) -> [DomainNode] {
        sorted(ids: rootIDs, alphabetical: alphabetical).map { makeNode(id: $0, alphabetical: alphabetical) }
    }

    // MARK: Private

    private struct Contribution {
        let url: URL
        let nodeIDs: [String]
        let method: String
        let sequence: Int
        var isError: Bool
    }

    private var nodesByID: [String: DomainNode] = [:]
    private var childIDsByParentID: [String: Set<String>] = [:]
    private var rootIDs: Set<String> = []
    private var parentIDs: [String: String] = [:]
    private var methodCounts: [String: [String: Int]] = [:]
    private var sequenceCounts: [String: [Int: Int]] = [:]
    private var contributions: [ObjectIdentifier: Contribution] = [:]

    private mutating func subtract(_ contribution: Contribution, dirtyOrdering: inout Set<String>) {
        for id in contribution.nodeIDs {
            guard var node = nodesByID[id] else {
                continue
            }
            node.requestCount -= 1
            if contribution.isError {
                node.errorCount -= 1
            }
            let methods = methodCounts[id]?[contribution.method] ?? 0
            if methods <= 1 {
                methodCounts[id]?.removeValue(forKey: contribution.method)
                node.methods.remove(contribution.method)
            } else {
                methodCounts[id]?[contribution.method] = methods - 1
            }
            let sequences = sequenceCounts[id]?[contribution.sequence] ?? 0
            if sequences <= 1 {
                sequenceCounts[id]?.removeValue(forKey: contribution.sequence)
                if node.firstSeenSequence == contribution.sequence {
                    dirtyOrdering.insert(id)
                }
            } else {
                sequenceCounts[id]?[contribution.sequence] = sequences - 1
            }
            if node.requestCount == 0 {
                nodesByID.removeValue(forKey: id)
                methodCounts.removeValue(forKey: id)
                sequenceCounts.removeValue(forKey: id)
                if let parent = parentIDs.removeValue(forKey: id) {
                    childIDsByParentID[parent]?.remove(id)
                    if childIDsByParentID[parent]?.isEmpty == true {
                        childIDsByParentID.removeValue(forKey: parent)
                    }
                } else {
                    rootIDs.remove(id)
                }
                childIDsByParentID.removeValue(forKey: id)
            } else {
                nodesByID[id] = node
            }
        }
    }

    private mutating func reconcileOrdering(_ nodeIDs: Set<String>) {
        for id in nodeIDs where nodesByID[id] != nil {
            nodesByID[id]?.firstSeenSequence = sequenceCounts[id]?.keys.min() ?? .max
        }
    }

    private func makeNode(id: String, alphabetical: Bool) -> DomainNode {
        guard var node = nodesByID[id] else {
            return DomainNode(id: id, domain: id, requestCount: 0, children: [])
        }

        let childIDs = childIDsByParentID[id] ?? []
        node.children = sorted(ids: childIDs, alphabetical: alphabetical).map {
            makeNode(id: $0, alphabetical: alphabetical)
        }
        return node
    }

    private func sorted(ids: Set<String>, alphabetical: Bool) -> [String] {
        ids.sorted { lhsID, rhsID in
            guard let lhs = nodesByID[lhsID], let rhs = nodesByID[rhsID] else {
                return lhsID < rhsID
            }
            if alphabetical {
                return lhs.domain.localizedCaseInsensitiveCompare(rhs.domain) == .orderedAscending
            }
            if lhs.firstSeenSequence != rhs.firstSeenSequence {
                return lhs.firstSeenSequence < rhs.firstSeenSequence
            }
            return lhs.domain.localizedCaseInsensitiveCompare(rhs.domain) == .orderedAscending
        }
    }
}

// MARK: - AppGroupingIndex

/// Incremental application/domain counts for the Focus Navigator.
///
/// Process attribution arrives after the transaction batch in many captures. Keeping
/// reference counts lets Rockxy move those rows out of "Unknown" without rebuilding every
/// workspace index from the complete live history on each 100 ms capture batch.
///
/// Groups are keyed by the displayed client name — the same value the Client column shows
/// and the sidebar app filter matches on — so a sidebar count always equals the rows that
/// selecting the app reveals. Process identity resolves asynchronously per connection, so
/// keying by identity split one application into a name-only group and an identity group
/// with the same title. The first resolved identity is retained for icons and rule pickers.
struct AppGroupingIndex {
    // MARK: Internal

    private(set) var supportsIncrementalRemoval = true

    var recordedTransactionCount: Int {
        memberships.count
    }

    func contains(_ transaction: HTTPTransaction) -> Bool {
        memberships[ObjectIdentifier(transaction)] != nil
    }

    func recordedHost(for transaction: HTTPTransaction) -> String? {
        memberships[ObjectIdentifier(transaction)]?.host
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
        memberships.removeAll(keepingCapacity: true)
        supportsIncrementalRemoval = true
    }

    mutating func add(_ transaction: HTTPTransaction, appName: String? = nil) {
        let name = Self.normalizedAppName(appName ?? transaction.clientApp)
        let host = transaction.request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = ObjectIdentifier(transaction)
        if memberships[id] != nil {
            supportsIncrementalRemoval = false
        }
        let key = Self.key(for: name)
        if entries[key] == nil {
            entries[key] = Entry(name: name)
            insertionOrder.append(key)
        }
        entries[key]?.requestCount += 1
        if entries[key]?.identity == nil {
            entries[key]?.identity = transaction.clientApplicationIdentity
        }
        if !host.isEmpty {
            entries[key]?.domainCounts[host, default: 0] += 1
        }
        if memberships[id] == nil {
            memberships[id] = Membership(name: name, host: host, identity: transaction.clientApplicationIdentity)
        }
    }

    mutating func remove(_ transaction: HTTPTransaction, appName: String?) {
        let name = Self.normalizedAppName(appName)
        let id = ObjectIdentifier(transaction)
        if supportsIncrementalRemoval {
            guard let membership = memberships[id], membership.name == name else {
                return
            }
            memberships.removeValue(forKey: id)
            subtract(membership)
        } else {
            subtract(Membership(
                name: name,
                host: transaction.request.host.trimmingCharacters(in: .whitespacesAndNewlines),
                identity: nil
            ))
        }
    }

    @discardableResult
    mutating func remove(_ transactions: [HTTPTransaction]) -> Bool {
        guard supportsIncrementalRemoval else {
            return false
        }
        var changed = false
        for transaction in transactions {
            if let membership = memberships.removeValue(forKey: ObjectIdentifier(transaction)) {
                subtract(membership)
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    mutating func upsert(_ transaction: HTTPTransaction, appName: String? = nil) -> Bool {
        guard supportsIncrementalRemoval else {
            return false
        }
        let name = Self.normalizedAppName(appName ?? transaction.clientApp)
        let host = transaction.request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = transaction.clientApplicationIdentity
        let id = ObjectIdentifier(transaction)
        if var old = memberships[id] {
            if old.name == name, old.host == host {
                guard old.identity != identity else {
                    return false
                }
                old.identity = identity
                memberships[id] = old
                if entries[Self.key(for: name)]?.identity == nil {
                    entries[Self.key(for: name)]?.identity = identity
                }
                return true
            }
            memberships.removeValue(forKey: id)
            subtract(old)
        }
        add(transaction, appName: name)
        return true
    }

    mutating func reconcileRetainedOrder(_ history: [HTTPTransaction]) {
        var order: [String] = []
        var seen: Set<String> = []
        var identities: [String: ClientApplicationIdentity] = [:]
        for transaction in history {
            guard let membership = memberships[ObjectIdentifier(transaction)] else {
                continue
            }
            let key = Self.key(for: membership.name)
            if seen.insert(key).inserted {
                order.append(key)
            }
            if identities[key] == nil, let identity = membership.identity {
                identities[key] = identity
            }
        }
        for key in insertionOrder where !seen.contains(key) {
            order.append(key)
        }
        insertionOrder = order
        for key in entries.keys {
            entries[key]?.identity = identities[key]
        }
    }

    func makeNodes() -> [AppInfo] {
        insertionOrder.compactMap { key in
            guard let entry = entries[key] else {
                return nil
            }
            return AppInfo(
                name: entry.name,
                domains: entry.domainCounts.keys.sorted(),
                requestCount: entry.requestCount,
                identity: entry.identity
            )
        }
    }

    // MARK: Private

    private struct Entry {
        let name: String
        var requestCount = 0
        var domainCounts: [String: Int] = [:]
        var identity: ClientApplicationIdentity?
    }

    private struct Membership {
        let name: String
        let host: String
        var identity: ClientApplicationIdentity?
    }

    private var entries: [String: Entry] = [:]
    private var insertionOrder: [String] = []
    private var memberships: [ObjectIdentifier: Membership] = [:]

    private static func key(for name: String) -> String {
        "name:\(name)"
    }

    private static func normalizedAppName(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? String(localized: "Unknown", bundle: RockxyLocalization.bundle) : normalized
    }

    private mutating func subtract(_ membership: Membership) {
        let key = Self.key(for: membership.name)
        guard let count = entries[key]?.requestCount else {
            return
        }
        if count <= 1 {
            entries.removeValue(forKey: key)
            insertionOrder.removeAll { $0 == key }
            return
        }
        entries[key]?.requestCount = count - 1
        if !membership.host.isEmpty, let domains = entries[key]?.domainCounts[membership.host] {
            if domains <= 1 {
                entries[key]?.domainCounts.removeValue(forKey: membership.host)
            } else {
                entries[key]?.domainCounts[membership.host] = domains - 1
            }
        }
    }
}

// MARK: - DomainGrouping

enum DomainGrouping {
    // MARK: Internal

    struct NodeSpec {
        let id: String
        let parentID: String?
        let title: String
        let kind: DomainNode.Kind
        let filterDomain: String
        let pathPrefix: String?
    }

    static func nodeSpecs(for transaction: HTTPTransaction) -> [NodeSpec] {
        let host = normalizedHost(transaction.request.host)
        guard !host.isEmpty else {
            return []
        }

        let rootDomain = registrableDomain(for: host)
        let rootID = "domain:\(rootDomain)"
        var specs = [
            NodeSpec(
                id: rootID,
                parentID: nil,
                title: rootDomain,
                kind: .domain,
                filterDomain: rootDomain,
                pathPrefix: nil
            ),
        ]

        let parentID: String
        let pathFilterDomain: String
        if host == rootDomain {
            parentID = rootID
            pathFilterDomain = rootDomain
        } else {
            let hostID = "host:\(host)"
            specs.append(
                NodeSpec(
                    id: hostID,
                    parentID: rootID,
                    title: host,
                    kind: .host,
                    filterDomain: host,
                    pathPrefix: nil
                )
            )
            parentID = hostID
            pathFilterDomain = host
        }

        specs.append(contentsOf: pathSpecs(
            path: transaction.request.path,
            parentID: parentID,
            host: pathFilterDomain
        ))
        return specs
    }

    static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: dotCharacters)
            .lowercased()
    }

    static func host(_ host: String, matchesDomain domain: String) -> Bool {
        let candidateHost = normalizedHost(host)
        let candidateDomain = normalizedHost(domain)
        return candidateHost == candidateDomain || candidateHost.hasSuffix(".\(candidateDomain)")
    }

    static func path(_ path: String, matchesPrefix prefix: String?) -> Bool {
        guard let prefix, !prefix.isEmpty, prefix != "/" else {
            return true
        }
        return path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : "\(prefix)/")
    }

    static func isError(_ transaction: HTTPTransaction) -> Bool {
        if transaction.state == .failed || transaction.isTLSFailure {
            return true
        }
        guard let statusCode = transaction.response?.statusCode else {
            return false
        }
        return statusCode >= 400
    }

    // MARK: Private

    private static let maxPathDepth = 3
    private static let dotCharacters = CharacterSet(charactersIn: ".")

    private static let multiPartPublicSuffixes: Set<String> = [
        "ac.uk", "co.jp", "co.kr", "co.nz", "co.uk", "co.za", "com.au", "com.br",
        "com.cn", "com.hk", "com.mx", "com.sg", "com.tr", "com.tw", "com.vn",
        "edu.au", "gov.au", "gov.uk", "net.au", "net.cn", "net.nz", "ne.jp",
        "org.au", "org.cn", "org.uk",
    ]

    private static func registrableDomain(for host: String) -> String {
        if host == "localhost" || isIPAddress(host) {
            return host
        }

        let parts = host.split(separator: ".").map(String.init)
        guard parts.count > 2 else {
            return host
        }

        let suffix = parts.suffix(2).joined(separator: ".")
        let componentCount = multiPartPublicSuffixes.contains(suffix) ? 3 : 2
        return parts.suffix(componentCount).joined(separator: ".")
    }

    private static func pathSpecs(path: String, parentID: String, host: String) -> [NodeSpec] {
        let segments = path.split(separator: "/").map(String.init)
        guard !segments.isEmpty else {
            return []
        }

        var specs: [NodeSpec] = []
        var currentParentID = parentID
        var prefixSegments: [String] = []
        for rawSegment in segments.prefix(maxPathDepth) {
            prefixSegments.append(rawSegment)
            let normalizedSegment = displaySegment(for: rawSegment, canCollapseDynamic: prefixSegments.count > 1)
            let prefix = pathPrefix(for: prefixSegments, normalizedSegment: normalizedSegment)
            let id = "path:\(host):\(prefix)"
            specs.append(
                NodeSpec(
                    id: id,
                    parentID: currentParentID,
                    title: "/\(normalizedSegment)",
                    kind: .path,
                    filterDomain: host,
                    pathPrefix: prefix
                )
            )
            currentParentID = id
        }
        return specs
    }

    private static func pathPrefix(for segments: [String], normalizedSegment: String) -> String {
        if normalizedSegment == "{id}", segments.count > 1 {
            return "/" + segments.dropLast().joined(separator: "/") + "/"
        }
        return "/" + segments.joined(separator: "/")
    }

    private static func displaySegment(for segment: String, canCollapseDynamic: Bool) -> String {
        if canCollapseDynamic, isDynamicPathSegment(segment) {
            return "{id}"
        }
        if segment.count > 36 {
            return String(segment.prefix(33)) + "..."
        }
        return segment
    }

    private static func isDynamicPathSegment(_ segment: String) -> Bool {
        if segment.allSatisfy(\.isNumber) {
            return true
        }
        if UUID(uuidString: segment) != nil {
            return true
        }
        if segment.count >= 16, segment.allSatisfy(\.isHexDigit) {
            return true
        }
        return false
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") {
            return true
        }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else {
            return false
        }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0 ... 255).contains(value) else {
                return false
            }
            return String(value) == part
        }
    }
}
