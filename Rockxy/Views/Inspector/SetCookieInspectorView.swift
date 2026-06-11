import SwiftUI

/// Displays `Set-Cookie` headers from the HTTP response, showing each cookie's name, value,
/// domain, path, and security flags (Secure, HttpOnly).
struct SetCookieInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        if let response = transaction.response {
            let cookies = response.setCookies
            if cookies.isEmpty {
                InspectorEmptyStateView(
                    String(localized: "No Set-Cookie Headers"),
                    systemImage: "cup.and.saucer"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(cookies.enumerated()), id: \.offset) { _, cookie in
                            cookieRow(cookie)
                            Divider()
                        }
                    }
                    .padding()
                }
            }
        } else {
            InspectorEmptyStateView(
                String(localized: "No Response"),
                systemImage: "arrow.down.circle"
            )
        }
    }

    // MARK: Private

    private func cookieRow(_ cookie: HTTPCookie) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HighlightedInspectorText(text: cookie.name, highlightContext: highlightContext)
                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                .fontWeight(.bold)
            HighlightedInspectorText(text: cookie.value, highlightContext: highlightContext)
                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let domain = Optional(cookie.domain), !domain.isEmpty {
                    labelValue(String(localized: "Domain"), domain)
                }
                labelValue(String(localized: "Path"), cookie.path)
                if cookie.isSecure {
                    Text(String(localized: "Secure"))
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(.green)
                }
                if cookie.isHTTPOnly {
                    Text("HttpOnly")
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label + ":")
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(.secondary)
            HighlightedInspectorText(text: value, highlightContext: highlightContext)
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
