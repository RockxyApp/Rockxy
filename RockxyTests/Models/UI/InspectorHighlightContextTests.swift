import AppKit
import Foundation
@testable import Rockxy
import Testing

struct InspectorHighlightContextTests {
    @Test("Literal highlights are case insensitive")
    func literalHighlightsCaseInsensitive() {
        let context = InspectorHighlightContext(literalTerms: ["unsafe-inline"])
        let ranges = context.matchRanges(in: "script-src 'UNSAFE-INLINE'")
        #expect(ranges.count == 1)
    }

    @Test("Negative filter values are not represented in highlight context")
    @MainActor
    func negativeRulesDoNotHighlight() {
        let coordinator = MainContentCoordinator()
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .url, filterOperator: .doesNotContain, value: "secret"),
            FilterRule(isEnabled: true, field: .responseHeader, filterOperator: .contains, value: "unsafe-inline"),
        ]
        let context = coordinator.activeInspectorHighlightContext()

        #expect(!context.literalTerms.contains("secret"))
        #expect(context.literalTerms.contains("unsafe-inline"))
    }

    @Test("Highlight ranges are capped for large payloads")
    func highlightRangesAreCapped() {
        let context = InspectorHighlightContext(literalTerms: ["a"])
        let ranges = context.matchRanges(in: String(repeating: "a", count: 2_000), limit: 20)
        #expect(ranges.count == 20)
    }

    @Test("Long header values highlight matches near the end")
    func longHeaderHighlightingFindsLateMatches() {
        let context = InspectorHighlightContext(literalTerms: ["unsafe-inline"])
        let headerValue = String(repeating: "default-src 'self'; ", count: 80) + "script-src 'unsafe-inline'"

        let ranges = context.matchRanges(in: headerValue, limit: 5)

        #expect(ranges.count == 1)
    }

@Test("Highlight theme colors remain visible in light and dark appearances")
func highlightThemeColorsReadable() {
    let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    for appearanceName in appearances {
        guard let appearance = NSAppearance(named: appearanceName) else {
            continue
        }

        appearance.performAsCurrentDrawingAppearance {
            let backgroundAlpha = Theme.Inspector.matchHighlightNS.alphaComponent
            let foregroundAlpha = Theme.Inspector.matchHighlightTextNS.alphaComponent

            #expect(backgroundAlpha > 0.2)
            #expect(foregroundAlpha > 0.9)
        }
    }
}

    @Test("Rapid filter updates produce a fresh highlight identity")
    @MainActor
    func rapidFilterUpdatesProduceFreshHighlightContext() {
        let coordinator = MainContentCoordinator()
        coordinator.isFilterBarVisible = true
        coordinator.filterRules = [
            FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: "first"),
        ]
        let firstContext = coordinator.activeInspectorHighlightContext()

        coordinator.filterRules[0].value = "second"
        let secondContext = coordinator.activeInspectorHighlightContext()

        #expect(firstContext.identity != secondContext.identity)
        #expect(secondContext.literalTerms == ["second"])
    }
}
