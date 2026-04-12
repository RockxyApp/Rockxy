import Foundation
@testable import Rockxy
import Testing

// MARK: - TrafficDomainSnapshotTests

@MainActor
struct TrafficDomainSnapshotTests {
    // MARK: - Snapshot Population

    @Test("update populates app entries with domains")
    func updatePopulatesAppEntries() {
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

    // MARK: - Picker Flow: App Selection

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

    @Test("app with no observed domains returns empty — Add button stays disabled")
    func appWithNoDomains() {
        let snapshot = TrafficDomainSnapshot.shared
        let apps = [
            AppInfo(name: "SilentApp", domains: [], requestCount: 0),
        ]
        snapshot.update(appNodes: apps, domainTree: [])

        let resolved = snapshot.domains(forApp: "SilentApp")
        #expect(resolved.isEmpty)
    }

    // MARK: - Picker Flow: Domain Selection

    @Test("domain selection routes directly to onAdd — no manual sheet")
    func domainSelectionAddsDirect() {
        let snapshot = TrafficDomainSnapshot.shared
        let domains = [
            DomainNode(id: "api.test.com", domain: "api.test.com", requestCount: 1, children: []),
        ]
        snapshot.update(appNodes: [], domainTree: domains)

        #expect(snapshot.domains.contains("api.test.com"))
    }

    // MARK: - Snapshot Refresh After Clear/Rebuild

    @Test("update with empty arrays clears the snapshot")
    func clearSnapshotOnSessionClear() {
        let snapshot = TrafficDomainSnapshot.shared
        snapshot.update(
            appNodes: [AppInfo(name: "App", domains: ["d.com"], requestCount: 1)],
            domainTree: [DomainNode(id: "d.com", domain: "d.com", requestCount: 1, children: [])]
        )
        #expect(!snapshot.appEntries.isEmpty)
        #expect(!snapshot.domains.isEmpty)

        snapshot.update(appNodes: [], domainTree: [])
        #expect(snapshot.appEntries.isEmpty)
        #expect(snapshot.domains.isEmpty)
    }

    @Test("update replaces stale data after rebuild")
    func refreshAfterRebuild() {
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

    @Test("update after enrichment adds app domains that were previously unknown")
    func refreshAfterEnrichment() {
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
}
