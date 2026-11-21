import Foundation
@testable import Rockxy
import Testing

// The domain and app indexes are patched as rows arrive and leave. Whatever sequence of
// adds and evictions produced the current rows, what they publish has to equal what a
// fresh index built from only the surviving rows publishes.

// MARK: - DomainGroupingIncrementalEquivalenceTests

@MainActor
struct DomainGroupingIncrementalEquivalenceTests {
    // MARK: Internal

    @Test("A randomized run of adds and evictions always equals a rebuild")
    func randomizedAddsAndEvictionsMatchRebuild() {
        for seed in 1 ... 12 {
            var generator = SplitMix64(seed: UInt64(seed))
            var domains = DomainGroupingIndex()
            var apps = AppGroupingIndex()
            var history: [HTTPTransaction] = []
            var nextSequence = 0

            for step in 0 ..< 60 {
                let additions = Int(generator.next() % 9)
                var batch: [HTTPTransaction] = []
                for _ in 0 ..< additions {
                    // A repeated sequence number is allowed on purpose: it exercises the
                    // reference counting that decides when a node's earliest row is gone.
                    if generator.next() % 6 != 0 {
                        nextSequence += 1
                    }
                    batch.append(makeRow(sequence: nextSequence, using: &generator))
                }
                for row in batch {
                    domains.add(row)
                    apps.add(row)
                }
                history.append(contentsOf: batch)

                let removed = pickRemovals(from: history, step: step, using: &generator)
                if !removed.isEmpty {
                    let ids = Set(removed.map { ObjectIdentifier($0) })
                    history.removeAll { ids.contains(ObjectIdentifier($0)) }
                    domains.remove(removed)
                    apps.remove(removed)
                    apps.reconcileRetainedOrder(history)
                }
                assertEquivalent(domains: &domains, apps: apps, history: history, context: "seed \(seed) step \(step)")
            }
        }
    }

    @Test("Evicting a node's earliest row moves the node to its next-earliest row")
    func evictingTheEarliestRowRepositionsTheNode() {
        var domains = DomainGroupingIndex()
        let first = row("https://a.example.com/x", sequence: 1)
        let second = row("https://b.example.com/x", sequence: 2)
        let third = row("https://a.example.com/x", sequence: 3)
        for row in [first, second, third] {
            domains.add(row)
        }
        let initial = domains.makeTree()
        #expect(initial.map(\.id) == ["domain:example.com"])

        // Root keeps its position (b.example.com's row is still sequence 2), but the host
        // `a` loses sequence 1 and now sorts by sequence 3, behind host `b`.
        domains.remove([first])
        let tree = domains.makeTree()
        #expect(tree[0].children.map(\.domain) == ["b.example.com", "a.example.com"])
        #expect(tree[0].firstSeenSequence == 2)
    }

    @Test("Evicting every row of a node removes it and its selection domain")
    func evictingAWholeNodeRemovesIt() {
        var domains = DomainGroupingIndex()
        let kept = row("https://keep.test/a", sequence: 1)
        let gone = [row("https://drop.test/a/b", sequence: 2), row("https://sub.drop.test/c", sequence: 3)]
        for row in [kept] + gone {
            domains.add(row)
        }
        domains.remove(gone)
        let tree = domains.makeTree()
        #expect(tree.map(\.id) == ["domain:keep.test"])
        #expect(domains.rootRequestTotal == 1)
        #expect(!domains.sortedSelectionDomains.contains { $0.contains("drop") })
    }

    @Test("Rows sharing a sequence keep a node in place until the last one leaves")
    func sharedSequenceIsReferenceCounted() {
        var domains = DomainGroupingIndex()
        let early = row("https://one.test/a", sequence: 1)
        let twin = row("https://one.test/b", sequence: 1)
        let late = row("https://one.test/c", sequence: 5)
        let other = row("https://two.test/a", sequence: 3)
        for row in [early, twin, late, other] {
            domains.add(row)
        }
        domains.remove([early])
        let afterEarly = domains.makeTree()
        #expect(afterEarly.map(\.id) == ["domain:one.test", "domain:two.test"])
        domains.remove([twin])
        let afterTwin = domains.makeTree()
        #expect(afterTwin.map(\.id) == ["domain:two.test", "domain:one.test"])
    }

    // MARK: Private

    private struct SplitMix64: RandomNumberGenerator {
        // MARK: Lifecycle

        init(seed: UInt64) {
            state = seed &* 0x9E3779B97F4A7C15
        }

        // MARK: Internal

        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }

    private static let hosts = [
        "example.com", "api.example.com", "cdn.example.com", "shop.test", "www.shop.test",
        "a.b.example.co.uk", "localhost", "10.0.0.7", "Zeta.org", "zeta.org",
    ]
    private static let paths = [
        "/", "/v1/users", "/v1/users/42", "/v1/orders/7/items", "/static/app.js", "/health",
        "/v2/users/9001", "/a/b/c/d",
    ]
    private static let apps = ["Safari", "Terminal", "curl", "Xcode", ""]

    private func row(_ url: String, sequence: Int) -> HTTPTransaction {
        let transaction = TestFixtures.makeTransaction(url: url)
        transaction.sequenceNumber = sequence
        return transaction
    }

    private func makeRow(sequence: Int, using generator: inout SplitMix64) -> HTTPTransaction {
        let host = Self.hosts[Int(generator.next() % UInt64(Self.hosts.count))]
        let path = Self.paths[Int(generator.next() % UInt64(Self.paths.count))]
        let status = generator.next() % 5 == 0 ? 500 : 200
        let transaction = TestFixtures.makeTransaction(
            method: generator.next() % 2 == 0 ? "GET" : "POST",
            url: "https://\(host)\(path)",
            statusCode: status
        )
        transaction.sequenceNumber = sequence
        let app = Self.apps[Int(generator.next() % UInt64(Self.apps.count))]
        transaction.clientApp = app.isEmpty ? nil : app
        return transaction
    }

    /// Mixes the shapes eviction takes: the oldest rows, every row of one root domain, the
    /// earliest row of a node, and an arbitrary scatter.
    private func pickRemovals(
        from history: [HTTPTransaction],
        step: Int,
        using generator: inout SplitMix64
    )
        -> [HTTPTransaction]
    {
        guard !history.isEmpty else {
            return []
        }
        switch step % 4 {
        case 0:
            return Array(history.prefix(Int(generator.next() % 6)))
        case 1:
            let target = DomainGrouping.nodeSpecs(
                for: history[Int(generator.next() % UInt64(history.count))]
            ).first?.id
            return history.filter { DomainGrouping.nodeSpecs(for: $0).first?.id == target }
        case 2:
            let victim = history[Int(generator.next() % UInt64(history.count))]
            let nodeID = DomainGrouping.nodeSpecs(for: victim).last?.id
            let inNode = history.filter { DomainGrouping.nodeSpecs(for: $0).contains { $0.id == nodeID } }
            return inNode.min { $0.sequenceNumber < $1.sequenceNumber }.map { [$0] } ?? []
        default:
            return history.filter { _ in generator.next() % 5 == 0 }
        }
    }

    private func assertEquivalent(
        domains: inout DomainGroupingIndex,
        apps: AppGroupingIndex,
        history: [HTTPTransaction],
        context: String
    ) {
        var rebuiltDomains = DomainGroupingIndex()
        var rebuiltApps = AppGroupingIndex()
        // The rebuild feeds rows in sequence order, as a rebuild over the retained history
        // would, so nothing but the surviving rows can explain a difference.
        for row in history.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            rebuiltDomains.add(row)
        }
        for row in history {
            rebuiltApps.add(row)
        }
        let tree = domains.makeTree()
        let rebuiltTree = rebuiltDomains.makeTree()
        #expect(tree == rebuiltTree, "\(context): tree")
        #expect(domains.rootRequestTotal == rebuiltDomains.rootRequestTotal, "\(context): total")
        #expect(domains.sortedSelectionDomains == rebuiltDomains.sortedSelectionDomains, "\(context): domains")
        #expect(summary(apps.makeNodes()) == summary(rebuiltApps.makeNodes()), "\(context): apps")
    }

    private func summary(_ nodes: [AppInfo]) -> [String] {
        nodes.map { "\($0.name)|\($0.requestCount)|\($0.domains)" }
    }
}
