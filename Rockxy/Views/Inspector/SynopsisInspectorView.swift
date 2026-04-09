import SwiftUI

/// At-a-glance summary of a transaction: method, URL, host, path, HTTP version,
/// response status, content type, size, duration, and originating client app.
struct SynopsisInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                synopsisRow(String(localized: "Method"), transaction.request.method)
                synopsisRow(String(localized: "URL"), transaction.request.url.absoluteString)
                synopsisRow(String(localized: "Host"), transaction.request.host)
                synopsisRow(String(localized: "Path"), transaction.request.path)
                synopsisRow("HTTP Version", transaction.request.httpVersion)

                if let matchedRuleName = transaction.matchedRuleName {
                    Divider()
                    synopsisRow(String(localized: "Matched Rule"), matchedRuleName)
                    if let actionSummary = transaction.matchedRuleActionSummary {
                        synopsisRow(String(localized: "Rule Action"), actionSummary)
                    }
                    if let pattern = transaction.matchedRulePattern {
                        synopsisRow(String(localized: "Rule Pattern"), pattern)
                    }
                }

                if let response = transaction.response {
                    Divider()
                    synopsisRow(String(localized: "Status"), "\(response.statusCode) \(response.statusMessage)")
                    if let contentType = response.contentType {
                        synopsisRow("Content-Type", contentType.rawValue)
                    }
                    if let body = response.body {
                        synopsisRow(String(localized: "Response Size"), "\(body.count) bytes")
                    }
                }

                if let timing = transaction.timingInfo {
                    Divider()
                    synopsisRow(
                        String(localized: "Duration"),
                        DurationFormatter.format(seconds: timing.totalDuration)
                    )
                }

                if let clientApp = transaction.clientApp {
                    Divider()
                    synopsisRow(String(localized: "Client App"), clientApp)
                }
            }
            .padding()
        }
    }

    // MARK: Private

    private func synopsisRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
