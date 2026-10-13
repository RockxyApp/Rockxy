import Foundation

// Defines the structural, provider-neutral diagnostics captured for a streaming
// (Server-Sent Events) HTTP response. These value types carry only structural metadata
// about the event stream — never raw payload bytes — so they are safe to retain and
// display without leaking response content.

// MARK: - StreamDiagnostics

/// Bounded, provider-neutral summary of a captured SSE response stream.
///
/// Holds only structural metadata (per-event index / name / time / size) and a small
/// set of scalar summary fields. No raw event payloads are retained. Produced by
/// `SSEStreamCaptureAccumulator.finish(reason:)`.
struct StreamDiagnostics: Sendable, Equatable {
    /// Ordered structural metadata for retained events, bounded to `ProxyLimits.maxSSEEventRecords`.
    /// All time fields below are relative times expressed in seconds elapsed from the
    /// request/capture start (the same origin used by `UpstreamResponseHandler`), not from the
    /// first event.
    let events: [SSEEventMetadata]

    /// Total number of events observed, including any dropped once the retention bound was hit.
    let eventCount: Int

    /// Relative time (seconds elapsed from the request/capture start) of the first observed event.
    let firstEventTime: TimeInterval?

    /// Relative time (seconds elapsed from the request/capture start) of the most recent observed event.
    let lastEventTime: TimeInterval?

    /// Relative time (seconds elapsed from the request/capture start) of the terminal-marker
    /// event (e.g. `[DONE]`), if one was seen.
    let terminalEventTime: TimeInterval?

    /// Largest gap in seconds between two consecutive events.
    let maxInterEventGap: TimeInterval?

    /// In-band terminal marker recognized in the stream, if any.
    let terminalMarker: SSETerminalMarker?

    /// How the stream ended.
    let outcome: StreamTerminalOutcome

    /// True once the event-retention bound was reached and later events were counted but not stored.
    let didReachMetadataLimit: Bool

    /// True if a malformed or oversized partial frame was observed and discarded.
    let didObserveMalformedFrame: Bool

    /// True if the stream ended with buffered bytes that never formed a complete event.
    let hasUnterminatedPartialFrame: Bool
}

// MARK: - SSEEventMetadata

/// Structural metadata for a single SSE event. Deliberately excludes the event payload —
/// only its position, optional visible name, relative arrival time, and byte size.
struct SSEEventMetadata: Sendable, Equatable {
    /// Zero-based ordinal of this event within the stream.
    let index: Int

    /// The `event:` field value, if the stream declared one for this event.
    let eventName: String?

    /// Seconds elapsed from the request/capture start to this event's dispatch.
    let relativeTime: TimeInterval

    /// Number of raw stream bytes (field lines including their line terminators) that composed
    /// this event, excluding the dispatching blank line.
    let byteCount: Int
}

// MARK: - SSETerminalMarker

/// In-band terminal markers recognized in an SSE stream.
enum SSETerminalMarker: String, Sendable, Equatable {
    /// The conventional `data: [DONE]` sentinel used by AI/model streaming APIs.
    case done
    /// Anthropic Messages streams end with an `event: message_stop` event.
    case messageStop
    /// OpenAI Responses streams end with `response.completed`, `response.incomplete`, or `response.failed`.
    case responseFinished

    // MARK: Internal

    /// The terminal marker an `event:` name announces, if any.
    static func fromEventName(_ name: String?) -> SSETerminalMarker? {
        switch name {
        case "message_stop":
            .messageStop
        case "response.completed",
             "response.incomplete",
             "response.failed":
            .responseFinished
        default:
            nil
        }
    }
}

// MARK: - StreamTerminalOutcome

/// How a captured stream ended, distinguishing a clean terminal marker from an HTTP end
/// that arrived without one, a transport interruption, and a read timeout.
enum StreamTerminalOutcome: Sendable, Equatable {
    /// The upstream ended cleanly and an in-band terminal marker (e.g. `[DONE]`) was seen.
    case completedWithTerminalMarker

    /// The HTTP body ended without any recognized in-band terminal marker. The stream is
    /// treated as incomplete because the upstream never signalled a structural end of events.
    case endedWithoutTerminalMarker

    /// The transport was interrupted before the stream completed.
    case transportInterrupted

    /// The response read timed out before the stream produced a terminal marker or clean end.
    case timedOut
}

// MARK: - StreamCompletionReason

/// Explicit reason supplied by the caller when finishing a capture, used to derive the
/// terminal outcome alongside any observed in-band marker.
enum StreamCompletionReason: Sendable, Equatable {
    /// The upstream signalled a clean end of the response body.
    case endOfStream

    /// The channel went inactive or errored before the response body completed.
    case transportFailure

    /// The response read timed out before the body completed.
    case readTimeout
}
