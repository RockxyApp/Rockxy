import Foundation
@testable import Rockxy
import Testing

// MARK: - ServerSentEventParserTests

struct ServerSentEventParserTests {
    @Test("Events dispatch on blank lines with type, id, retry, and joined data")
    func parsesFields() {
        let stream = """
        : keep-alive

        event: status
        id: 7
        retry: 1500
        data: {"state":"queued"}

        data: line one
        data: line two

        data: [DONE]

        """
        let events = ServerSentEventParser.parse(Data(stream.utf8))

        #expect(events.count == 3)
        #expect(events[0].eventType == "status")
        #expect(events[0].lastEventID == "7")
        #expect(events[0].retry == 1_500)
        #expect(events[0].data == #"{"state":"queued"}"#)
        #expect(events[1].eventType == "message")
        #expect(events[1].lastEventID == "7")
        #expect(events[1].data == "line one\nline two")
        #expect(events[2].data == "[DONE]")
    }

    @Test("CRLF streams and a final event without a trailing blank line are handled")
    func handlesCRLFAndUnterminatedTail() {
        let events = ServerSentEventParser.parse(Data("data:a\r\n\r\ndata: b".utf8))

        #expect(events.map(\.data) == ["a", "b"])
    }

    @Test("A stream cut in the middle of a multibyte character still lists its events")
    func survivesTruncatedUTF8() {
        var bytes = Array("data: one\n\ndata: caf".utf8)
        bytes.append(contentsOf: [0xC3])
        let events = ServerSentEventParser.parse(Data(bytes))

        #expect(events.first?.data == "one")
        #expect(events.count == 2)
    }

    @Test("Only text/event-stream responses qualify")
    func detectsEventStream() {
        #expect(ServerSentEventParser.isEventStream([HTTPHeader(name: "content-type", value: "text/event-stream; charset=utf-8")]))
        #expect(!ServerSentEventParser.isEventStream([HTTPHeader(name: "Content-Type", value: "application/json")]))
    }

    @Test("Response tabs include Events only when requested")
    func eventsTabIsConditional() {
        #expect(!ResponseInspectorTab.availableTabs().contains(.events))
        #expect(ResponseInspectorTab.availableTabs(includesEvents: true).contains(.events))
    }
}
