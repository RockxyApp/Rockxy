import SwiftUI

/// Displays request cookies (from Cookie header) and response cookies (from Set-Cookie headers)
/// in a two-column grid layout matching the HeadersInspectorView pattern.
struct CookiesInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        ScrollView {
            if transaction.request.cookies.isEmpty, responseCookies.isEmpty {
                Text("No cookies")
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !transaction.request.cookies.isEmpty {
                        Section("Request Cookies") {
                            cookieTable(cookies: transaction.request.cookies)
                        }
                    }

                    if !responseCookies.isEmpty {
                        Section("Response Cookies") {
                            cookieTable(cookies: responseCookies)
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: Private

    private var responseCookies: [HTTPCookie] {
        transaction.response?.setCookies ?? []
    }

    private func cookieTable(cookies: [HTTPCookie]) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(minimum: 120, maximum: 200), alignment: .topLeading),
            GridItem(.flexible(), alignment: .topLeading),
        ], spacing: 4) {
            ForEach(Array(cookies.enumerated()), id: \.offset) { _, cookie in
                Text("Name")
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .fontWeight(.semibold)
                HighlightedInspectorText(text: cookie.name, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .textSelection(.enabled)

                Text("Value")
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .fontWeight(.semibold)
                HighlightedInspectorText(text: cookie.value, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .textSelection(.enabled)

                Text("Domain")
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .fontWeight(.semibold)
                HighlightedInspectorText(text: cookie.domain, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .textSelection(.enabled)

                Text("Path")
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .fontWeight(.semibold)
                HighlightedInspectorText(text: cookie.path, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .textSelection(.enabled)

                if cookie.isSecure {
                    Text("Secure")
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .fontWeight(.semibold)
                    Text("Yes")
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                }

                if cookie.isHTTPOnly {
                    Text("HttpOnly")
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .fontWeight(.semibold)
                    Text("Yes")
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let expires = cookie.expiresDate {
                    Text("Expires")
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(expires.formatted(.dateTime))
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                }

                Divider()
                    .gridCellColumns(2)
            }
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
