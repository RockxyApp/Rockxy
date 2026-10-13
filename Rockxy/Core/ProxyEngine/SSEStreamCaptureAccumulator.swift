import Foundation

// Defines `SSEStreamCaptureAccumulator`, a provider-neutral, bounded helper that ingests
// Server-Sent Events response bytes incrementally and produces structural `StreamDiagnostics`.
// `UpstreamResponseHandler` drives it for `text/event-stream` responses, feeding each decoded
// body buffer as it arrives — before relay — and never mutating or delaying the bytes.

// MARK: - SSEStreamCaptureAccumulator

/// Ingests SSE response bytes across many `append(_:at:)` calls and derives structural
/// diagnostics without retaining any raw event payloads.
///
/// Recognizes event boundaries at blank lines using either LF (`\n\n`) or CRLF (`\r\n\r\n`)
/// terminators, and the conventional `data: [DONE]` terminal marker. Both the retained event
/// records and the in-progress partial-frame buffer are bounded (see `ProxyLimits`).
///
/// Pure Foundation value type with no isolation — safe to drive from a NIO event loop or a test.
/// Time is supplied by the caller so the accumulator has no ambient clock dependency. Each
/// supplied timestamp is already relative to the capture/request start, so it is recorded as-is
/// (the accumulator applies no origin offset of its own).
struct SSEStreamCaptureAccumulator: Sendable {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Feed a chunk of response bytes observed at `time` (seconds, already relative to the
    /// capture/request start). The value is recorded verbatim as the relative event time — the
    /// accumulator does not rebase against its first call. Each byte is scanned once.
    mutating func append<Bytes: Collection>(_ bytes: Bytes, at time: TimeInterval) where Bytes.Element == UInt8 {
        guard !finished, !bytes.isEmpty else {
            return
        }
        var remaining = bytes[...]
        if skippingOversizedLine {
            // The rest of a very long line (a large `data:` value) only counts toward the event's
            // size; its field was already read from the head of the line.
            guard let lineFeedIndex = remaining.firstIndex(of: Self.lineFeed) else {
                currentEventBytes += remaining.count
                return
            }
            currentEventBytes += remaining.distance(from: remaining.startIndex, to: lineFeedIndex) + 1
            skippingOversizedLine = false
            remaining = remaining[remaining.index(after: lineFeedIndex)...]
        }

        let scanFrom = partial.count
        partial.append(contentsOf: remaining)
        processCompleteLines(scanningFrom: scanFrom, at: time)

        // Leftover bytes are one unterminated line. A line past the per-frame cap is not dropped:
        // its head still names the field, and the event keeps its `event:` name (for example a
        // `response.completed` that carries the whole response), so only the bytes are skipped.
        if partial.count > ProxyLimits.maxSSEPartialFrameBytes {
            let head = partial.prefix(Self.oversizedLineHeadBytes)
            if head.first != Self.colon {
                currentHasContent = true
                parseField(head, isComplete: false)
            }
            if !head.contains(Self.colon) {
                // No field name at all: not a well-formed SSE line.
                didObserveMalformedFrame = true
            }
            currentEventBytes += partial.count
            partial.removeAll(keepingCapacity: false)
            skippingOversizedLine = true
        }
    }

    /// Finish the capture with an explicit completion reason and return the bounded diagnostics.
    /// The outcome distinguishes a completion with a terminal marker, an end that arrived without
    /// one (treated as incomplete), a transport interruption, and a read timeout. Idempotent-safe
    /// fields are computed from accumulated state.
    mutating func finish(reason: StreamCompletionReason) -> StreamDiagnostics {
        finished = true
        let hasPending = currentHasContent || !partial.isEmpty

        // A recognized in-band terminal marker (e.g. `[DONE]`) means the upstream already
        // signalled a structural end of events, so the stream is complete regardless of how
        // the transport later closed — a subsequent interruption or timeout does not downgrade it.
        let outcome: StreamTerminalOutcome = if terminalMarker != nil {
            .completedWithTerminalMarker
        } else {
            switch reason {
            case .transportFailure:
                .transportInterrupted
            case .readTimeout:
                .timedOut
            case .endOfStream:
                .endedWithoutTerminalMarker
            }
        }

        return StreamDiagnostics(
            events: events,
            eventCount: eventCount,
            firstEventTime: firstEventTime,
            lastEventTime: lastEventTime,
            terminalEventTime: terminalEventTime,
            maxInterEventGap: maxInterEventGap,
            terminalMarker: terminalMarker,
            outcome: outcome,
            didReachMetadataLimit: didReachMetadataLimit,
            didObserveMalformedFrame: didObserveMalformedFrame,
            hasUnterminatedPartialFrame: hasPending
        )
    }

    // MARK: Private

    private static let maxEventNameLength = 256
    /// Enough of an oversized line to read its field name and recognize `data: [DONE]`.
    private static let oversizedLineHeadBytes = 512
    private static let doneMarker = Array("[DONE]".utf8)
    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D
    private static let colon: UInt8 = 0x3A
    private static let space: UInt8 = 0x20

    private var partial: [UInt8] = []
    private var skippingOversizedLine = false
    private var finished = false

    private var events: [SSEEventMetadata] = []
    private var eventCount = 0
    private var firstEventTime: TimeInterval?
    private var lastEventTime: TimeInterval?
    private var terminalEventTime: TimeInterval?
    private var maxInterEventGap: TimeInterval?
    private var previousEventTime: TimeInterval?
    private var terminalMarker: SSETerminalMarker?
    private var didReachMetadataLimit = false
    private var didObserveMalformedFrame = false

    // In-progress event accumulation (reset at every boundary).
    private var currentEventName: String?
    private var currentEventBytes = 0
    private var currentHasContent = false
    private var currentSawDone = false

    /// `scanningFrom` is where new bytes start: earlier bytes were already searched and hold no
    /// line feed, so a long line split across many chunks is never rescanned from its start.
    private mutating func processCompleteLines(scanningFrom scanFrom: Int, at time: TimeInterval) {
        var cursor = 0
        var searchFrom = scanFrom
        let count = partial.count

        while let lineFeedIndex = partial[searchFrom ..< count].firstIndex(of: Self.lineFeed) {
            var end = lineFeedIndex
            if end > cursor, partial[end - 1] == Self.carriageReturn {
                end -= 1
            }
            consumeLine(partial[cursor ..< end], rawByteCount: lineFeedIndex - cursor + 1, at: time)
            cursor = lineFeedIndex + 1
            searchFrom = cursor
        }

        if cursor > 0 {
            partial.removeFirst(cursor)
        }
    }

    private mutating func consumeLine(_ content: ArraySlice<UInt8>, rawByteCount: Int, at time: TimeInterval) {
        if content.isEmpty {
            if currentHasContent {
                dispatchCurrentEvent(at: time)
            }
            resetCurrentEvent()
            return
        }

        // Comment lines begin with ':' and are ignored per the SSE specification.
        if content.first == Self.colon {
            return
        }

        currentHasContent = true
        currentEventBytes += rawByteCount
        parseField(content, isComplete: true)
    }

    /// Reads the field a line sets. Only `event:` values become strings; `data:` is compared as
    /// bytes, and `[DONE]` only counts when the whole line was seen (`isComplete`).
    private mutating func parseField(_ content: ArraySlice<UInt8>, isComplete: Bool) {
        guard let colonIndex = content.firstIndex(of: Self.colon) else {
            // A line with no colon is a field name with an empty value — not relevant here.
            return
        }

        let name = content[content.startIndex ..< colonIndex]
        var valueStart = content.index(after: colonIndex)
        if valueStart < content.endIndex, content[valueStart] == Self.space {
            valueStart = content.index(after: valueStart)
        }
        let value = content[valueStart ..< content.endIndex]

        if name.elementsEqual("event".utf8) {
            let bounded = value.prefix(Self.maxEventNameLength * 4)
            currentEventName = String(bytes: bounded, encoding: .utf8).map { String($0.prefix(Self.maxEventNameLength)) }
        } else if name.elementsEqual("data".utf8), isComplete, value.elementsEqual(Self.doneMarker) {
            currentSawDone = true
        }
    }

    private mutating func dispatchCurrentEvent(at time: TimeInterval) {
        // `time` is already the caller-provided elapsed time from request start, so it is
        // recorded verbatim — the accumulator applies no origin offset of its own.
        let relative = time
        let index = eventCount
        eventCount += 1

        if let previousEventTime {
            let gap = relative - previousEventTime
            if maxInterEventGap == nil || gap > (maxInterEventGap ?? 0) {
                maxInterEventGap = gap
            }
        }
        previousEventTime = relative

        if firstEventTime == nil {
            firstEventTime = relative
        }
        lastEventTime = relative

        if currentSawDone {
            terminalMarker = .done
            terminalEventTime = relative
        } else if let marker = SSETerminalMarker.fromEventName(currentEventName) {
            terminalMarker = marker
            terminalEventTime = relative
        }

        if events.count < ProxyLimits.maxSSEEventRecords {
            events.append(SSEEventMetadata(
                index: index,
                eventName: currentEventName,
                relativeTime: relative,
                byteCount: currentEventBytes
            ))
        } else {
            didReachMetadataLimit = true
        }
    }

    private mutating func resetCurrentEvent() {
        currentEventName = nil
        currentEventBytes = 0
        currentHasContent = false
        currentSawDone = false
    }
}
