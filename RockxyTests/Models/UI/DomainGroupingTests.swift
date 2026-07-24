import Foundation
@testable import Rockxy
import Testing

// Regression tests for sidebar domain grouping.

// MARK: - DomainGroupingTests

@MainActor
struct DomainGroupingTests {
    @Test("Groups root domains, subdomains, and paths into a recursive tree")
    func recursiveDomainTree() throws {
        let coordinator = MainContentCoordinator()
        let version = transaction("https://proxyman.com/osx/version.xml", sequence: 0)
        let events = transaction("https://proxyman.com/v1/events", sequence: 1)
        let apiEvents = transaction("https://api.proxyman.com/v1/events", sequence: 2, statusCode: 500)
        coordinator.transactions = [version, events, apiEvents]

        coordinator.rebuildSidebarIndexes()

        let root = try #require(coordinator.domainTree.first { $0.domain == "proxyman.com" })
        #expect(root.requestCount == 3)
        #expect(root.errorCount == 1)
        #expect(root.children.contains { $0.domain == "/osx" })
        #expect(root.children.contains { $0.domain == "/v1" })

        let api = try #require(root.children.first { $0.domain == "api.proxyman.com" })
        #expect(api.kind == .host)
        #expect(api.requestCount == 1)
        #expect(api.errorCount == 1)
        #expect(api.children.first?.domain == "/v1")
    }

    @Test("Uses common multi-part public suffixes for registrable domain grouping")
    func multiPartPublicSuffix() throws {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [
            transaction("https://api.example.co.uk/orders", sequence: 0),
            transaction("https://cdn.example.co.uk/assets/app.js", sequence: 1),
        ]

        coordinator.rebuildSidebarIndexes()

        let root = try #require(coordinator.domainTree.first)
        #expect(root.domain == "example.co.uk")
        #expect(root.children.map(\.domain).contains("api.example.co.uk"))
        #expect(root.children.map(\.domain).contains("cdn.example.co.uk"))
    }

    @Test("Collapses dynamic path segments under an id group")
    func dynamicPathSegments() throws {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [
            transaction("https://api.example.com/users/100", sequence: 0),
            transaction("https://api.example.com/users/200", sequence: 1),
        ]

        coordinator.rebuildSidebarIndexes()

        let root = try #require(coordinator.domainTree.first { $0.domain == "example.com" })
        let host = try #require(root.children.first { $0.domain == "api.example.com" })
        let users = try #require(host.children.first { $0.domain == "/users" })
        let idGroup = try #require(users.children.first)
        #expect(idGroup.domain == "/{id}")
        #expect(idGroup.pathPrefix == "/users/")
        #expect(idGroup.requestCount == 2)
    }

    @Test("App grouping moves an attributed request out of Unknown")
    func appGroupingMovesAttributedRequestOutOfUnknown() throws {
        var index = AppGroupingIndex()
        let request = transaction("https://api.example.com/users/100", sequence: 0)

        index.add(request)
        #expect(index.makeNodes().map(\.name) == [String(localized: "Unknown")])

        request.clientApp = "Safari"
        index.remove(request, appName: String(localized: "Unknown"))
        index.add(request, appName: request.clientApp)

        let node = try #require(index.makeNodes().first)
        #expect(index.makeNodes().count == 1)
        #expect(node.name == "Safari")
        #expect(node.requestCount == 1)
        #expect(node.domains == ["api.example.com"])
    }

    @Test("App grouping keeps a shared domain until its last request is removed")
    func appGroupingReferenceCountsSharedDomains() throws {
        var index = AppGroupingIndex()
        let first = transaction("https://api.example.com/one", sequence: 0)
        let second = transaction("https://api.example.com/two", sequence: 1)

        index.add(first, appName: "Safari")
        index.add(second, appName: "Safari")
        index.remove(first, appName: "Safari")

        var node = try #require(index.makeNodes().first)
        #expect(node.requestCount == 1)
        #expect(node.domains == ["api.example.com"])

        index.remove(second, appName: "Safari")
        #expect(index.makeNodes().isEmpty)
    }

    // MARK: Private

    private func transaction(_ url: String, sequence: Int, statusCode: Int = 200) -> HTTPTransaction {
        let transaction = TestFixtures.makeTransaction(url: url, statusCode: statusCode)
        transaction.sequenceNumber = sequence
        return transaction
    }
}
