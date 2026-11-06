import Foundation
@testable import Rockxy
import Testing

struct GraphQLResponseErrorSummaryTests {
    @Test("Errors in a successful HTTP response are summarized with message, path, and code")
    func parsesErrors() throws {
        let body = Data(#"""
        {"data":null,"errors":[
          {"message":"Not authorized","path":["viewer","orders",0],"extensions":{"code":"UNAUTHENTICATED"}},
          {"message":"Rate limited"}
        ]}
        """#.utf8)

        let summary = try #require(GraphQLResponseErrorSummary.parse(body))

        #expect(summary.totalCount == 2)
        #expect(!summary.hasPartialData)
        #expect(summary.errors[0] == GraphQLResponseError(
            message: "Not authorized",
            path: "viewer.orders.0",
            code: "UNAUTHENTICATED"
        ))
        #expect(summary.errors[1] == GraphQLResponseError(message: "Rate limited", path: nil, code: nil))
    }

    @Test("Data alongside errors is reported as a partial success")
    func reportsPartialData() throws {
        let body = Data(
            #"{"data":{"user":{"name":"Ada"}},"errors":[{"message":"posts unavailable","path":["user","posts"]}]}"#
                .utf8
        )
        let summary = try #require(GraphQLResponseErrorSummary.parse(body))
        #expect(summary.hasPartialData)
    }

    @Test(
        "Responses without errors, empty errors, or non-JSON bodies produce no summary",
        arguments: [
            #"{"data":{"ok":true}}"#,
            #"{"data":{"ok":true},"errors":[]}"#,
            "not json",
            #"[{"errors":[{"message":"batched"}]}]"#,
        ]
    )
    func ignoresResponsesWithoutErrors(body: String) {
        #expect(GraphQLResponseErrorSummary.parse(Data(body.utf8)) == nil)
        #expect(GraphQLResponseErrorSummary.parse(nil) == nil)
    }

    @Test("Large error lists are capped while the total stays accurate")
    func capsErrorList() throws {
        let entries = (0 ..< 80).map { #"{"message":"error \#($0)"}"# }.joined(separator: ",")
        let body = Data(#"{"errors":[\#(entries)]}"#.utf8)
        let summary = try #require(GraphQLResponseErrorSummary.parse(body))
        #expect(summary.errors.count == GraphQLResponseErrorSummary.maxErrors)
        #expect(summary.totalCount == 80)
    }

    @Test("Oversized bodies are not parsed")
    func skipsOversizedBodies() {
        let filler = String(repeating: "x", count: GraphQLResponseErrorSummary.maxPayloadBytes)
        let body = Data(#"{"errors":[{"message":"\#(filler)"}]}"#.utf8)
        #expect(GraphQLResponseErrorSummary.parse(body) == nil)
    }
}
