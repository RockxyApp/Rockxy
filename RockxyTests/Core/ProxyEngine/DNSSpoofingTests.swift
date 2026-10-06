import Foundation
@testable import Rockxy
import Testing

// MARK: - DNSSpoofingTableTests

struct DNSSpoofingTableTests {
    @Test("Exact and wildcard hosts resolve to their address; the first match wins")
    func matching() {
        let table = DNSSpoofingTable()
        table.update([
            DNSSpoofingEntry(hostPattern: "api.example.com", address: "10.0.0.5"),
            DNSSpoofingEntry(hostPattern: "*.example.com", address: "staging.example.net"),
        ])
        #expect(table.address(for: "API.example.com") == "10.0.0.5")
        #expect(table.address(for: "cdn.example.com") == "staging.example.net")
        #expect(table.address(for: "example.org") == nil)
        #expect(UpstreamConnectHost.resolve(for: "example.org", clientHost: "127.0.0.1", table: table) == "example.org")
        #expect(UpstreamConnectHost.resolve(for: "api.example.com", clientHost: nil, table: table) == "10.0.0.5")

        table.update([])
        #expect(table.address(for: "api.example.com") == nil)
    }
}

// MARK: - DNSSpoofingRuleValidatorTests

struct DNSSpoofingRuleValidatorTests {
    @Test("Valid rules pass; malformed hosts and addresses are explained")
    func validation() {
        func problem(_ host: String, _ address: String, others: [DNSSpoofingRule] = []) -> String? {
            DNSSpoofingRuleValidator.problem(with: DNSSpoofingRule(host: host, address: address), among: others)
        }
        #expect(problem("api.example.com", "10.0.0.5") == nil)
        #expect(problem("*.example.com", "staging.example.net") == nil)
        #expect(problem("api.example.com", "2001:db8::1") == nil)
        #expect(problem("api.example.com", "[2001:db8::1]") == nil)
        #expect(problem("", "10.0.0.5") != nil)
        #expect(problem("https://api.example.com", "10.0.0.5") != nil)
        #expect(problem("api.example.com:443", "10.0.0.5") != nil)
        #expect(problem("api.example.com", "") != nil)
        #expect(problem("api.example.com", "10.0.0.5:8080") != nil)
        #expect(problem("api.example.com", "http://10.0.0.5") != nil)
        #expect(problem("api.example.com", "*.example.net") != nil)
        #expect(problem("api.example.com", "API.example.com") != nil)
        #expect(problem("api.example.com", "10.0.0.6", others: [DNSSpoofingRule(host: "api.example.com", address: "10.0.0.5")]) != nil)
    }

    @Test("An editor can leave empty fields unreported while still flagging real mistakes")
    func missingFieldsAreQuiet() {
        func quiet(_ host: String, _ address: String) -> String? {
            DNSSpoofingRuleValidator.problem(
                with: DNSSpoofingRule(host: host, address: address),
                among: [],
                reportsMissingFields: false
            )
        }
        #expect(quiet("", "") == nil)
        #expect(quiet("api.example.com", "") == nil)
        #expect(quiet("", "10.0.0.5") == nil)
        #expect(quiet("https://api.example.com", "") != nil)
        #expect(quiet("api.example.com", "http://10.0.0.5") != nil)
    }
}

// MARK: - DNSSpoofingStoreTests

@MainActor
struct DNSSpoofingStoreTests {
    @Test("Enabled rules drive the table and survive a relaunch")
    func storeDrivesTable() {
        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.DNSSpoofingStoreTests")
        let table = DNSSpoofingTable()
        let store = DNSSpoofingStore(defaults: defaults, table: table)
        let rule = DNSSpoofingRule(host: "api.example.com", address: " 10.0.0.5 ")
        store.upsert(rule)
        #expect(table.address(for: "api.example.com") == "10.0.0.5")

        store.setEnabled(false, id: rule.id)
        #expect(table.address(for: "api.example.com") == nil)

        let relaunchedTable = DNSSpoofingTable()
        let relaunched = DNSSpoofingStore(defaults: defaults, table: relaunchedTable)
        #expect(relaunched.rules.count == 1)
        relaunched.setEnabled(true, id: rule.id)
        #expect(relaunchedTable.address(for: "api.example.com") == "10.0.0.5")

        relaunched.remove(ids: [rule.id])
        #expect(relaunchedTable.address(for: "api.example.com") == nil)
    }
}
