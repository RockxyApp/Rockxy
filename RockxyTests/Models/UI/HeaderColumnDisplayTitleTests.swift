@testable import Rockxy
import Testing

/// A body column's name is an expression, not a title. `$.data.user.name` drawn as a column
/// header is the expression leaking into the UI, which is what these pin down.
@Suite("Custom column header titles")
struct HeaderColumnDisplayTitleTests {
    @Test("A plain path is titled by its last key")
    func plainPathUsesLastKey() {
        #expect(HeaderColumn.bodyColumnTitle(for: "$.data.user.name") == "name")
        #expect(HeaderColumn.bodyColumnTitle(for: ".id") == "id")
        #expect(HeaderColumn.bodyColumnTitle(for: "$.items[0].sku") == "sku")
        #expect(HeaderColumn.bodyColumnTitle(for: ".users[].name") == "name")
        #expect(HeaderColumn.bodyColumnTitle(for: "$.a_b-c") == "a_b-c")
    }

    /// Naming a column after one part of a filter would describe it wrongly, so anything
    /// that is not a plain path keeps its whole expression.
    @Test("Anything that is not a plain path keeps the whole expression")
    func filtersAreLeftWhole() {
        #expect(HeaderColumn.bodyColumnTitle(for: ".a + .b") == nil)
        #expect(HeaderColumn.bodyColumnTitle(for: ".[] | .name") == nil)
        #expect(HeaderColumn.bodyColumnTitle(for: "$") == nil)
        #expect(HeaderColumn.bodyColumnTitle(for: "") == nil)
        #expect(HeaderColumn.bodyColumnTitle(for: "length") == nil)
        #expect(HeaderColumn.bodyColumnTitle(for: "$.items[abc].sku") == nil)
        #expect(HeaderColumn.bodyColumnTitle(for: "$.items[0") == nil)
    }

    @Test("A header or query column keeps its own name")
    func nonBodyColumnsAreUnchanged() {
        let columns = [
            HeaderColumn(headerName: "Authorization", source: .request),
            HeaderColumn(headerName: "page", source: .query),
        ]
        let titles = HeaderColumn.displayTitles(for: columns)
        #expect(titles[columns[0].id] == "Authorization")
        #expect(titles[columns[1].id] == "page")
    }

    @Test("A body column is titled by its last key, not its expression")
    func bodyColumnIsShortened() {
        let column = HeaderColumn(headerName: "$.data.user.name", source: .responseBody)
        #expect(HeaderColumn.displayTitles(for: [column])[column.id] == "name")
    }

    /// Two columns both called `name` would be worse than two raw expressions, because the
    /// user could not tell which one they were reading.
    @Test("Colliding titles fall back to the full expression")
    func collidingTitlesFallBack() {
        let first = HeaderColumn(headerName: "$.data.user.name", source: .responseBody)
        let second = HeaderColumn(headerName: "$.meta.user.name", source: .responseBody)
        let other = HeaderColumn(headerName: "$.data.id", source: .responseBody)
        let titles = HeaderColumn.displayTitles(for: [first, second, other])
        #expect(titles[first.id] == "$.data.user.name")
        #expect(titles[second.id] == "$.meta.user.name")
        #expect(titles[other.id] == "id")
    }

    /// The expression is the column's identity and its sort key; shortening the header must
    /// not touch either.
    @Test("Shortening the header leaves the column's identity alone")
    func identityIsUnchanged() {
        let column = HeaderColumn(headerName: "$.data.user.name", source: .responseBody)
        #expect(column.columnIdentifier == "resBody.$.data.user.name")
        #expect(HeaderColumn.parse(columnID: column.columnIdentifier)?.name == "$.data.user.name")
        #expect(HeaderColumn.parse(columnID: column.columnIdentifier)?.source == .responseBody)
    }
}
