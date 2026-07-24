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

    mutating func removeAll() {
        nodesByID.removeAll(keepingCapacity: true)
        childIDsByParentID.removeAll(keepingCapacity: true)
        rootIDs.removeAll(keepingCapacity: true)
    }

    mutating func add(_ transaction: HTTPTransaction) {
        let specs = DomainGrouping.nodeSpecs(for: transaction)
        guard !specs.isEmpty else {
            return
        }

        for spec in specs {
            var node = nodesByID[spec.id] ?? DomainNode(
                id: spec.id,
                domain: spec.title,
                requestCount: 0,
                children: [],
                kind: spec.kind,
                filterDomain: spec.filterDomain,
                pathPrefix: spec.pathPrefix,
                firstSeenSequence: transaction.sequenceNumber
            )
            node.requestCount += 1
            if DomainGrouping.isError(transaction) {
                node.errorCount += 1
            }
            node.methods.insert(transaction.request.method)
            node.firstSeenSequence = min(node.firstSeenSequence, transaction.sequenceNumber)
            nodesByID[spec.id] = node

            if let parentID = spec.parentID {
                childIDsByParentID[parentID, default: []].insert(spec.id)
            } else {
                rootIDs.insert(spec.id)
            }
        }
    }

    func makeTree(alphabetical: Bool = false) -> [DomainNode] {
        sorted(ids: rootIDs, alphabetical: alphabetical).map { makeNode(id: $0, alphabetical: alphabetical) }
    }

    // MARK: Private

    private var nodesByID: [String: DomainNode] = [:]
    private var childIDsByParentID: [String: Set<String>] = [:]
    private var rootIDs: Set<String> = []

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
struct AppGroupingIndex {
    // MARK: Internal

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
    }

    mutating func add(_ transaction: HTTPTransaction, appName: String? = nil) {
        let name = Self.normalizedAppName(appName ?? transaction.clientApp)
        let host = transaction.request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if entries[name] == nil {
            entries[name] = Entry()
            insertionOrder.append(name)
        }
        entries[name]?.requestCount += 1
        if !host.isEmpty {
            entries[name]?.domainCounts[host, default: 0] += 1
        }
    }

    mutating func remove(_ transaction: HTTPTransaction, appName: String?) {
        let name = Self.normalizedAppName(appName)
        guard var entry = entries[name] else {
            return
        }
        entry.requestCount = max(0, entry.requestCount - 1)

        let host = transaction.request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty, let count = entry.domainCounts[host] {
            if count <= 1 {
                entry.domainCounts.removeValue(forKey: host)
            } else {
                entry.domainCounts[host] = count - 1
            }
        }

        if entry.requestCount == 0 {
            entries.removeValue(forKey: name)
            insertionOrder.removeAll { $0 == name }
        } else {
            entries[name] = entry
        }
    }

    func makeNodes() -> [AppInfo] {
        insertionOrder.compactMap { name in
            guard let entry = entries[name] else {
                return nil
            }
            return AppInfo(
                name: name,
                domains: entry.domainCounts.keys.sorted(),
                requestCount: entry.requestCount
            )
        }
    }

    // MARK: Private

    private struct Entry {
        var requestCount = 0
        var domainCounts: [String: Int] = [:]
    }

    private var entries: [String: Entry] = [:]
    private var insertionOrder: [String] = []

    private static func normalizedAppName(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? String(localized: "Unknown") : normalized
    }
}

// MARK: - DomainGrouping

enum DomainGrouping {
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
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
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
