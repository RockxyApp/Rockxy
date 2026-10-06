import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

struct HeaderModifyPresetsTests {
    @Test("CORS preset covers preflight headers and replaces values the origin already sent")
    func corsPresetReplacesAndCoversPreflight() throws {
        let rule = HeaderModifyPresets.corsHeaders()
        guard case let .modifyHeader(operations) = rule.action else {
            Issue.record("expected a modify-header action")
            return
        }
        let names = Set(operations.map { $0.headerName.lowercased() })
        #expect(names.isSuperset(of: [
            "access-control-allow-origin",
            "access-control-allow-methods",
            "access-control-allow-headers",
        ]))
        #expect(operations.allSatisfy { $0.type == .replace && $0.phase == .response })

        var headers = HTTPHeaders([("Access-Control-Allow-Origin", "https://app.example.com")])
        HeaderMutator.apply(operations, to: &headers)
        #expect(headers["Access-Control-Allow-Origin"] == ["*"])
        #expect(headers["Access-Control-Allow-Methods"].count == 1)
    }
}
