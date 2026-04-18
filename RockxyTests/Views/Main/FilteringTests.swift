import Foundation
@testable import Rockxy
import Testing

// Regression tests for `Filtering` in the views main layer.

// MARK: - FilteringTests

@MainActor
struct FilteringTests {
    // MARK: Internal

    // MARK: - No Filters

    @Test("No filters returns all non-TLS transactions")
    func noFiltersReturnsAll() {
        let coordinator = makeCoordinator()
        #expect(coordinator.filteredTransactions.count == coordinator.transactions.count)
    }

    @Test("TLS failures always excluded")
    func tlsFailuresExcluded() {
        let coordinator = MainContentCoordinator()
        let normal = TestFixtures.makeTransaction()
        let tlsFail = TestFixtures.makeTransaction()
        tlsFail.isTLSFailure = true
        coordinator.transactions = [normal, tlsFail]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == normal.id)
    }

    @Test("successful CONNECT passthrough remains visible")
    func successfulConnectPassthroughVisible() {
        let coordinator = MainContentCoordinator()
        let connect = TLSInterceptHandler.makeTunnelTransaction(
            host: "example.com",
            port: 443,
            statusCode: 200,
            statusMessage: "Connection Established",
            state: .completed,
            sourcePort: 54_321
        )
        let tlsFail = TLSInterceptHandler.makeTunnelTransaction(
            host: "bad.example.com",
            port: 443,
            statusCode: 0,
            statusMessage: "TLS Handshake Failed",
            state: .failed,
            sourcePort: 54_322,
            isTLSFailure: true
        )

        coordinator.transactions = [connect, tlsFail]
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].request.method == "CONNECT")
        #expect(coordinator.filteredTransactions[0].isTLSFailure == false)
    }

    // MARK: - Search by Field

    @Test("Search by URL field matches URL substring")
    func searchByURL() {
        let coordinator = makeCoordinator()
        coordinator.filterCriteria.searchField = .url
        coordinator.filterCriteria.searchText = "users"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.allSatisfy {
            $0.request.url.absoluteString.lowercased().contains("users")
        })
    }

    @Test("Search by host field matches host")
    func searchByHost() {
        let coordinator = makeCoordinator()
        coordinator.filterCriteria.searchField = .host
        coordinator.filterCriteria.searchText = "api.example.com"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.allSatisfy {
            $0.request.host.lowercased().contains("api.example.com")
        })
    }

    @Test("Search by path field matches path only")
    func searchByPath() {
        let coordinator = makeCoordinator()
        coordinator.filterCriteria.searchField = .path
        coordinator.filterCriteria.searchText = "/users"
        coordinator.recomputeFilteredTransactions()
        #expect(!coordinator.filteredTransactions.isEmpty)
        #expect(coordinator.filteredTransactions.allSatisfy {
            $0.request.path.lowercased().contains("/users")
        })
    }

    @Test("Search by method field matches method")
    func searchByMethod() {
        let coordinator = makeCoordinator()
        coordinator.filterCriteria.searchField = .method
        coordinator.filterCriteria.searchText = "POST"
        coordinator.recomputeFilteredTransactions()
        #expect(!coordinator.filteredTransactions.isEmpty)
        #expect(coordinator.filteredTransactions.allSatisfy {
            $0.request.method == "POST"
        })
    }

    // MARK: - isSearchEnabled Toggle

    @Test("Disabling search ignores search text")
    func disabledSearchIgnoresText() {
        let coordinator = makeCoordinator()
        coordinator.filterCriteria.searchText = "nonexistent_gibberish_xyz"
        coordinator.filterCriteria.isSearchEnabled = true
        coordinator.recomputeFilteredTransactions()
        let filteredCount = coordinator.filteredTransactions.count

        coordinator.filterCriteria.isSearchEnabled = false
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count > filteredCount)
        #expect(coordinator.filteredTransactions.count == coordinator.transactions.count)
    }

    // MARK: - Protocol Filters

    @Test("Protocol content filters use OR logic within group")
    func protocolContentFiltersOR() {
        let coordinator = MainContentCoordinator()
        let httpTransaction = TestFixtures.makeTransaction(url: "http://example.com/test")
        let httpsTransaction = TestFixtures.makeTransaction(url: "https://example.com/test")
        coordinator.transactions = [httpTransaction, httpsTransaction]
        coordinator.filterCriteria.activeProtocolFilters = [.http]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == httpTransaction.id)
    }

    @Test("Protocol status filters use OR logic within group")
    func protocolStatusFiltersOR() {
        let coordinator = MainContentCoordinator()
        let ok = TestFixtures.makeTransaction(statusCode: 200)
        let notFound = TestFixtures.makeTransaction(statusCode: 404)
        let error = TestFixtures.makeErrorTransaction(statusCode: 500)
        coordinator.transactions = [ok, notFound, error]
        coordinator.filterCriteria.activeProtocolFilters = [.status2xx, .status4xx]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 2)
    }

    @Test("Content and status filters combined with AND")
    func contentAndStatusFiltersAND() {
        let coordinator = MainContentCoordinator()
        let httpsOk = TestFixtures.makeTransaction(url: "https://example.com/test", statusCode: 200)
        let httpOk = TestFixtures.makeTransaction(url: "http://example.com/test", statusCode: 200)
        let httpsError = TestFixtures.makeTransaction(url: "https://example.com/test", statusCode: 500)
        coordinator.transactions = [httpsOk, httpOk, httpsError]
        coordinator.filterCriteria.activeProtocolFilters = [.https, .status2xx]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == httpsOk.id)
    }

    // MARK: - Sidebar Filters

    @Test("Sidebar domain filters by suffix match")
    func sidebarDomainFilter() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(url: "https://api.example.com/test")
        let noMatch = TestFixtures.makeTransaction(url: "https://other.com/test")
        coordinator.transactions = [match, noMatch]
        coordinator.filterCriteria.sidebarDomain = "example.com"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == match.id)
    }

    @Test("Sidebar app filters by exact match")
    func sidebarAppFilter() {
        let coordinator = MainContentCoordinator()
        let safari = TestFixtures.makeTransaction()
        safari.clientApp = "Safari"
        let chrome = TestFixtures.makeTransaction()
        chrome.clientApp = "Chrome"
        coordinator.transactions = [safari, chrome]
        coordinator.filterCriteria.sidebarApp = "Safari"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].clientApp == "Safari")
    }

    // MARK: - Filter Rules

    @Test("Filter rules are AND-combined")
    func filterRulesANDCombined() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/users/1")
        let noMatch = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/users/1")
        coordinator.transactions = [match, noMatch]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: "users"),
            FilterRule(isEnabled: true, field: .method, filterOperator: .is, value: "GET"),
        ]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == match.id)
    }

    @Test("Disabled rules are ignored")
    func disabledRulesIgnored() {
        let coordinator = makeCoordinator()
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: false, field: .url, filterOperator: .contains, value: "nonexistent_xyz"),
        ]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == coordinator.transactions.count)
    }

    @Test("Rules only apply when filter bar is visible")
    func rulesRequireFilterBarVisible() {
        let coordinator = makeCoordinator()
        coordinator.isFilterBarVisible = false
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: "nonexistent_xyz"),
        ]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == coordinator.transactions.count)
    }

    // MARK: - New Field Cases

    @Test("fieldValue for statusCode returns status string")
    func fieldValueStatusCode() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction(statusCode: 404)
        let value = coordinator.fieldValue(for: .statusCode, in: transaction)
        #expect(value == "404")
    }

    @Test("fieldValue for requestHeader returns joined headers")
    func fieldValueRequestHeader() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        let value = coordinator.fieldValue(for: .requestHeader, in: transaction)
        #expect(value.contains("Content-Type"))
        #expect(value.contains("application/json"))
    }

    @Test("fieldValue for queryString returns query")
    func fieldValueQueryString() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction(url: "https://example.com/search?q=test&page=1")
        let value = coordinator.fieldValue(for: .queryString, in: transaction)
        #expect(value.contains("q=test"))
        #expect(value.contains("page=1"))
    }

    @Test("fieldValue for comment returns comment")
    func fieldValueComment() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.comment = "Test comment"
        let value = coordinator.fieldValue(for: .comment, in: transaction)
        #expect(value == "Test comment")
    }

    @Test("fieldValue for color returns color rawValue")
    func fieldValueColor() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.highlightColor = .red
        let value = coordinator.fieldValue(for: .color, in: transaction)
        #expect(value == "red")
    }

    // MARK: - New Operators in Rules

    @Test("NotEqual operator works in filter rules")
    func notEqualInRules() {
        let coordinator = MainContentCoordinator()
        let get = TestFixtures.makeTransaction(method: "GET")
        let post = TestFixtures.makeTransaction(method: "POST")
        coordinator.transactions = [get, post]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .method, filterOperator: .notEqual, value: "GET"),
        ]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].request.method == "POST")
    }

    @Test("Regex operator works in filter rules")
    func regexInRules() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(url: "https://api.example.com/users/123")
        let noMatch = TestFixtures.makeTransaction(url: "https://api.example.com/users/abc")
        coordinator.transactions = [match, noMatch]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .url, filterOperator: .regex, value: "/users/\\d+$"),
        ]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == match.id)
    }

    // MARK: - Append Fast Path

    @Test("appendFilteredTransactions fast path when no filters active")
    func appendFastPath() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = []
        coordinator.filteredTransactions = []
        let batch = [TestFixtures.makeTransaction(), TestFixtures.makeTransaction()]
        coordinator.transactions.append(contentsOf: batch)
        coordinator.appendFilteredTransactions(batch)
        #expect(coordinator.filteredTransactions.count == 2)
    }

    @Test("appendFilteredTransactions recomputes when filters active")
    func appendRecomputes() {
        let coordinator = MainContentCoordinator()
        let existing = TestFixtures.makeTransaction(url: "https://api.example.com/users/1")
        coordinator.transactions = [existing]
        coordinator.filterCriteria.searchText = "users"
        coordinator.recomputeFilteredTransactions()

        let newMatch = TestFixtures.makeTransaction(url: "https://api.example.com/users/2")
        let newNoMatch = TestFixtures.makeTransaction(url: "https://api.example.com/posts/1")
        coordinator.transactions.append(contentsOf: [newMatch, newNoMatch])
        coordinator.appendFilteredTransactions([newMatch, newNoMatch])
        #expect(coordinator.filteredTransactions.count == 2)
        #expect(coordinator.filteredTransactions.allSatisfy {
            $0.request.url.absoluteString.contains("users")
        })
    }

    // MARK: - Sidebar Scope

    @Test("allApps resets scope to allTraffic and shows all transactions")
    func allAppsResetsToAllTraffic() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(url: "https://api.example.com/test")
        let noMatch = TestFixtures.makeTransaction(url: "https://other.com/test")
        coordinator.transactions = [match, noMatch]
        coordinator.filterCriteria.sidebarDomain = "other.com"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)

        coordinator.selectSidebarItem(.allApps)
        #expect(coordinator.filterCriteria.sidebarScope == .allTraffic)
        #expect(coordinator.filterCriteria.sidebarDomain == nil)
        #expect(coordinator.filteredTransactions.count == 2)
    }

    @Test("allDomains resets scope to allTraffic and shows all transactions")
    func allDomainsResetsToAllTraffic() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(url: "https://api.example.com/test")
        let noMatch = TestFixtures.makeTransaction(url: "https://other.com/test")
        coordinator.transactions = [match, noMatch]
        coordinator.filterCriteria.sidebarDomain = "other.com"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)

        coordinator.selectSidebarItem(.allDomains)
        #expect(coordinator.filterCriteria.sidebarScope == .allTraffic)
        #expect(coordinator.filterCriteria.sidebarDomain == nil)
        #expect(coordinator.filteredTransactions.count == 2)
    }

    @Test("allSaved shows only saved transactions")
    func allSavedShowsSavedOnly() {
        let coordinator = MainContentCoordinator()
        let normal = TestFixtures.makeTransaction()
        let saved = TestFixtures.makeTransaction()
        saved.isSaved = true
        let pinned = TestFixtures.makeTransaction()
        pinned.isPinned = true
        coordinator.transactions = [normal, saved, pinned]

        coordinator.selectSidebarItem(.allSaved)
        #expect(coordinator.filterCriteria.sidebarScope == .saved)
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == saved.id)
    }

    @Test("allPinned shows only pinned transactions")
    func allPinnedShowsPinnedOnly() {
        let coordinator = MainContentCoordinator()
        let normal = TestFixtures.makeTransaction()
        let saved = TestFixtures.makeTransaction()
        saved.isSaved = true
        let pinned = TestFixtures.makeTransaction()
        pinned.isPinned = true
        coordinator.transactions = [normal, saved, pinned]

        coordinator.selectSidebarItem(.allPinned)
        #expect(coordinator.filterCriteria.sidebarScope == .pinned)
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == pinned.id)
    }

    @Test("Saved scope respects search text filter")
    func savedScopeRespectsSearch() {
        let coordinator = MainContentCoordinator()
        let savedMatch = TestFixtures.makeTransaction(url: "https://api.example.com/users/1")
        savedMatch.isSaved = true
        let savedNoMatch = TestFixtures.makeTransaction(url: "https://api.example.com/posts/1")
        savedNoMatch.isSaved = true
        let unsaved = TestFixtures.makeTransaction(url: "https://api.example.com/users/2")
        coordinator.transactions = [savedMatch, savedNoMatch, unsaved]

        coordinator.selectSidebarItem(.allSaved)
        coordinator.filterCriteria.searchText = "users"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == savedMatch.id)
    }

    @Test("Selecting a leaf app resets scope to allTraffic")
    func leafAppResetsScope() {
        let coordinator = MainContentCoordinator()
        let safari = TestFixtures.makeTransaction()
        safari.clientApp = "Safari"
        safari.isSaved = true
        let chrome = TestFixtures.makeTransaction()
        chrome.clientApp = "Chrome"
        coordinator.transactions = [safari, chrome]

        coordinator.selectSidebarItem(.allSaved)
        #expect(coordinator.filterCriteria.sidebarScope == .saved)

        coordinator.selectSidebarItem(.app(name: "Safari", bundleId: nil))
        #expect(coordinator.filterCriteria.sidebarScope == .allTraffic)
        #expect(coordinator.filterCriteria.sidebarApp == "Safari")
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].clientApp == "Safari")
    }

    @Test("Clearing selection returns to allTraffic scope")
    func clearingScopeReturnsToAllTraffic() {
        let coordinator = MainContentCoordinator()
        let saved = TestFixtures.makeTransaction()
        saved.isSaved = true
        let normal = TestFixtures.makeTransaction()
        coordinator.transactions = [saved, normal]

        coordinator.selectSidebarItem(.allSaved)
        #expect(coordinator.filterCriteria.sidebarScope == .saved)
        #expect(coordinator.filteredTransactions.count == 1)

        coordinator.selectSidebarItem(nil)
        #expect(coordinator.filterCriteria.sidebarScope == .allTraffic)
        #expect(coordinator.filteredTransactions.count == 2)
    }

    // MARK: - Combined Filters

    @Test("Combined search + protocol + rules")
    func combinedFilters() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/users/1",
            statusCode: 200
        )
        let wrongMethod = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.example.com/users/2",
            statusCode: 200
        )
        let wrongStatus = TestFixtures.makeTransaction(
            method: "GET",
            url: "https://api.example.com/users/3",
            statusCode: 404
        )
        coordinator.transactions = [match, wrongMethod, wrongStatus]

        coordinator.filterCriteria.searchText = "users"
        coordinator.filterCriteria.activeProtocolFilters = [.status2xx]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .method, filterOperator: .is, value: "GET"),
        ]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == match.id)
    }

    // MARK: Private

    // MARK: - Setup

    private func makeCoordinator(transactions: [HTTPTransaction]? = nil) -> MainContentCoordinator {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = transactions ?? TestFixtures.makeBulkTransactions(count: 20)
        coordinator.recomputeFilteredTransactions()
        return coordinator
    }
}
