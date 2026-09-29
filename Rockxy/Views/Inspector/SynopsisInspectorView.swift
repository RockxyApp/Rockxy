import SwiftUI

/// At-a-glance summary of a transaction: method, URL, host, path, HTTP version,
/// response status, content type, size, duration, and originating client app.
struct SynopsisInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                synopsisRow(String(localized: "Method", bundle: RockxyLocalization.bundle), transaction.request.method)
                synopsisRow(
                    String(localized: "URL", bundle: RockxyLocalization.bundle),
                    transaction.request.url.absoluteString
                )
                synopsisRow(String(localized: "Host", bundle: RockxyLocalization.bundle), transaction.request.host)
                synopsisRow(String(localized: "Path", bundle: RockxyLocalization.bundle), transaction.request.path)
                synopsisRow(
                    String(localized: "HTTP Version", bundle: RockxyLocalization.bundle),
                    transaction.request.httpVersion
                )

                if let matchedRuleName = transaction.matchedRuleName {
                    Divider()
                    synopsisRow(String(localized: "Matched Rule", bundle: RockxyLocalization.bundle), matchedRuleName)
                    if let actionSummary = transaction.matchedRuleActionSummary {
                        synopsisRow(String(localized: "Rule Action", bundle: RockxyLocalization.bundle), actionSummary)
                    }
                    if let pattern = transaction.matchedRulePattern {
                        synopsisRow(String(localized: "Rule Pattern", bundle: RockxyLocalization.bundle), pattern)
                    }
                }

                if !transaction.appliedScriptNames.isEmpty {
                    Divider()
                    synopsisRow(
                        String(localized: "Scripts", bundle: RockxyLocalization.bundle),
                        transaction.appliedScriptNames.joined(separator: ", ")
                    )
                }

                if let response = transaction.response {
                    Divider()
                    synopsisRow(
                        String(localized: "Status", bundle: RockxyLocalization.bundle),
                        "\(response.statusCode) \(response.statusMessage)"
                    )
                    if let contentType = Self.contentTypeHeaderValue(in: response.headers) {
                        synopsisRow("Content-Type", contentType)
                    }
                    if let body = response.body {
                        synopsisRow(
                            String(localized: "Response Size", bundle: RockxyLocalization.bundle),
                            SizeFormatter.format(bytes: body.count)
                        )
                    }
                }

                if let duration = transaction.displayDuration {
                    Divider()
                    synopsisRow(
                        String(localized: "Duration", bundle: RockxyLocalization.bundle),
                        DurationFormatter.format(seconds: duration)
                    )
                }

                if let clientApp = transaction.clientApp {
                    Divider()
                    synopsisRow(String(localized: "Client App", bundle: RockxyLocalization.bundle), clientApp)
                }
            }
            .padding()
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private func synopsisRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    /// The `Content-Type` header exactly as the peer sent it. The row is labelled with the wire
    /// header name, so it must show the wire value — `ContentType` is Rockxy's normalized render
    /// bucket (`text` for `text/event-stream`, `unknown` for a message with no such header) and
    /// reading it here reported a category the response never carried.
    private static func contentTypeHeaderValue(in headers: [HTTPHeader]) -> String? {
        headers.first { $0.name.lowercased() == "content-type" }?.value
    }
}
