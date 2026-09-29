import AppKit
import Foundation
@testable import Rockxy
import Testing

// MARK: - RequestListModificationMarkerTests

struct RequestListModificationMarkerTests {
    @Test("Rows summarize the rule and scripts that changed an exchange")
    func summary() {
        let untouched = TestFixtures.makeTransaction()
        #expect(RequestListRow(from: untouched).modificationSummary == nil)

        let mocked = TestFixtures.makeTransaction()
        mocked.matchedRuleName = "User mock"
        mocked.matchedRuleActionSummary = "Map Local (user.json)"
        mocked.appliedScriptNames = ["Add CORS"]
        #expect(RequestListRow(from: mocked).modificationSummary == "User mock — Map Local (user.json)\nAdd CORS")
    }

    @MainActor
    @Test("Modified rows lead the URL with a marker and keep the address text")
    func markerString() {
        let string = RequestTableView.Coordinator.modifiedURLString(
            "api.example.com/users",
            font: .monospacedSystemFont(ofSize: 12, weight: .regular)
        )

        #expect(string.string.hasSuffix(" api.example.com/users"))
        #expect(string.attribute(.attachment, at: 0, effectiveRange: nil) != nil)
    }
}
