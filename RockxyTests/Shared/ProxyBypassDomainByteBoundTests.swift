import Foundation
@testable import Rockxy
import Testing

struct ProxyBypassDomainByteBoundTests {
    @Test("the count cap alone still admits a list the command layer could not read back")
    func countCapDoesNotBoundTheReply() {
        // 500 domains — the helper's documented maximum — each at the 253-character maximum.
        let domains = Array(repeating: String(repeating: "a", count: 253), count: 500)
        #expect(domains.allSatisfy(ProxyBypassDomainValidator.isValid))
        #expect(domains.reduce(0) { $0 + $1.utf8.count + 1 } > 65_536)
        #expect(!ProxyBypassDomainValidator.fitsTotalByteBound(domains))
    }

    @Test("every accepted list stays inside what the command runner will read")
    func acceptedListsFitTheCommandBudget() {
        let domains = Array(repeating: String(repeating: "a", count: 127), count: 512)
        #expect(domains.reduce(0) { $0 + $1.utf8.count + 1 } == ProxyBypassDomainValidator.maximumTotalBytes)
        #expect(ProxyBypassDomainValidator.fitsTotalByteBound(domains))
        #expect(ProxyBypassDomainValidator.maximumTotalBytes < BoundedHelperCommand.standardOutputLimit)
    }

    @Test("one byte past the bound is rejected")
    func rejectsOneBytePastTheBound() {
        var domains = Array(repeating: String(repeating: "a", count: 127), count: 512)
        domains.append("a")
        #expect(!ProxyBypassDomainValidator.fitsTotalByteBound(domains))
    }

    @Test("a realistic bypass list is nowhere near the bound")
    func realisticListsAreUnaffected() {
        let domains = (0 ..< 500).map { "service-\($0).internal.example.com" }
        #expect(ProxyBypassDomainValidator.fitsTotalByteBound(domains))
    }
}
