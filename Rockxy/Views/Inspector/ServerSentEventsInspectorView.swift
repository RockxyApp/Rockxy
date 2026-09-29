import AppKit
import SwiftUI

// Event-by-event view of a text/event-stream response.

// MARK: - ServerSentEventsInspectorView

/// Lists each Server-Sent Event in arrival order with its type and a preview,
/// and shows the selected event's data pretty-printed when it is JSON.
struct ServerSentEventsInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        Group {
            if let events {
                if events.isEmpty {
                    InspectorEmptyStateView(
                        String(localized: "No Events", bundle: RockxyLocalization.bundle),
                        systemImage: "dot.radiowaves.left.and.right",
                        description: String(
                            localized: "The stream has not delivered a complete event yet.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                } else {
                    VSplitView {
                        eventTable(events)
                            .frame(minHeight: 90, idealHeight: 160)
                        eventDetail
                            .frame(minHeight: 120)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: renderKey) {
            await loadEvents()
        }
    }

    static func isApplicable(to transaction: HTTPTransaction) -> Bool {
        guard let response = transaction.response else {
            return false
        }
        return ServerSentEventParser.isEventStream(response.headers)
    }

    // MARK: Private

    @State private var events: [ServerSentEvent]?
    @State private var selection: ServerSentEvent.ID?
    @Environment(\.appUIDisplayMetrics) private var metrics

    /// Re-parses when a streaming body grows, not only when the row changes.
    private var renderKey: String {
        "\(transaction.id.uuidString)-\(transaction.response?.body?.count ?? 0)"
    }

    private var selectedEvent: ServerSentEvent? {
        guard let events else {
            return nil
        }
        guard let selection else {
            return events.first
        }
        return events.first { $0.id == selection }
    }

    @ViewBuilder private var eventDetail: some View {
        if let event = selectedEvent {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(String(
                        localized: "Event \(event.id) · \(event.eventType)",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(.system(size: metrics.fontSize, weight: .semibold))
                    if let lastEventID = event.lastEventID {
                        Text("id: \(lastEventID)")
                            .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(String(localized: "Copy", bundle: RockxyLocalization.bundle)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(event.data, forType: .string)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider()
                ScrollView {
                    Text(Self.displayText(for: event.data))
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
            }
        }
    }

    private static func displayText(for data: String) -> String {
        guard let json = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: pretty, encoding: .utf8) else
        {
            return data
        }
        return text
    }

    private func eventTable(_ events: [ServerSentEvent]) -> some View {
        Table(events, selection: $selection) {
            TableColumn("#") { event in
                Text(event.id, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 32, ideal: 44, max: 64)
            TableColumn(String(localized: "Event", bundle: RockxyLocalization.bundle)) { event in
                Text(event.eventType)
                    .foregroundStyle(event.event == nil ? .secondary : .primary)
            }
            .width(min: 70, ideal: 120, max: 220)
            TableColumn(String(localized: "Data", bundle: RockxyLocalization.bundle)) { event in
                Text(event.data.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: metrics.secondaryFontSize))
        .accessibilityLabel(String(localized: "Server-sent events", bundle: RockxyLocalization.bundle))
    }

    private func loadEvents() async {
        guard let body = transaction.response?.body else {
            events = []
            return
        }
        let parsed = await Task.detached(priority: .userInitiated) {
            ServerSentEventParser.parse(body)
        }.value
        guard !Task.isCancelled else {
            return
        }
        if let selection, !parsed.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        events = parsed
    }
}
