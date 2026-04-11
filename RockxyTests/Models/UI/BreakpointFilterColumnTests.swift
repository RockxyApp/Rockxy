import Foundation
@testable import Rockxy
import Testing

// Tests for the `BreakpointFilterColumn` enum.

struct BreakpointFilterColumnTests {
    @Test("All cases are defined — exactly 3")
    func allCasesAreDefined() {
        #expect(BreakpointFilterColumn.allCases.count == 3)
    }

    @Test("Display names are non-empty")
    func displayNamesAreNonEmpty() {
        for column in BreakpointFilterColumn.allCases {
            #expect(!column.displayName.isEmpty, "displayName for \(column) should not be empty")
        }
    }

    @Test("Raw values are unique")
    func rawValuesAreUnique() {
        let rawValues = BreakpointFilterColumn.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count, "Raw values must be unique")
    }
}
