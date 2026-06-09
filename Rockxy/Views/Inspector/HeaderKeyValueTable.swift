import AppKit
import SwiftUI

/// Dense two-column header table used by request and response inspectors.
/// Keeps the column names visible so header values read like a native key/value grid.
struct HeaderKeyValueTable: View {
    let headers: [HTTPHeader]
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                row(header)
                if index < headers.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text(String(localized: "Key"))
                .font(.system(size: metrics.fontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            Divider()
            Text(String(localized: "Value"))
                .font(.system(size: metrics.fontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func row(_ header: HTTPHeader) -> some View {
        HStack(spacing: 0) {
            HighlightedInspectorText(text: header.name, highlightContext: highlightContext)
                .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(width: 180, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            Divider()
            HStack(alignment: .top, spacing: 6) {
                HighlightedInspectorText(text: header.value, highlightContext: highlightContext)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                if let badge = HeaderDebugBadge.classify(header.name) {
                    Text(badge.title)
                        .font(.system(size: metrics.badgeFontSize, weight: .semibold))
                        .foregroundStyle(badge.foreground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badge.background, in: RoundedRectangle(cornerRadius: 4))
                        .help(badge.help)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

private extension Text {
    init(_ text: String, highlightContext: InspectorHighlightContext) {
        guard !highlightContext.isEmpty else {
            self.init(text)
            return
        }
        var attributed = AttributedString(text)
        let ranges = highlightContext.matchRanges(in: text, limit: 50)
        for range in ranges {
            guard let attributedRange = Range(range, in: text),
                  let lower = AttributedString.Index(attributedRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(attributedRange.upperBound, within: attributed) else
            {
                continue
            }
            attributed[lower ..< upper].backgroundColor = Theme.Inspector.matchHighlight
            attributed[lower ..< upper].foregroundColor = Theme.Inspector.matchHighlightText
        }
        self.init(attributed)
    }
}

struct HighlightedInspectorText: View {
    let text: String
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        Text(text, highlightContext: highlightContext)
    }
}

private struct HeaderDebugBadge {
    let title: String
    let help: String
    let foreground: Color
    let background: Color

    static func classify(_ headerName: String) -> HeaderDebugBadge? {
        switch headerName.lowercased() {
        case "content-security-policy":
            HeaderDebugBadge(
                title: "CSP",
                help: String(localized: "Content Security Policy header"),
                foreground: .red,
                background: .red.opacity(0.12)
            )
        case "access-control-allow-origin",
             "access-control-allow-headers",
             "access-control-allow-methods",
             "access-control-allow-credentials":
            HeaderDebugBadge(
                title: "CORS",
                help: String(localized: "Cross-Origin Resource Sharing header"),
                foreground: .blue,
                background: .blue.opacity(0.12)
            )
        case "set-cookie",
             "cookie":
            HeaderDebugBadge(
                title: "Cookie",
                help: String(localized: "Cookie header"),
                foreground: .orange,
                background: .orange.opacity(0.12)
            )
        case "cache-control",
             "etag",
             "expires",
             "last-modified":
            HeaderDebugBadge(
                title: "Cache",
                help: String(localized: "Cache debugging header"),
                foreground: .indigo,
                background: .indigo.opacity(0.12)
            )
        case "authorization",
             "proxy-authorization",
             "www-authenticate":
            HeaderDebugBadge(
                title: "Auth",
                help: String(localized: "Authentication header"),
                foreground: .purple,
                background: .purple.opacity(0.12)
            )
        case "x-forwarded-for",
             "x-forwarded-host",
             "x-forwarded-proto",
             "x-real-ip",
             "via",
             "forwarded":
            HeaderDebugBadge(
                title: "Proxy",
                help: String(localized: "Proxy or gateway header"),
                foreground: .teal,
                background: .teal.opacity(0.12)
            )
        default:
            nil
        }
    }
}
