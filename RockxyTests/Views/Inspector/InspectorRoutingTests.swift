import Foundation
@testable import Rockxy
import Testing

/// Tests for the extracted protocol-routing/defaulting logic used by ResponseInspectorView.
/// These cover ProtocolTabKind.defaultFor(...) and state transition sequences.
/// Actual SwiftUI lifecycle behavior (.task(id:) firing, tab-button interaction) is not
/// covered by this suite. Those behaviors remain manual verification scope for now.
struct InspectorRoutingTests {
    // MARK: - Model Facts

    @Test("HTTP transaction has no WebSocket connection")
    func httpTransactionNoWebSocket() {
        let transaction = TestFixtures.makeTransaction()
        #expect(transaction.webSocketConnection == nil)
        #expect(transaction.graphQLInfo == nil)
    }

    @Test("WebSocket transaction has WebSocket connection")
    func webSocketTransactionHasConnection() throws {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(transaction.webSocketConnection != nil)
        #expect(try #require(transaction.webSocketConnection?.frameCount) > 0)
    }

    @Test("GraphQL transaction has GraphQL info")
    func graphQLTransactionHasInfo() {
        let transaction = TestFixtures.makeGraphQLTransaction()
        #expect(transaction.graphQLInfo != nil)
        #expect(transaction.graphQLInfo?.operationType == .query)
    }

    @Test("WebSocket transaction preserves HTTP response for handshake inspection")
    func webSocketPreservesHTTPResponse() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(transaction.response != nil)
        #expect(transaction.response?.statusCode == 101)
    }

    @Test("WebSocket transaction preserves HTTP request for upgrade headers")
    func webSocketPreservesHTTPRequest() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(transaction.request.method == "GET")
        #expect(transaction.request.url.scheme == "wss")
    }

    // MARK: - Protocol Tab Selection Behavior (via ProtocolTabKind.defaultFor)

    @Test("WebSocket transaction defaults to .websocket protocol tab")
    func wsDefaultsToWebSocketTab() {
        let tx = TestFixtures.makeWebSocketTransaction()
        let tab = ProtocolTabKind.defaultFor(tx)
        #expect(tab == .websocket)
    }

    @Test("GraphQL transaction defaults to .graphql protocol tab")
    func gqlDefaultsToGraphQLTab() {
        let tx = TestFixtures.makeGraphQLTransaction()
        let tab = ProtocolTabKind.defaultFor(tx)
        #expect(tab == .graphql)
    }

    @Test("Plain HTTP transaction defaults to nil protocol tab")
    func httpDefaultsToNilTab() {
        let tx = TestFixtures.makeTransaction()
        let tab = ProtocolTabKind.defaultFor(tx)
        #expect(tab == nil)
    }

    @Test("Switching WS → HTTP clears protocol tab")
    func wsToHttpClearsProtocol() {
        let wsTx = TestFixtures.makeWebSocketTransaction()
        let httpTx = TestFixtures.makeTransaction()

        // Simulate: first select WS
        var protocolTab = ProtocolTabKind.defaultFor(wsTx)
        #expect(protocolTab == .websocket)

        // Then select HTTP
        protocolTab = ProtocolTabKind.defaultFor(httpTx)
        #expect(protocolTab == nil)
    }

    @Test("Switching HTTP → WS re-enables protocol tab")
    func httpToWsReEnablesProtocol() {
        let httpTx = TestFixtures.makeTransaction()
        let wsTx = TestFixtures.makeWebSocketTransaction()

        var protocolTab = ProtocolTabKind.defaultFor(httpTx)
        #expect(protocolTab == nil)

        protocolTab = ProtocolTabKind.defaultFor(wsTx)
        #expect(protocolTab == .websocket)
    }

    @Test("Switching WS → HTTP → WS resets and re-enables correctly")
    func wsHttpWsTransition() {
        let ws1 = TestFixtures.makeWebSocketTransaction()
        let http = TestFixtures.makeTransaction()
        let ws2 = TestFixtures.makeWebSocketTransaction()

        var tab = ProtocolTabKind.defaultFor(ws1)
        #expect(tab == .websocket)

        tab = ProtocolTabKind.defaultFor(http)
        #expect(tab == nil)

        tab = ProtocolTabKind.defaultFor(ws2)
        #expect(tab == .websocket)
    }

    @Test("Switching WS → GraphQL transitions protocol tab correctly")
    func wsToGraphQLTransition() {
        let ws = TestFixtures.makeWebSocketTransaction()
        let gql = TestFixtures.makeGraphQLTransaction()

        var tab = ProtocolTabKind.defaultFor(ws)
        #expect(tab == .websocket)

        tab = ProtocolTabKind.defaultFor(gql)
        #expect(tab == .graphql)
    }

    @Test("Manual switch to nil preserves until next transaction change")
    func manualSwitchPreserved() {
        let ws = TestFixtures.makeWebSocketTransaction()

        // Auto-select on first appearance
        var protocolTab = ProtocolTabKind.defaultFor(ws)
        #expect(protocolTab == .websocket)

        // User manually clicks Headers tab — clears protocol tab
        protocolTab = nil
        #expect(protocolTab == nil)

        // Same transaction — manual choice should be preserved
        // (autoSelectProtocolTab only fires on transaction CHANGE, not same transaction)
        // The nil state remains until the transaction id changes
        #expect(protocolTab == nil)

        // Different transaction triggers auto-select again
        let ws2 = TestFixtures.makeWebSocketTransaction()
        protocolTab = ProtocolTabKind.defaultFor(ws2)
        #expect(protocolTab == .websocket)
    }

    @Test("CONNECT tunnel shows domain and app SSL prompt actions")
    func connectTunnelShowsSSLPromptActions() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )
        transaction.clientApp = "Brave Browser Helper"

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            sslProxyingEnabled: true,
            canInterceptHTTPS: true,
            domainRuleEnabled: false,
            appName: transaction.clientApp,
            appDomains: ["api.example.com", "cdn.example.com"]
        )

        #expect(prompt?.title == "HTTPS Response")
        #expect(prompt?.primaryTitle == "Enable only this domain")
        #expect(prompt?.primaryAction == .enableDomain("api.example.com"))
        #expect(prompt?.secondaryTitle == "Enable all domains from \"Brave Browser Helper\"")
        #expect(prompt?.secondaryAction == .enableApp("Brave Browser Helper"))
    }

    @Test("CONNECT tunnel prefers certificate guidance when HTTPS interception is unavailable")
    func connectTunnelShowsCertificateGuidance() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            sslProxyingEnabled: true,
            canInterceptHTTPS: false,
            domainRuleEnabled: false,
            appName: nil,
            appDomains: []
        )

        #expect(prompt?.primaryAction == .installCertificate)
        #expect(prompt?.secondaryAction == nil)
    }

    @Test("CONNECT tunnel with existing SSL rule shows retry guidance")
    func connectTunnelWithExistingRuleShowsRetryGuidance() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            sslProxyingEnabled: true,
            canInterceptHTTPS: true,
            domainRuleEnabled: true,
            appName: nil,
            appDomains: []
        )

        #expect(prompt?.primaryAction == .openSSLProxyingList)
        #expect(prompt?.secondaryAction == nil)
    }

    @Test("CONNECT tunnel shows alternate message when SSL proxying is globally off")
    func connectTunnelShowsSSLDisabledMessage() {
        let transaction = TestFixtures.makeTransaction(
            method: "CONNECT",
            url: "https://api.example.com:443",
            statusCode: 200
        )
        transaction.clientApp = "Brave Browser Helper"

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            sslProxyingEnabled: false,
            canInterceptHTTPS: true,
            domainRuleEnabled: false,
            appName: transaction.clientApp,
            appDomains: ["api.example.com"]
        )

        #expect(prompt?.message == "SSL Proxying is off. Enable it to see the encrypted content.")
    }

    @Test("Plain HTTP response does not show HTTPS prompt")
    func plainHTTPDoesNotShowHTTPSPrompt() {
        let transaction = TestFixtures.makeTransaction()

        let prompt = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            sslProxyingEnabled: true,
            canInterceptHTTPS: true,
            domainRuleEnabled: false,
            appName: nil,
            appDomains: []
        )

        #expect(prompt == nil)
    }

    // MARK: - Frame Version

    @Test("webSocketFrameVersion starts at zero")
    func frameVersionStartsAtZero() {
        let transaction = TestFixtures.makeTransaction()
        #expect(transaction.webSocketFrameVersion == 0)
    }

    @Test("webSocketFrameVersion is writable")
    func frameVersionWritable() {
        let transaction = TestFixtures.makeWebSocketTransaction()
        #expect(transaction.webSocketFrameVersion == 0)
        transaction.webSocketFrameVersion += 1
        #expect(transaction.webSocketFrameVersion == 1)
    }
}
