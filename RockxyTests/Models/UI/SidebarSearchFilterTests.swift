import Foundation
@testable import Rockxy
import Testing

struct SidebarSearchFilterTests {
    @Test("App matches keep their descendants while domain matches keep the app ancestor")
    func appHierarchyFiltering() {
        let apps = [
            AppInfo(name: "Safari", domains: ["api.example.com", "cdn.example.com"], requestCount: 8),
            AppInfo(name: "Rockxy Helper", domains: ["localhost"], requestCount: 2),
        ]

        let appMatch = SidebarSearchFilter.apps(apps, query: "sAfArI")
        let domainMatch = SidebarSearchFilter.apps(apps, query: "cdn")

        #expect(appMatch.count == 1)
        #expect(appMatch.first?.domains == ["api.example.com", "cdn.example.com"])
        #expect(domainMatch.count == 1)
        #expect(domainMatch.first?.name == "Safari")
        #expect(domainMatch.first?.domains == ["cdn.example.com"])
    }

    @Test("Domain filtering preserves matching ancestors and prunes unrelated siblings")
    func domainHierarchyFiltering() throws {
        let matchingPath = DomainNode(
            id: "path:api.example.com:/checkout",
            domain: "/checkout",
            requestCount: 2,
            children: [],
            kind: .path,
            filterDomain: "api.example.com",
            pathPrefix: "/checkout"
        )
        let siblingPath = DomainNode(
            id: "path:api.example.com:/health",
            domain: "/health",
            requestCount: 1,
            children: [],
            kind: .path,
            filterDomain: "api.example.com",
            pathPrefix: "/health"
        )
        let host = DomainNode(
            id: "host:api.example.com",
            domain: "api.example.com",
            requestCount: 3,
            children: [matchingPath, siblingPath],
            kind: .host,
            filterDomain: "api.example.com"
        )
        let root = DomainNode(
            id: "domain:example.com",
            domain: "example.com",
            requestCount: 3,
            children: [host]
        )

        let result = SidebarSearchFilter.domainTree([root], query: "checkout")
        let filteredRoot = try #require(result.first)
        let filteredHost = try #require(filteredRoot.children.first)

        #expect(filteredRoot.domain == "example.com")
        #expect(filteredHost.domain == "api.example.com")
        #expect(filteredHost.children.map(\.domain) == ["/checkout"])
        #expect(SidebarSearchFilter.domainMatchCount([root], query: "checkout") == 1)
    }

    @Test("Domain match count counts matching descendants instead of retained roots")
    func domainMatchCount() {
        let hosts = ["api.example.com", "cdn.example.com"].map {
            DomainNode(
                id: "host:\($0)",
                domain: $0,
                requestCount: 1,
                children: [],
                kind: .host,
                filterDomain: $0
            )
        }
        let root = DomainNode(
            id: "domain:example.com",
            domain: "example.com",
            requestCount: 2,
            children: hosts
        )

        #expect(SidebarSearchFilter.domainMatchCount([root], query: "api") == 1)
        #expect(SidebarSearchFilter.domainMatchCount([root], query: "example.com") == 3)
    }

    @Test("Library transactions match URL, app, and comments")
    func libraryTransactionFiltering() {
        let checkout = TestFixtures.makeTransaction(url: "https://shop.example.com/checkout")
        checkout.clientApp = "Safari"
        checkout.comment = "payment retry"
        let health = TestFixtures.makeTransaction(url: "https://api.example.com/health")

        #expect(SidebarSearchFilter.transactions([checkout, health], query: "payment").map(\.id) == [checkout.id])
        #expect(SidebarSearchFilter.transactions([checkout, health], query: "safari").map(\.id) == [checkout.id])
        #expect(SidebarSearchFilter.transactions([checkout, health], query: "health").map(\.id) == [health.id])
    }
}
