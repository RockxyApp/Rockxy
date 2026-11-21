@testable import Rockxy
import Testing

// MARK: - FilterRuleListEditorTests

struct FilterRuleListEditorTests {
    // MARK: Internal

    @Test("a stale focused id resolves to the last row")
    func staleFocusFallsBackToLast() {
        let rules = Self.rows(3)
        #expect(FilterRuleListEditor.resolve(FilterRule().id, in: rules) == rules.last?.id)
        #expect(FilterRuleListEditor.resolve(nil, in: rules) == rules.last?.id)
        #expect(FilterRuleListEditor.resolve(rules[0].id, in: rules) == rules[0].id)
    }

    @Test("removing with a stale focused id removes the last row")
    func removeWithStaleFocusRemovesLast() {
        var rules = Self.rows(3)
        let last = rules[2].id
        let stale = FilterRule().id
        FilterRuleListEditor.removeRule(id: FilterRuleListEditor.resolve(stale, in: rules), from: &rules)
        #expect(rules.count == 2)
        #expect(!rules.contains { $0.id == last })
    }

    @Test("removing an id that is gone does nothing")
    func removeUnknownIDIsNoOp() {
        var rules = Self.rows(2)
        let before = rules.map(\.id)
        FilterRuleListEditor.removeRule(id: FilterRule().id, from: &rules)
        #expect(rules.map(\.id) == before)
    }

    @Test("removing the only row clears it instead of removing it")
    func removeOnlyRowClearsIt() {
        var rules = [FilterRule(field: .url, filterOperator: .contains, value: "abc")]
        let id = rules[0].id
        FilterRuleListEditor.removeRule(id: id, from: &rules)
        #expect(rules.count == 1)
        #expect(rules[0].id == id)
        #expect(rules[0].value.isEmpty)
    }

    @Test("adding after a stale id appends")
    func addAfterStaleIDAppends() {
        var rules = Self.rows(2)
        let originals = rules.map(\.id)
        FilterRuleListEditor.addRule(afterID: FilterRule().id, to: &rules)
        #expect(rules.count == 3)
        #expect(Array(rules.map(\.id).prefix(2)) == originals)
    }

    @Test("adding after a known id inserts directly below it")
    func addAfterKnownIDInserts() {
        var rules = Self.rows(3)
        let originals = rules.map(\.id)
        FilterRuleListEditor.addRule(afterID: originals[0], to: &rules)
        #expect(rules.count == 4)
        #expect(rules[0].id == originals[0])
        #expect(rules[2].id == originals[1])
        #expect(rules[3].id == originals[2])
    }

    @Test("rows replaced wholesale by Clear All survive a stale action from the old rows")
    func clearAllThenStaleActions() {
        var rules = Self.rows(4)
        let staleIDs = rules.map(\.id)
        rules = [FilterRule()]
        let fresh = rules[0].id

        // Buttons and shortcuts that still carry an old id must not crash or mutate.
        for id in staleIDs {
            FilterRuleListEditor.removeRule(id: id, from: &rules)
        }
        #expect(rules.count == 1)
        #expect(rules[0].id == fresh)

        // A stale add appends rather than indexing into the old array.
        FilterRuleListEditor.addRule(afterID: staleIDs[3], to: &rules)
        #expect(rules.count == 2)
        #expect(rules[0].id == fresh)
    }

    // MARK: Private

    private static func rows(_ count: Int) -> [FilterRule] {
        (0 ..< count).map { FilterRule(field: .url, filterOperator: .contains, value: "v\($0)") }
    }
}
