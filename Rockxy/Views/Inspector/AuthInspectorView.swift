import SwiftUI

/// Displays the Authorization header from a captured HTTP transaction,
/// identifying the auth scheme (Bearer, Basic, Digest) and showing the full header value.
struct AuthInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        if let authHeader = findAuthHeader() {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        labelRow(String(localized: "Type"), authType(from: authHeader))
                        Spacer()
                        if JWTPreviewDecoder.looksLikeJWT(authHeader) {
                            Button {
                                jwtPreview = JWTPreviewDecoder.decode(authHeader)
                                isJWTPreviewPresented = true
                            } label: {
                                Label(String(localized: "Preview JWT"), systemImage: "key.viewfinder")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .popover(isPresented: $isJWTPreviewPresented, arrowEdge: .bottom) {
                                if let jwtPreview {
                                    QuickPreviewPopoverView(result: jwtPreview)
                                }
                            }
                        }
                    }
                    Divider()
                    labelRow(String(localized: "Full Value"), authHeader)
                }
                .padding()
            }
        } else {
            InspectorEmptyStateView(
                String(localized: "No Authorization"),
                systemImage: "lock.open",
                description: String(localized: "No Authorization header found")
            )
        }
    }

    // MARK: Private

    @State private var isJWTPreviewPresented = false
    @State private var jwtPreview: QuickPreviewResult?

    private func labelRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(.secondary)
            HighlightedInspectorText(text: value, highlightContext: highlightContext)
                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics

    private func findAuthHeader() -> String? {
        transaction.request.headers
            .first { $0.name.lowercased() == "authorization" }?
            .value
    }

    private func authType(from value: String) -> String {
        if value.lowercased().hasPrefix("bearer") {
            return "Bearer Token"
        } else if value.lowercased().hasPrefix("basic") {
            return "Basic Auth"
        } else if value.lowercased().hasPrefix("digest") {
            return "Digest Auth"
        }
        return String(localized: "Unknown")
    }
}
