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

    @Test("Add Filter reveals the existing first rule")
    func addFilterRevealsExistingRule() {
        let coordinator = MainContentCoordinator()
        #expect(!coordinator.isFilterBarVisible)
        #expect(coordinator.filterRules.count == 1)

        coordinator.addAdvancedFilterRule()

        #expect(coordinator.isFilterBarVisible)
        #expect(coordinator.filterRules.count == 1)
    }

    @Test("Add Filter appends rules while the editor is visible")
    func addFilterAppendsRule() {
        let coordinator = MainContentCoordinator()
        coordinator.isFilterBarVisible = true

        coordinator.addAdvancedFilterRule()
        coordinator.addAdvancedFilterRule()

        #expect(coordinator.filterRules.count == 3)
        #expect(Set(coordinator.filterRules.map(\.id)).count == 3)
    }

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

    @Test("AI and RPC error protocol filters match captured metadata")
    func smartProtocolFilters() {
        let coordinator = MainContentCoordinator()
        let ai = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.openai.com/v1/responses"
        )
        let rpcError = TestFixtures.makeWeb3RPCTransaction(
            error: Web3RPCError(code: -32_000, message: "rate limited")
        )
        let ordinary = TestFixtures.makeTransaction(url: "https://example.com/test")
        coordinator.transactions = [ai, rpcError, ordinary]

        coordinator.filterCriteria.activeProtocolFilters = [.ai, .rpcError]
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [ai.id, rpcError.id])
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

    @Test("Sidebar domain filter does not match partial host suffixes")
    func sidebarDomainFilterRequiresBoundary() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(url: "https://api.example.com/test")
        let noMatch = TestFixtures.makeTransaction(url: "https://badexample.com/test")
        coordinator.transactions = [match, noMatch]
        coordinator.filterCriteria.sidebarDomain = "example.com"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.count == 1)
        #expect(coordinator.filteredTransactions[0].id == match.id)
    }

    @Test("Sidebar path filter narrows selected domain group")
    func sidebarPathFilter() {
        let coordinator = MainContentCoordinator()
        let users = TestFixtures.makeTransaction(url: "https://api.example.com/v1/users")
        let events = TestFixtures.makeTransaction(url: "https://api.example.com/v1/events")
        let otherPath = TestFixtures.makeTransaction(url: "https://api.example.com/v2/users")
        coordinator.transactions = [users, events, otherPath]
        coordinator.filterCriteria.sidebarDomain = "api.example.com"
        coordinator.filterCriteria.sidebarPathPrefix = "/v1"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [users.id, events.id])
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

    @Test("Filter rules support OR connectors")
    func filterRulesORCombined() {
        let coordinator = MainContentCoordinator()
        let getUsers = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/users")
        let postOrders = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/orders")
        let deleteOther = TestFixtures.makeTransaction(method: "DELETE", url: "https://api.example.com/admin")
        coordinator.transactions = [getUsers, postOrders, deleteOther]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .method, filterOperator: .is, value: "GET"),
            FilterRule(
                isEnabled: true,
                connector: .or,
                field: .method,
                filterOperator: .is,
                value: "POST"
            ),
        ]

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [getUsers.id, postOrders.id])
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

    @Test("Request body filter matches decoded text")
    func requestBodyRule() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(method: "POST")
        match.request.body = Data("{\"token\":\"needle\"}".utf8)
        let noMatch = TestFixtures.makeTransaction(method: "POST")
        noMatch.request.body = Data("{\"token\":\"other\"}".utf8)
        coordinator.transactions = [match, noMatch]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .requestBody, filterOperator: .contains, value: "needle"),
        ]

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [match.id])
    }

    @Test("Response body filter matches decoded text")
    func responseBodyRule() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(statusCode: 200)
        match.response = TestFixtures.makeResponse(body: Data("unsafe-inline".utf8))
        let noMatch = TestFixtures.makeTransaction(statusCode: 200)
        noMatch.response = TestFixtures.makeResponse(body: Data("safe".utf8))
        coordinator.transactions = [match, noMatch]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .responseBody, filterOperator: .contains, value: "unsafe-inline"),
        ]

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [match.id])
    }

    @Test("No-result state keeps filtered rows empty")
    func noResultStateForUnmatchedFilter() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/users"),
            TestFixtures.makeTransaction(url: "https://api.example.com/orders"),
        ]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: "missing-value"),
        ]

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.isEmpty)
        #expect(coordinator.filteredRows.isEmpty)
    }

    @Test("Client app, domain, content type, and cookie fields match")
    func expandedDebugFields() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(url: "https://api.example.com/users")
        match.clientApp = "Google Chrome"
        match.request.contentType = .json
        match.request.headers = [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Cookie", value: "session=abc123"),
        ]
        let noMatch = TestFixtures.makeTransaction(url: "https://other.test/users")
        noMatch.clientApp = "Safari"
        noMatch.request.contentType = .text
        coordinator.transactions = [match, noMatch]
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .clientApp, filterOperator: .contains, value: "Chrome"),
            FilterRule(isEnabled: true, field: .domain, filterOperator: .contains, value: "example.com"),
            FilterRule(isEnabled: true, field: .contentType, filterOperator: .contains, value: "json"),
            FilterRule(isEnabled: true, field: .cookies, filterOperator: .contains, value: "abc123"),
        ]

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [match.id])
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

    // MARK: - Smart Search Tokens

    @Test("Smart search filters AI traffic and applies remaining text")
    func smartSearchAIWithRemainingText() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.openai.com/v1/responses"
        )
        let wrongPath = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.anthropic.com/v1/messages"
        )
        let ordinary = TestFixtures.makeTransaction(url: "https://api.example.com/reports/responses")
        coordinator.transactions = [match, wrongPath, ordinary]
        coordinator.filterCriteria.searchField = .path
        coordinator.filterCriteria.searchText = "is:ai responses"

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [match.id])
    }

    @Test("Smart search filters Web3 RPC method, provider, and errors")
    func smartSearchWeb3Metadata() {
        let coordinator = MainContentCoordinator()
        let match = TestFixtures.makeWeb3RPCTransaction(
            method: nil,
            batch: Web3RPCBatchSummary(
                requestCount: 2,
                web3RequestCount: 2,
                responseCount: 2,
                errorCount: 1,
                methods: ["eth_chainId", "eth_getLogs"]
            ),
            error: Web3RPCError(code: -32_000, message: "rate limited")
        )
        let wrongMethod = TestFixtures.makeWeb3RPCTransaction(
            method: "eth_blockNumber",
            error: Web3RPCError(code: -32_000, message: "rate limited")
        )
        let noError = TestFixtures.makeWeb3RPCTransaction(method: "eth_getLogs")
        coordinator.transactions = [match, wrongMethod, noError]
        coordinator.filterCriteria.searchText = "is:web3 rpc_error:true rpc:eth_getLogs provider:rpc.example.com"

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [match.id])
    }

    @Test("Smart provider search matches AI provider names")
    func smartSearchAIProviderName() {
        let coordinator = MainContentCoordinator()
        let ai = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.openai.com/v1/responses"
        )
        let ordinary = TestFixtures.makeTransaction(url: "https://api.example.com/test")
        coordinator.transactions = [ai, ordinary]
        coordinator.filterCriteria.searchText = "provider:openai"

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.map(\.id) == [ai.id])
    }

    @Test("Smart search finds AI tool calls and streamed responses")
    func smartSearchToolCallsAndStreaming() {
        let coordinator = MainContentCoordinator()
        let toolCall = TestFixtures.makeTransaction(method: "POST", url: "https://api.openai.com/v1/chat/completions")
        toolCall.request.body = Data(#"{"model":"gpt-4o","messages":[]}"#.utf8)
        toolCall.response?.body = Data(
            #"{"choices":[{"message":{"tool_calls":[{"id":"call_1","function":{"name":"lookup"}}]}}]}"#.utf8
        )
        let streamed = TestFixtures.makeTransaction(method: "POST", url: "https://api.anthropic.com/v1/messages")
        streamed.request.body = Data(#"{"model":"claude-sonnet-4-5","stream":true,"messages":[]}"#.utf8)
        let plain = TestFixtures.makeTransaction(method: "POST", url: "https://api.openai.com/v1/responses")
        plain.request.body = Data(#"{"model":"gpt-4o","input":"hi"}"#.utf8)
        coordinator.transactions = [toolCall, streamed, plain]

        coordinator.filterCriteria.searchText = "has:tool_call"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [toolCall.id])

        coordinator.filterCriteria.searchText = "streaming:true"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [streamed.id])

        coordinator.filterCriteria.searchText = "is:ai streaming:false"
        coordinator.recomputeFilteredTransactions()
        #expect(Set(coordinator.filteredTransactions.map(\.id)) == [toolCall.id, plain.id])
    }

    @Test("Smart search matches Web3 chains, transaction hashes, and x402 payment flows")
    func smartSearchChainTxHashAndX402() {
        let coordinator = MainContentCoordinator()
        let mainnet = TestFixtures.makeWeb3RPCTransaction(method: "eth_chainId")
        let broadcast = TestFixtures.makeWeb3RPCTransaction(method: "eth_sendRawTransaction")
        broadcast.web3RPCInfo = Web3RPCInfo(
            family: .evm,
            providerHost: "rpc.example.com",
            method: "eth_sendRawTransaction",
            requestID: "1",
            batch: nil,
            error: nil,
            chainHint: Web3RPCChainHint(chainID: "0x2105"),
            transactionHash: "0xabc",
            blockIdentifier: nil,
            requestPayloadSize: nil,
            responsePayloadSize: nil
        )
        let paywall = TestFixtures.makeTransaction(url: "https://paid.example.com/report", statusCode: 402)
        paywall.x402Info = X402Info(
            stage: .paymentRequired,
            isX402Like: true,
            version: "1",
            paymentRequired: true,
            hasPaymentProof: false,
            hasChallenge: true,
            hasPaymentMetadata: false,
            providerErrorPresent: false,
            parseState: .parsed,
            redactionFields: [],
            requestPayloadSize: nil,
            responsePayloadSize: nil
        )
        coordinator.transactions = [mainnet, broadcast, paywall]

        coordinator.filterCriteria.searchText = "has:tx_hash"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [broadcast.id])

        for query in ["chain:base", "chain:8453", "chain:0x2105"] {
            coordinator.filterCriteria.searchText = query
            coordinator.recomputeFilteredTransactions()
            #expect(coordinator.filteredTransactions.map(\.id) == [broadcast.id], "\(query)")
        }

        coordinator.filterCriteria.searchText = "is:x402"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [paywall.id])
    }

    @Test("streaming: applies to any streamed response, not only AI traffic")
    func streamingAppliesToAllTraffic() {
        let coordinator = MainContentCoordinator()
        let events = TestFixtures.makeTransaction(url: "https://api.example.com/events")
        events.response?.headers = [HTTPHeader(name: "Content-Type", value: "text/event-stream")]
        let page = TestFixtures.makeTransaction(url: "https://www.example.com/index.html")
        coordinator.transactions = [events, page]

        coordinator.filterCriteria.searchText = "streaming:true"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [events.id])

        coordinator.filterCriteria.searchText = "streaming:false"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [page.id])
    }

    @Test("Unknown values for new tokens fall back to plain text search")
    func smartSearchUnknownValues() {
        let filter = SmartTrafficFilter.parse("has:nothing streaming:maybe chain: chain:moonbase hello")
        #expect(!filter.hasPredicates)
        #expect(filter.remainingSearchText == "has:nothing streaming:maybe chain: chain:moonbase hello")
    }

    @Test("Smart model search matches the requested model in the request body")
    func smartSearchAIModel() {
        let coordinator = MainContentCoordinator()
        let gpt = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.openai.com/v1/chat/completions"
        )
        gpt.request.body = Data(#"{"model":"gpt-4o-mini","messages":[]}"#.utf8)
        let claude = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.anthropic.com/v1/messages"
        )
        claude.request.body = Data(#"{"model":"claude-sonnet-4-5","messages":[]}"#.utf8)
        let gemini = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )
        let ordinary = TestFixtures.makeTransaction(url: "https://api.example.com/models/gpt-4o")
        coordinator.transactions = [gpt, claude, gemini, ordinary]

        coordinator.filterCriteria.searchText = "model:gpt-4o"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [gpt.id])

        coordinator.filterCriteria.searchText = "model:gemini"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [gemini.id])

        coordinator.filterCriteria.searchText = "provider:anthropic model:sonnet"
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.filteredTransactions.map(\.id) == [claude.id])
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

    @Test("fieldValue for responseHeader returns joined headers")
    func fieldValueResponseHeader() {
        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction()
        transaction.response = TestFixtures.makeResponse(headers: [
            HTTPHeader(name: "Content-Security-Policy", value: "script-src 'unsafe-inline'"),
        ])
        let value = coordinator.fieldValue(for: .responseHeader, in: transaction)
        #expect(value.contains("Content-Security-Policy"))
        #expect(value.contains("unsafe-inline"))
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

    // MARK: - Selection Across Filters

    @Test("Filtering out the primary row promotes a surviving selected row")
    func filterPromotesSurvivingSelectedRow() {
        let first = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/a")
        let kept = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/b")
        let last = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/c")
        let coordinator = makeCoordinator(transactions: [first, kept, last])
        coordinator.selectTransactions([first.id, kept.id, last.id], primaryID: first.id)
        #expect(coordinator.selectedTransaction?.id == first.id)

        coordinator.filterCriteria.searchField = .method
        coordinator.filterCriteria.searchText = "POST"
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.selectedTransactionIDs == [kept.id])
        #expect(coordinator.selectedTransaction?.id == kept.id)
    }

    @Test("Filtering out every selected row clears the primary row")
    func filterClearsPrimaryWhenNothingSurvives() {
        let first = TestFixtures.makeTransaction(method: "GET", url: "https://api.example.com/a")
        let other = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/b")
        let coordinator = makeCoordinator(transactions: [first, other])
        coordinator.selectTransactions([first.id], primaryID: first.id)

        coordinator.filterCriteria.searchField = .method
        coordinator.filterCriteria.searchText = "POST"
        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.selectedTransactionIDs.isEmpty)
        #expect(coordinator.selectedTransaction == nil)
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

    @Test("Large traffic sessions keep filtered counts correct")
    func largeTrafficSessionFiltering() {
        let coordinator = MainContentCoordinator()
        coordinator.transactions = (0 ..< 5_000).map { index in
            let method = index.isMultiple(of: 2) ? "GET" : "POST"
            return TestFixtures.makeTransaction(method: method, url: "https://api.example.com/items/\(index)")
        }
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .method, filterOperator: .is, value: "POST"),
        ]

        coordinator.recomputeFilteredTransactions()

        #expect(coordinator.filteredTransactions.count == 2_500)
        #expect(coordinator.filteredRows.count == 2_500)
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

    // MARK: - Centralized Filter Reset

    @Test("clearAllWorkspaceFilters clears every filter, focus, and scope field and restores traffic")
    func clearAllWorkspaceFiltersResetsEverything() {
        let coordinator = MainContentCoordinator()
        let saved = TestFixtures.makeTransaction(url: "https://api.example.com/users/1")
        saved.isSaved = true
        let other = TestFixtures.makeTransaction(url: "https://other.com/test")
        coordinator.transactions = [saved, other]

        coordinator.filterCriteria.searchText = "users"
        coordinator.filterCriteria.methods = ["GET"]
        coordinator.filterCriteria.activeProtocolFilters = [.https]
        coordinator.filterCriteria.sidebarDomain = "example.com"
        coordinator.filterCriteria.sidebarScope = .saved
        coordinator.filterCriteria.exactTransactionID = saved.id
        coordinator.sidebarSelection = .allSaved
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: "users"),
        ]
        coordinator.activeWorkspace.activeTrafficSignal = .errors
        let focusSet = FocusSet(name: "API", domain: "example.com")
        coordinator.activeWorkspace.focusSets = [focusSet]
        coordinator.activeWorkspace.activeFocusSetID = focusSet.id
        coordinator.activeWorkspace.mutedTrafficSources = [.host("ads.example.com")]
        coordinator.recomputeFilteredTransactions()
        #expect(coordinator.hasActiveWorkspaceFilters)

        coordinator.clearAllWorkspaceFilters()

        #expect(coordinator.filterCriteria.sidebarScope == .allTraffic)
        #expect(coordinator.filterCriteria.isEmpty)
        #expect(coordinator.sidebarSelection == nil)
        #expect(!coordinator.isFilterBarVisible)
        #expect(coordinator.filterRules.count == 1)
        #expect(coordinator.filterRules[0].value.isEmpty)
        #expect(coordinator.activeWorkspace.activeTrafficSignal == nil)
        #expect(coordinator.activeWorkspace.activeFocusSetID == nil)
        #expect(coordinator.activeWorkspace.activeFocusSet == nil)
        #expect(coordinator.activeWorkspace.mutedTrafficSources.isEmpty)
        #expect(!coordinator.hasActiveWorkspaceFilters)
        #expect(coordinator.filteredTransactions.count == 2)
    }

    @Test("clear capture and filters resets visibility lenses in every workspace")
    func clearCaptureAndFiltersResetsEveryWorkspaceVisibilityLens() async {
        let coordinator = MainContentCoordinator()
        let firstWorkspace = coordinator.activeWorkspace
        let secondWorkspace = coordinator.workspaceStore.createWorkspace(title: "Filtered")
        let focusSet = FocusSet(name: "API", domain: "example.com")

        for workspace in [firstWorkspace, secondWorkspace] {
            workspace.filterCriteria.searchText = "api"
            workspace.filterCriteria.sidebarScope = .saved
            workspace.sidebarSelection = .allSaved
            workspace.isFilterBarVisible = true
            workspace.filterRules = [
                FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: "api"),
            ]
            workspace.activeTrafficSignal = .errors
            workspace.focusSets = [focusSet]
            workspace.activeFocusSetID = focusSet.id
            workspace.mutedTrafficSources = [.host("noise.example.com")]
        }

        await coordinator.clearCaptureAndFilters()

        for workspace in [firstWorkspace, secondWorkspace] {
            #expect(workspace.filterCriteria.isEmpty)
            #expect(workspace.filterCriteria.sidebarScope == .allTraffic)
            #expect(workspace.sidebarSelection == nil)
            #expect(!workspace.isFilterBarVisible)
            #expect(workspace.filterRules.count == 1)
            #expect(workspace.filterRules[0].value.isEmpty)
            #expect(workspace.activeTrafficSignal == nil)
            #expect(workspace.activeFocusSetID == nil)
            #expect(workspace.mutedTrafficSources.isEmpty)
            #expect(workspace.focusSets == [focusSet])
        }

        let fresh = TestFixtures.makeTransaction(url: "https://fresh.example.net/new")
        coordinator.processActiveProjectTestBatch([fresh])

        #expect(firstWorkspace.filteredTransactions.map(\.id) == [fresh.id])
        #expect(secondWorkspace.filteredTransactions.map(\.id) == [fresh.id])
    }

    @Test("Editing an active Focus Set refreshes every workspace that uses it")
    func editingFocusSetRefreshesOtherWorkspaces() {
        let coordinator = MainContentCoordinator()
        let api = TestFixtures.makeTransaction(url: "https://api.example.com/data")
        let web = TestFixtures.makeTransaction(url: "https://www.example.com/home")
        coordinator.transactions = [api, web]
        coordinator.recomputeFilteredTransactions()

        let second = coordinator.workspaceStore.createWorkspace(title: "Second")
        coordinator.recomputeFilteredTransactions(for: second)

        var focusSet = FocusSet(name: "Target", domain: "api.example.com")
        coordinator.saveFocusSet(focusSet)
        second.activeFocusSetID = focusSet.id
        coordinator.recomputeFilteredTransactions(for: second)
        #expect(second.filteredTransactions.map(\.id) == [api.id])

        focusSet.domain = "www.example.com"
        coordinator.saveFocusSet(focusSet)

        #expect(second.filteredTransactions.map(\.id) == [web.id])
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
