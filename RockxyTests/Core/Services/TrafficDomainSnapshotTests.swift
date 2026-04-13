import Foundation
@testable import Rockxy
import Testing

// MARK: - TrafficDomainSnapshotTests

@Suite(.serialized)
@MainActor
struct TrafficDomainSnapshotTests {
    // MARK: - Snapshot Population

    @Test("update populates app entries with domains")
    func updatePopulatesAppEntries() {
        TrafficDomainSnapshot.shared.reset()
        let snapshot = TrafficDomainSnapshot.shared
        let apps = [
            AppInfo(name: "TestApp", domains: ["api.test.com", "cdn.test.com"], requestCount: 5),
            AppInfo(name: "OtherApp", domains: ["other.com"], requestCount: 2),
        ]
        let domains = [
            DomainNode(id: "api.test.com", domain: "api.test.com", requestCount: 3, children: []),
            DomainNode(id: "cdn.test.com", domain: "cdn.test.com", requestCount: 2, children: []),
            DomainNode(id: "other.com", domain: "other.com", requestCount: 2, children: []),
        ]
        snapshot.update(appNodes: apps, domainTree: domains)

        #expect(snapshot.appEntries.count == 2)
        #expect(snapshot.domains.count == 3)
    }

    @Test("domains(forApp:) returns observed domains for a known app")
    func domainsForKnownApp() {
        let snapshot = TrafficDomainSnapshot.shared
        let apps = [
            AppInfo(name: "Browser", domains: ["example.com", "cdn.example.com"], requestCount: 10),
        ]
        snapshot.update(appNodes: apps, domainTree: [])

        let result = snapshot.domains(forApp: "Browser")
        #expect(result.count == 2)
        #expect(result.contains("example.com"))
        #expect(result.contains("cdn.example.com"))
    }

    @Test("domains(forApp:) returns empty for unknown app")
    func domainsForUnknownApp() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(appNodes: [], domainTree: [])

        let result = snapshot.domains(forApp: "NonexistentApp")
        #expect(result.isEmpty)
    }

    // MARK: - Picker Flow: App Selection → onAdd(appDomains)

    @Test("app selection resolves real observed domains, not guessed wildcards")
    func appSelectionUsesRealDomains() {
        let snapshot = TrafficDomainSnapshot.shared
        let apps = [
            AppInfo(name: "MyApp", domains: ["real-api.myapp.com", "analytics.myapp.com"], requestCount: 8),
        ]
        snapshot.update(appNodes: apps, domainTree: [])

        let resolved = snapshot.domains(forApp: "MyApp")
        #expect(resolved == ["real-api.myapp.com", "analytics.myapp.com"])
        #expect(!resolved.contains { $0.hasPrefix("*.") })
    }

    @Test("app selection with observed domains produces non-empty result for onAdd")
    func appSelectionProducesDomainsForOnAdd() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(
            appNodes: [AppInfo(name: "Chrome", domains: ["google.com", "gstatic.com"], requestCount: 5)],
            domainTree: []
        )

        let domains = snapshot.domains(forApp: "Chrome")
        #expect(domains.count == 2)
        #expect(domains[0] == "google.com")
        #expect(domains[1] == "gstatic.com")
    }

    @Test("app with no observed domains blocks Add — returns empty")
    func appWithNoDomainsBlocksAdd() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(
            appNodes: [AppInfo(name: "SilentApp", domains: [], requestCount: 0)],
            domainTree: []
        )

        let resolved = snapshot.domains(forApp: "SilentApp")
        #expect(resolved.isEmpty)
    }

    // MARK: - Picker Flow: Domain Selection → onAdd([domain])

    @Test("domain selection routes single domain to onAdd")
    func domainSelectionSingleDomain() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(
            appNodes: [],
            domainTree: [DomainNode(id: "api.test.com", domain: "api.test.com", requestCount: 1, children: [])]
        )

        #expect(snapshot.domains == ["api.test.com"])
    }

    // MARK: - Snapshot Refresh: Clear Session Path

    @Test("clear session empties the snapshot")
    func clearSessionEmptiesSnapshot() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(
            appNodes: [AppInfo(name: "App", domains: ["d.com"], requestCount: 1)],
            domainTree: [DomainNode(id: "d.com", domain: "d.com", requestCount: 1, children: [])]
        )
        #expect(!snapshot.appEntries.isEmpty)

        snapshot.update(appNodes: [], domainTree: [])
        #expect(snapshot.appEntries.isEmpty)
        #expect(snapshot.domains.isEmpty)
    }

    // MARK: - Snapshot Refresh: Rebuild / Enrichment Path

    @Test("rebuild replaces stale data with fresh data")
    func rebuildReplacesStaleData() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(
            appNodes: [AppInfo(name: "OldApp", domains: ["old.com"], requestCount: 1)],
            domainTree: [DomainNode(id: "old.com", domain: "old.com", requestCount: 1, children: [])]
        )

        snapshot.update(
            appNodes: [AppInfo(name: "NewApp", domains: ["new.com"], requestCount: 1)],
            domainTree: [DomainNode(id: "new.com", domain: "new.com", requestCount: 1, children: [])]
        )

        #expect(snapshot.appEntries.count == 1)
        #expect(snapshot.appEntries[0].name == "NewApp")
        #expect(snapshot.domains == ["new.com"])
        #expect(snapshot.domains(forApp: "OldApp").isEmpty)
    }

    @Test("enrichment updates app names while preserving domains")
    func enrichmentUpdatesAppNames() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(
            appNodes: [AppInfo(name: "Unknown", domains: ["api.com"], requestCount: 1)],
            domainTree: [DomainNode(id: "api.com", domain: "api.com", requestCount: 1, children: [])]
        )
        #expect(snapshot.domains(forApp: "Unknown") == ["api.com"])

        snapshot.update(
            appNodes: [AppInfo(name: "Chrome", domains: ["api.com"], requestCount: 1)],
            domainTree: [DomainNode(id: "api.com", domain: "api.com", requestCount: 1, children: [])]
        )
        #expect(snapshot.domains(forApp: "Chrome") == ["api.com"])
        #expect(snapshot.domains(forApp: "Unknown").isEmpty)
    }

    // MARK: - Snapshot Refresh: Import Path (HAR / Session)

    @Test("import populates snapshot with imported app and domain data")
    func importPopulatesSnapshot() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(appNodes: [], domainTree: [])
        #expect(snapshot.appEntries.isEmpty)

        snapshot.update(
            appNodes: [
                AppInfo(name: "ImportedApp", domains: ["imported-api.com", "imported-cdn.com"], requestCount: 3),
            ],
            domainTree: [
                DomainNode(id: "imported-api.com", domain: "imported-api.com", requestCount: 2, children: []),
                DomainNode(id: "imported-cdn.com", domain: "imported-cdn.com", requestCount: 1, children: []),
            ]
        )

        #expect(snapshot.appEntries.count == 1)
        #expect(snapshot.appEntries[0].name == "ImportedApp")
        #expect(snapshot.domains.count == 2)
        #expect(snapshot.domains(forApp: "ImportedApp") == ["imported-api.com", "imported-cdn.com"])
    }

    @Test("import after clear replaces empty snapshot with imported data")
    func importAfterClearReplacesData() {
        let snapshot = TrafficDomainSnapshot.shared

        snapshot.update(
            appNodes: [AppInfo(name: "LiveApp", domains: ["live.com"], requestCount: 5)],
            domainTree: [DomainNode(id: "live.com", domain: "live.com", requestCount: 5, children: [])]
        )

        snapshot.update(appNodes: [], domainTree: [])
        #expect(snapshot.appEntries.isEmpty)

        snapshot.update(
            appNodes: [AppInfo(name: "HARApp", domains: ["har-domain.com"], requestCount: 1)],
            domainTree: [DomainNode(id: "har-domain.com", domain: "har-domain.com", requestCount: 1, children: [])]
        )

        #expect(snapshot.appEntries.count == 1)
        #expect(snapshot.appEntries[0].name == "HARApp")
        #expect(snapshot.domains(forApp: "LiveApp").isEmpty)
        #expect(snapshot.domains(forApp: "HARApp") == ["har-domain.com"])
    }
}
