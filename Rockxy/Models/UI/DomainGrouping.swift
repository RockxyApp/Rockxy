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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - DomainGroupingIndex

/// Incremental domain, host, and path counts behind the sidebar's domain source list.
///
/// The index also owns the materialized `[DomainNode]` tree it last published and patches
/// only the branches that changed. `makeTree` used to rebuild and re-sort every node on
/// every delivery batch, once per open Traffic Tab, and the node count here is the number
/// of distinct hosts and paths observed -- which grows for the whole session and is not
/// bounded by the transaction cap, so evicting rows never shrank it. That made this the
/// one piece of derived state whose cost rose monotonically with hours of capture.
struct DomainGroupingIndex {
    // MARK: Internal

    private(set) var supportsIncrementalRemoval = true

    /// Requests recorded against the root nodes: what reducing `requestCount` over the
    /// published tree's top level produced. Maintained because that reduce was itself a
    /// per-batch pass over a root list that only ever grows.
    private(set) var rootRequestTotal = 0

    /// Every non-path node's `selectionDomain`, already in the order
    /// `TrafficDomainSnapshot` publishes them in: case-insensitive collation, with the raw
    /// value breaking ties so the order is total rather than merely self-consistent.
    ///
    /// Maintained for the same reason the tree is. The snapshot flattened the whole tree
    /// and re-sorted every observed domain on each batch, and one collation comparison is
    /// a full ICU collator call -- over a collection the history cap does not bound.
    private(set) var sortedSelectionDomains: [String] = []

    /// Bumped when the root list's membership or order changes, never for a count change,
    /// so `refreshDomainTree` rebuilds `domainIndexMap` only when it can have changed.
    private(set) var rootOrderRevision: UInt = 0

    func contains(_ transaction: HTTPTransaction) -> Bool {
        contributions[ObjectIdentifier(transaction)] != nil
    }

    mutating func removeAll() {
        nodesByID.removeAll(keepingCapacity: true)
        childIDsByParentID.removeAll(keepingCapacity: true)
        rootIDs.removeAll(keepingCapacity: true)
        parentIDs.removeAll(keepingCapacity: true)
        methodCounts.removeAll(keepingCapacity: true)
        sequenceLedgers.removeAll(keepingCapacity: true)
        contributions.removeAll(keepingCapacity: true)
        projectedNodesByID.removeAll(keepingCapacity: true)
        projectedTree.removeAll(keepingCapacity: true)
        dirtyNodeIDs.removeAll(keepingCapacity: true)
        rootIndexByID.removeAll(keepingCapacity: true)
        selectionDomainCounts.removeAll(keepingCapacity: true)
        sortedSelectionDomains.removeAll(keepingCapacity: true)
        rootRequestTotal = 0
        rootIndexIsStale = true
        rootOrderRevision &+= 1
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
            let existing = nodesByID[spec.id]
            var node = existing ?? DomainNode(
                id: spec.id, domain: spec.title, requestCount: 0, children: [],
                kind: spec.kind, filterDomain: spec.filterDomain,
                pathPrefix: spec.pathPrefix, firstSeenSequence: sequence
            )
            let previousSequence = node.firstSeenSequence
            node.requestCount += 1
            if isError {
                node.errorCount += 1
            }
            node.methods.insert(method)
            node.firstSeenSequence = min(node.firstSeenSequence, sequence)
            nodesByID[spec.id] = node
            methodCounts[spec.id, default: [:]][method, default: 0] += 1
            sequenceLedgers[spec.id, default: SequenceLedger()].add(sequence)
            nodeIDs.append(node.id)
            if spec.parentID == nil {
                rootRequestTotal += 1
            }
            if existing == nil {
                if let parent = spec.parentID {
                    parentIDs[spec.id] = parent
                    insert(spec.id, intoChildrenOf: parent)
                } else {
                    insertRoot(spec.id)
                }
                if spec.kind != .path {
                    retainSelectionDomain(node.selectionDomain)
                }
            } else if node.firstSeenSequence != previousSequence {
                // A node sits at its earliest contributing sequence, so a row older than
                // everything already filed under it moves the node. An append can never
                // lower it -- which is why the ordinary capture path only ever inserts a
                // brand-new node, and at the end of its sibling list.
                reposition(spec.id)
            }
            markDirty(spec.id)
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
                    for nodeID in old.nodeIDs where nodesByID[nodeID] != nil {
                        nodesByID[nodeID]?.errorCount += delta
                        // The error badge is part of the published node, so a row that
                        // only changed disposition still invalidates the branch it is on.
                        markDirty(nodeID)
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

    /// The published tree, with only the branches that changed since the last call rebuilt.
    ///
    /// `alphabetical` is the one-shot sidebar sort command and deliberately bypasses the
    /// projection: it publishes a different order from the one the index maintains, is not
    /// sticky (the next batch republishes capture order), and must not leave the cache
    /// describing an order the index does not hold.
    mutating func makeTree(alphabetical: Bool = false) -> [DomainNode] {
        guard !alphabetical else {
            return alphabeticalOrder(of: rootIDs).map { alphabeticalNode(id: $0) }
        }
        if rootIndexIsStale {
            var tree: [DomainNode] = []
            tree.reserveCapacity(rootIDs.count)
            rootIndexByID.removeAll(keepingCapacity: true)
            for (index, id) in rootIDs.enumerated() {
                rootIndexByID[id] = index
                tree.append(projectedNode(id: id))
            }
            projectedTree = tree
            rootIndexIsStale = false
        } else {
            // Marking a node dirty marks every ancestor, so a dirty node always has a
            // dirty root above it and rebuilding the dirty roots reaches all of them.
            for id in dirtyNodeIDs where parentIDs[id] == nil {
                guard let index = rootIndexByID[id] else {
                    continue
                }
                // Through a local, so the mutating projection call does not overlap the
                // write access to the array it is being stored into.
                let node = projectedNode(id: id)
                projectedTree[index] = node
            }
        }
        dirtyNodeIDs.removeAll(keepingCapacity: true)
        return projectedTree
    }

    // MARK: Private

    /// Reference-counted sequences kept in ascending order.
    ///
    /// Eviction removes the oldest rows, so the sequence a node was positioned by is the one
    /// that leaves, and the replacement used to be found with `keys.min()` -- a scan of every
    /// distinct sequence under the node, which for a busy root domain is most of the
    /// retained history. The distinct values are kept sorted instead, so the earliest is
    /// `first` and losing it is a removal at the front. `Int` order is total and the values
    /// are distinct, which is what makes the binary search safe.
    private struct SequenceLedger {
        // MARK: Internal

        private(set) var sorted: [Int] = []

        var earliest: Int? {
            sorted.first
        }

        mutating func add(_ sequence: Int) {
            let count = counts[sequence] ?? 0
            counts[sequence] = count + 1
            guard count == 0 else {
                return
            }
            sorted.insert(sequence, at: lowerBound(of: sequence))
        }

        /// Returns `true` when this was the last row carrying `sequence`.
        @discardableResult
        mutating func remove(_ sequence: Int) -> Bool {
            guard let count = counts[sequence] else {
                return false
            }
            guard count <= 1 else {
                counts[sequence] = count - 1
                return false
            }
            counts.removeValue(forKey: sequence)
            let index = lowerBound(of: sequence)
            if index < sorted.count, sorted[index] == sequence {
                sorted.remove(at: index)
            }
            return true
        }

        // MARK: Private

        private var counts: [Int: Int] = [:]

        private func lowerBound(of sequence: Int) -> Int {
            var low = 0
            var high = sorted.count
            while low < high {
                let middle = low + (high - low) / 2
                if sorted[middle] < sequence {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low
        }
    }

    private struct Contribution {
        let url: URL
        let nodeIDs: [String]
        let method: String
        let sequence: Int
        var isError: Bool
    }

    private var nodesByID: [String: DomainNode] = [:]
    /// Sibling ids in published order, maintained by insertion rather than re-sorted.
    private var childIDsByParentID: [String: [String]] = [:]
    private var rootIDs: [String] = []
    private var parentIDs: [String: String] = [:]
    private var methodCounts: [String: [String: Int]] = [:]
    /// Per node, the sequences of the rows filed under it, with the earliest kept at hand so
    /// a node that loses its earliest row learns its next one without scanning the rest.
    private var sequenceLedgers: [String: SequenceLedger] = [:]
    private var contributions: [ObjectIdentifier: Contribution] = [:]

    /// The last published form of each node, children attached. Kept so a batch rebuilds
    /// only the branches it touched instead of every node in the capture.
    private var projectedNodesByID: [String: DomainNode] = [:]
    /// Nodes whose published form is out of date, always together with their ancestors.
    private var dirtyNodeIDs: Set<String> = []
    private var projectedTree: [DomainNode] = []
    private var rootIndexByID: [String: Int] = [:]
    private var rootIndexIsStale = true
    private var selectionDomainCounts: [String: Int] = [:]

    private static func insertionIndex(of value: String, in values: [String]) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let middle = low + (high - low) / 2
            if DomainGrouping.isOrderedBefore(domain: values[middle], value) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private mutating func subtract(_ contribution: Contribution, dirtyOrdering: inout Set<String>) {
        for id in contribution.nodeIDs {
            guard var node = nodesByID[id] else {
                continue
            }
            let isRoot = parentIDs[id] == nil
            node.requestCount -= 1
            if contribution.isError {
                node.errorCount -= 1
            }
            if isRoot {
                rootRequestTotal -= 1
            }
            let methods = methodCounts[id]?[contribution.method] ?? 0
            if methods <= 1 {
                methodCounts[id]?.removeValue(forKey: contribution.method)
                node.methods.remove(contribution.method)
            } else {
                methodCounts[id]?[contribution.method] = methods - 1
            }
            if sequenceLedgers[id]?.remove(contribution.sequence) == true,
               node.firstSeenSequence == contribution.sequence
            {
                dirtyOrdering.insert(id)
            }
            if node.requestCount == 0 {
                nodesByID.removeValue(forKey: id)
                methodCounts.removeValue(forKey: id)
                sequenceLedgers.removeValue(forKey: id)
                dirtyOrdering.remove(id)
                projectedNodesByID.removeValue(forKey: id)
                dirtyNodeIDs.remove(id)
                if node.kind != .path {
                    releaseSelectionDomain(node.selectionDomain)
                }
                if let parent = parentIDs.removeValue(forKey: id) {
                    remove(id, fromChildrenOf: parent)
                    // Nodes are subtracted root first, so the parent may already be gone.
                    // Marking a dead id leaves it in the dirty set, and `markDirty` stops
                    // at the first node already in the set: when that id is later recreated
                    // in the same cycle, its ancestors are never marked and their cached
                    // projection keeps omitting the new branch.
                    if nodesByID[parent] != nil {
                        markDirty(parent)
                    }
                } else {
                    removeRoot(id)
                }
                childIDsByParentID.removeValue(forKey: id)
            } else {
                nodesByID[id] = node
                markDirty(id)
            }
        }
    }

    private mutating func reconcileOrdering(_ nodeIDs: Set<String>) {
        for id in nodeIDs {
            guard let node = nodesByID[id] else {
                continue
            }
            let firstSeen = sequenceLedgers[id]?.earliest ?? .max
            guard firstSeen != node.firstSeenSequence else {
                continue
            }
            nodesByID[id]?.firstSeenSequence = firstSeen
            // The node's position is derived from this value, so losing the row it was
            // taken from moves the node among its siblings.
            reposition(id)
            markDirty(id)
        }
    }

    /// Marks `id` and every ancestor above it as needing republication. The walk stops at
    /// the first already-dirty node, which is sound because nothing is marked without its
    /// ancestors being marked in the same pass.
    private mutating func markDirty(_ id: String) {
        var current: String? = id
        while let next = current, dirtyNodeIDs.insert(next).inserted {
            current = parentIDs[next]
        }
    }

    private mutating func insert(_ id: String, intoChildrenOf parent: String) {
        var children = childIDsByParentID[parent] ?? []
        children.insert(id, at: siblingInsertionIndex(of: id, in: children))
        childIDsByParentID[parent] = children
    }

    private mutating func remove(_ id: String, fromChildrenOf parent: String) {
        guard var children = childIDsByParentID[parent], let index = children.firstIndex(of: id) else {
            return
        }
        children.remove(at: index)
        if children.isEmpty {
            childIDsByParentID.removeValue(forKey: parent)
        } else {
            childIDsByParentID[parent] = children
        }
    }

    private mutating func insertRoot(_ id: String) {
        rootIDs.insert(id, at: siblingInsertionIndex(of: id, in: rootIDs))
        rootIndexIsStale = true
        rootOrderRevision &+= 1
    }

    private mutating func removeRoot(_ id: String) {
        guard let index = rootIDs.firstIndex(of: id) else {
            return
        }
        rootIDs.remove(at: index)
        rootIndexIsStale = true
        rootOrderRevision &+= 1
    }

    private mutating func reposition(_ id: String) {
        if let parent = parentIDs[id] {
            remove(id, fromChildrenOf: parent)
            insert(id, intoChildrenOf: parent)
            markDirty(parent)
        } else {
            removeRoot(id)
            insertRoot(id)
        }
    }

    private mutating func retainSelectionDomain(_ domain: String) {
        let count = selectionDomainCounts[domain] ?? 0
        selectionDomainCounts[domain] = count + 1
        guard count == 0 else {
            return
        }
        sortedSelectionDomains.insert(
            domain,
            at: Self.insertionIndex(of: domain, in: sortedSelectionDomains)
        )
    }

    private mutating func releaseSelectionDomain(_ domain: String) {
        guard let count = selectionDomainCounts[domain] else {
            return
        }
        guard count <= 1 else {
            selectionDomainCounts[domain] = count - 1
            return
        }
        selectionDomainCounts.removeValue(forKey: domain)
        let index = Self.insertionIndex(of: domain, in: sortedSelectionDomains)
        guard index < sortedSelectionDomains.count, sortedSelectionDomains[index] == domain else {
            return
        }
        sortedSelectionDomains.remove(at: index)
    }

    private mutating func projectedNode(id: String) -> DomainNode {
        if !dirtyNodeIDs.contains(id), let projected = projectedNodesByID[id] {
            return projected
        }
        guard var node = nodesByID[id] else {
            return DomainNode(id: id, domain: id, requestCount: 0, children: [])
        }
        let childIDs = childIDsByParentID[id] ?? []
        var children: [DomainNode] = []
        children.reserveCapacity(childIDs.count)
        for childID in childIDs {
            children.append(projectedNode(id: childID))
        }
        node.children = children
        projectedNodesByID[id] = node
        return node
    }

    /// Siblings are ordered by earliest sequence, then collated title, then id. The id is
    /// what makes it a total order: without it two siblings sharing a sequence and
    /// collating equal had no defined relative position, and an unstable comparator is
    /// also unsafe to binary-search against.
    private func siblingInsertionIndex(of id: String, in ids: [String]) -> Int {
        var low = 0
        var high = ids.count
        while low < high {
            let middle = low + (high - low) / 2
            if nodeIsOrderedBefore(ids[middle], id) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func nodeIsOrderedBefore(_ lhsID: String, _ rhsID: String) -> Bool {
        guard let lhs = nodesByID[lhsID], let rhs = nodesByID[rhsID] else {
            return lhsID < rhsID
        }
        if lhs.firstSeenSequence != rhs.firstSeenSequence {
            return lhs.firstSeenSequence < rhs.firstSeenSequence
        }
        switch lhs.domain.localizedCaseInsensitiveCompare(rhs.domain) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return lhsID < rhsID
        }
    }

    private func alphabeticalOrder(of ids: [String]) -> [String] {
        ids.sorted { lhsID, rhsID in
            guard let lhs = nodesByID[lhsID], let rhs = nodesByID[rhsID] else {
                return lhsID < rhsID
            }
            switch lhs.domain.localizedCaseInsensitiveCompare(rhs.domain) {
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            case .orderedSame:
                return lhsID < rhsID
            }
        }
    }

    private func alphabeticalNode(id: String) -> DomainNode {
        guard var node = nodesByID[id] else {
            return DomainNode(id: id, domain: id, requestCount: 0, children: [])
        }
        node.children = alphabeticalOrder(of: childIDsByParentID[id] ?? []).map { alphabeticalNode(id: $0) }
        return node
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
        var entry = entries[key] ?? Entry(name: name)
        if entries[key] == nil {
            insertionOrder.append(key)
        }
        entry.requestCount += 1
        if entry.identity == nil {
            entry.identity = transaction.clientApplicationIdentity
        }
        if !host.isEmpty {
            let count = entry.domainCounts[host] ?? 0
            entry.domainCounts[host] = count + 1
            if count == 0 {
                entry.insertSortedDomain(host)
            }
        }
        entries[key] = entry
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
                domains: entry.sortedDomains,
                requestCount: entry.requestCount,
                identity: entry.identity
            )
        }
    }

    // MARK: Private

    private struct Entry {
        // MARK: Internal

        let name: String
        var requestCount = 0
        var domainCounts: [String: Int] = [:]
        var identity: ClientApplicationIdentity?

        /// `domainCounts.keys` in published order, maintained by insertion.
        ///
        /// `makeNodes()` sorted the keys on every delivery batch, and an app's contacted
        /// host set grows for the whole session -- the history cap does not bound it -- so
        /// that sort was one of the costs that rose with how long capture had run. The
        /// comparator stays the plain `<` the sort used, so the published order is
        /// unchanged.
        private(set) var sortedDomains: [String] = []

        mutating func insertSortedDomain(_ domain: String) {
            sortedDomains.insert(domain, at: Self.insertionIndex(of: domain, in: sortedDomains))
        }

        mutating func removeSortedDomain(_ domain: String) {
            let index = Self.insertionIndex(of: domain, in: sortedDomains)
            guard index < sortedDomains.count, sortedDomains[index] == domain else {
                return
            }
            sortedDomains.remove(at: index)
        }

        // MARK: Private

        private static func insertionIndex(of domain: String, in domains: [String]) -> Int {
            var low = 0
            var high = domains.count
            while low < high {
                let middle = low + (high - low) / 2
                if domains[middle] < domain {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low
        }
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
                entries[key]?.removeSortedDomain(membership.host)
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

    /// Publication order for observed domain names: case-insensitive collation, with the
    /// raw value breaking ties.
    ///
    /// The tiebreak is what makes the order total. Collation ties left two distinct names
    /// with no defined relative position, which both let them swap places between batches
    /// with no traffic change and makes the comparator unsafe to binary-search against --
    /// the same defect the Insights sorts had to add a key tiebreak for.
    static func isOrderedBefore(domain lhs: String, _ rhs: String) -> Bool {
        switch lhs.localizedCaseInsensitiveCompare(rhs) {
        case .orderedAscending:
            true
        case .orderedDescending:
            false
        case .orderedSame:
            lhs < rhs
        }
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
