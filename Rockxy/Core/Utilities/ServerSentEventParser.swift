import Foundation

// Splits a captured text/event-stream body into individual Server-Sent Events.

// MARK: - ServerSentEvent

struct ServerSentEvent: Identifiable, Equatable, Sendable {
    /// Position in the stream, starting at 1.
    let id: Int
    let event: String?
    let lastEventID: String?
    let retry: Int?
    let data: String

    /// Event name as the browser's EventSource dispatches it.
    var eventType: String {
        event ?? "message"
    }
}

// MARK: - ServerSentEventParser

/// Follows the WHATWG event-stream interpretation: `data:` lines accumulate,
/// a blank line dispatches, `:` lines are comments, and an event without data
/// is not dispatched. Unlike the AI detector, sentinel payloads such as `[DONE]`
/// are kept so the stream reads exactly as the client received it.
enum ServerSentEventParser {
    static let maxEvents = 5_000

    static func isEventStream(_ headers: [HTTPHeader]) -> Bool {
        headers.contains {
            $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
                && $0.value.lowercased().hasPrefix("text/event-stream")
        }
    }

    static func parse(_ data: Data) -> [ServerSentEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        var events: [ServerSentEvent] = []
        var eventName: String?
        var eventID: String?
        var retry: Int?
        var dataLines: [String] = []

        func dispatch() {
            defer {
                eventName = nil
                retry = nil
                dataLines = []
            }
            guard !dataLines.isEmpty, events.count < maxEvents else {
                return
            }
            events.append(ServerSentEvent(
                id: events.count + 1,
                event: eventName,
                lastEventID: eventID,
                retry: retry,
                data: dataLines.joined(separator: "\n")
            ))
        }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                dispatch()
                continue
            }
            if line.hasPrefix(":") {
                continue
            }
            let field: Substring
            var value: Substring
            if let colon = line.firstIndex(of: ":") {
                field = line[line.startIndex ..< colon]
                value = line[line.index(after: colon)...]
                if value.hasPrefix(" ") {
                    value = value.dropFirst()
                }
            } else {
                field = line
                value = ""
            }
            switch field {
            case "event":
                eventName = String(value)
            case "data":
                dataLines.append(String(value))
            case "id":
                if !value.contains("\0") {
                    eventID = String(value)
                }
            case "retry":
                retry = Int(value)
            default:
                continue
            }
            if events.count >= maxEvents {
                break
            }
        }
        dispatch()
        return events
    }
}
