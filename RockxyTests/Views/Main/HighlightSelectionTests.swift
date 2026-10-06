import AppKit
import Foundation
@testable import Rockxy
import Testing

@MainActor
struct HighlightSelectionTests {
    @Test("Highlighting a row inside a multi-selection colors every selected row")
    func highlightsWholeSelection() {
        let coordinator = MainContentCoordinator()
        let rows = (0 ..< 3).map { TestFixtures.makeTransaction(url: "https://api.example.com/\($0)") }
        let outside = TestFixtures.makeTransaction(url: "https://api.example.com/outside")
        for row in rows + [outside] {
            row.assignCaptureContextIfMissing(coordinator.activeCaptureContext)
        }
        coordinator.processBatch(rows + [outside], generation: coordinator.sessionGeneration)
        coordinator.selectedTransactionIDs = Set(rows.map(\.id))

        coordinator.setHighlight(.gray, clicked: rows[1])
        #expect(rows.allSatisfy { $0.highlightColor == .gray })
        #expect(outside.highlightColor == nil)

        coordinator.setHighlight(.red, clicked: outside)
        #expect(outside.highlightColor == .red)
        #expect(rows.allSatisfy { $0.highlightColor == .gray })
    }

    @Test("Every highlight color has a localized name and a system color")
    func colorsAreNamed() {
        #expect(HighlightColor.allCases.map(\.displayName) == ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"])
        #expect(HighlightColor(rawValue: "gray")?.nsColor == .systemGray)
    }
}
