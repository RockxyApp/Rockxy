@testable import Rockxy
import Testing

struct HeaderTableFilterTests {
    private let headers = [
        HTTPHeader(name: "Content-Type", value: "application/json"),
        HTTPHeader(name: "X-Request-ID", value: "abc"),
        HTTPHeader(name: "Cache-Control", value: "no-store"),
    ]

    @Test("The header filter matches names and values without regard to case")
    func matchesNameOrValue() {
        #expect(HeaderKeyValueTable.filtered(headers, by: "content").map(\.name) == ["Content-Type"])
        #expect(HeaderKeyValueTable.filtered(headers, by: "NO-STORE").map(\.name) == ["Cache-Control"])
        #expect(HeaderKeyValueTable.filtered(headers, by: "  ").count == 3)
        #expect(HeaderKeyValueTable.filtered(headers, by: "missing").isEmpty)
    }
}
