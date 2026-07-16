@testable import Rockxy
import Testing

struct StatusBarRequestSummaryTests {
    @Test("Unfiltered summaries preserve the compact existing copy")
    func unfilteredSummary() {
        #expect(StatusBarRequestSummary.text(
            visibleCount: 238,
            availableCount: 238,
            selectedCount: 0,
            activeFilterCount: 0
        ) == "238 requests")
        #expect(StatusBarRequestSummary.text(
            visibleCount: 0,
            availableCount: 0,
            selectedCount: 0,
            activeFilterCount: 0
        ) == "No requests")
    }

    @Test("Active filters distinguish visible and available request counts")
    func filteredSummary() {
        #expect(StatusBarRequestSummary.text(
            visibleCount: 5,
            availableCount: 238,
            selectedCount: 0,
            activeFilterCount: 1
        ) == "5 of 238 requests")
        #expect(StatusBarRequestSummary.text(
            visibleCount: 5,
            availableCount: 238,
            selectedCount: 2,
            activeFilterCount: 1
        ) == "2 selected · 5 of 238 shown")
        #expect(StatusBarRequestSummary.text(
            visibleCount: 238,
            availableCount: 238,
            selectedCount: 0,
            activeFilterCount: 1
        ) == "238 requests")
    }
}
