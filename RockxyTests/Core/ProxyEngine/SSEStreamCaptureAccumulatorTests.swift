import Foundation
@testable import Rockxy
import Testing

struct SSEStreamCaptureAccumulatorTests {
    // MARK: Internal

    // MARK: Fragmented frames

    @Test("reassembles an event split across multiple appends")
    func fragmentedFramesFormOneEvent() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: hel"), at: 0)
        acc.append(bytes("lo"), at: 0)
        acc.append(bytes("\n\n"), at: 0)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.eventCount == 1)
        #expect(diagnostics.events.count == 1)
        #expect(diagnostics.events[0].index == 0)
        #expect(diagnostics.events[0].eventName == nil)
        // "data: hello" (11 bytes) + LF terminator.
        #expect(diagnostics.events[0].byteCount == 12)
        #expect(diagnostics.terminalMarker == nil)
        #expect(diagnostics.outcome == .endedWithoutTerminalMarker)
        #expect(diagnostics.hasUnterminatedPartialFrame == false)
    }

    // MARK: CRLF boundaries

    @Test("recognizes CRLF blank-line event boundaries")
    func crlfBoundaryDispatchesEvent() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("event: message\r\ndata: x\r\n\r\n"), at: 0)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.eventCount == 1)
        #expect(diagnostics.events[0].eventName == "message")
        #expect(diagnostics.hasUnterminatedPartialFrame == false)
    }

    // MARK: DONE terminal marker

    @Test("recognizes data: [DONE] terminal marker")
    func doneMarkerProducesTerminalOutcome() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: hi\n\n"), at: 0)
        acc.append(bytes("data: [DONE]\n\n"), at: 1)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.eventCount == 2)
        #expect(diagnostics.terminalMarker == .done)
        #expect(diagnostics.terminalEventTime == 1)
        #expect(diagnostics.outcome == .completedWithTerminalMarker)
    }

    @Test(
        "recognizes provider end-of-stream events",
        arguments: [
            ("message_stop", SSETerminalMarker.messageStop),
            ("response.completed", SSETerminalMarker.responseFinished),
            ("response.incomplete", SSETerminalMarker.responseFinished),
        ]
    )
    func providerTerminalEvents(eventName: String, expected: SSETerminalMarker) {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("event: content\ndata: {}\n\n"), at: 0.1)
        acc.append(bytes("event: \(eventName)\ndata: {}\n\n"), at: 0.4)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.terminalMarker == expected)
        #expect(diagnostics.terminalEventTime == 0.4)
        #expect(diagnostics.outcome == .completedWithTerminalMarker)
    }

    @Test("recognizes data:[DONE] without a leading space")
    func doneMarkerWithoutLeadingSpace() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data:[DONE]\n\n"), at: 0)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.terminalMarker == .done)
        #expect(diagnostics.outcome == .completedWithTerminalMarker)
    }

    // MARK: End without DONE

    @Test("clean end without a terminal marker")
    func endWithoutDoneMarker() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: a\n\ndata: b\n\n"), at: 0)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.eventCount == 2)
        #expect(diagnostics.terminalMarker == nil)
        #expect(diagnostics.outcome == .endedWithoutTerminalMarker)
    }

    // MARK: Transport interruption

    @Test("transport failure yields an interrupted outcome")
    func transportInterruptionOutcome() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: a\n\n"), at: 0)
        acc.append(bytes("data: partial-without-boundary"), at: 1)
        let diagnostics = acc.finish(reason: .transportFailure)

        #expect(diagnostics.eventCount == 1)
        #expect(diagnostics.outcome == .transportInterrupted)
        #expect(diagnostics.hasUnterminatedPartialFrame == true)
    }

    @Test("a terminal marker stays complete when the transport later drops")
    func doneMarkerSurvivesTransportInterruption() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: hi\n\n"), at: 0)
        acc.append(bytes("data: [DONE]\n\n"), at: 1)
        // The connection drops after [DONE] without a clean HTTP end.
        let diagnostics = acc.finish(reason: .transportFailure)

        #expect(diagnostics.terminalMarker == .done)
        #expect(diagnostics.outcome == .completedWithTerminalMarker)
    }

    @Test("a terminal marker stays complete when a read timeout fires afterwards")
    func doneMarkerSurvivesReadTimeout() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: [DONE]\n\n"), at: 0.5)
        let diagnostics = acc.finish(reason: .readTimeout)

        #expect(diagnostics.terminalMarker == .done)
        #expect(diagnostics.outcome == .completedWithTerminalMarker)
    }

    // MARK: Read timeout

    @Test("read timeout yields a distinct timed-out outcome")
    func readTimeoutOutcome() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: a\n\n"), at: 0.1)
        let diagnostics = acc.finish(reason: .readTimeout)

        #expect(diagnostics.eventCount == 1)
        #expect(diagnostics.terminalMarker == nil)
        #expect(diagnostics.outcome == .timedOut)
    }

    // MARK: Timing / max gap

    @Test("tracks first/last event time and max inter-event gap")
    func timingAndMaxGap() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: a\n\n"), at: 10)
        acc.append(bytes("data: b\n\n"), at: 11)
        acc.append(bytes("data: c\n\n"), at: 15)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.firstEventTime == 10)
        #expect(diagnostics.lastEventTime == 15)
        #expect(diagnostics.maxInterEventGap == 4)
        #expect(diagnostics.events.map(\.relativeTime) == [10, 11, 15])
    }

    @Test("first event time preserves the caller-supplied elapsed offset")
    func firstEventTimePreservesCallerElapsed() {
        var acc = SSEStreamCaptureAccumulator()
        // The caller feeds bytes already offset from request start; the first event must
        // report that elapsed value verbatim, not a rebased zero.
        acc.append(bytes("data: hello\n\n"), at: 0.280)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.firstEventTime == 0.280)
        #expect(diagnostics.events.first?.relativeTime == 0.280)
    }

    // MARK: Bounds

    @Test("bounds retained event records while still counting overflow")
    func metadataRecordLimitIsBounded() {
        var acc = SSEStreamCaptureAccumulator()
        let overflow = ProxyLimits.maxSSEEventRecords + 5
        for _ in 0 ..< overflow {
            acc.append(bytes("data: x\n\n"), at: 0)
        }
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.eventCount == overflow)
        #expect(diagnostics.events.count == ProxyLimits.maxSSEEventRecords)
        #expect(diagnostics.didReachMetadataLimit == true)
    }

    @Test("bounds an oversized unterminated partial frame")
    func partialFrameBufferIsBounded() {
        var acc = SSEStreamCaptureAccumulator()
        let oversized = [UInt8](repeating: 0x61, count: ProxyLimits.maxSSEPartialFrameBytes + 1)
        acc.append(oversized, at: 0)
        // A valid event after the malformed frame still parses.
        acc.append(bytes("data: ok\n\n"), at: 1)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.didObserveMalformedFrame == true)
        #expect(diagnostics.eventCount == 1)
        #expect(diagnostics.hasUnterminatedPartialFrame == false)
    }

    @Test("a final event with a huge data line keeps its name and completes the stream")
    func oversizedFinalEventKeepsCompletion() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("event: response.output_text.delta\ndata: {}\n\n"), at: 0.1)
        acc.append(bytes("event: response.completed\ndata: {\"output\":\""), at: 0.5)
        let huge = [UInt8](repeating: 0x41, count: ProxyLimits.maxSSEPartialFrameBytes + 10)
        // Delivered in many chunks, as a network read would.
        stride(from: 0, to: huge.count, by: 4_096).forEach { start in
            acc.append(huge[start ..< min(start + 4_096, huge.count)], at: 0.6)
        }
        acc.append(bytes("\"}\n\n"), at: 0.7)
        let diagnostics = acc.finish(reason: .endOfStream)

        #expect(diagnostics.eventCount == 2)
        #expect(diagnostics.terminalMarker == .responseFinished)
        #expect(diagnostics.outcome == .completedWithTerminalMarker)
        #expect(diagnostics.didObserveMalformedFrame == false)
        #expect(diagnostics.events.last?.byteCount ?? 0 > ProxyLimits.maxSSEPartialFrameBytes)
    }

    @Test("[DONE] split across chunks is still recognized")
    func doneSplitAcrossChunks() {
        var acc = SSEStreamCaptureAccumulator()
        acc.append(bytes("data: [DO"), at: 0.1)
        acc.append(bytes("NE]\n\n"), at: 0.2)
        #expect(acc.finish(reason: .endOfStream).terminalMarker == .done)
    }

    // MARK: Private

    // MARK: Helpers

    private func bytes(_ string: String) -> [UInt8] {
        Array(string.utf8)
    }
}
