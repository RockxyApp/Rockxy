import AppKit
import SwiftUI

// MARK: - HeaderKeyValueTable

/// Dense two-column header table used by request and response inspectors.
/// Keeps the column names visible so header values read like a native key/value grid.
struct HeaderKeyValueTable: View {
    // MARK: Internal

    let headers: [HTTPHeader]
    var highlightContext: InspectorHighlightContext = .empty
    var source: HeaderColumnSource?
    var coordinator: MainContentCoordinator?

    /// Tables longer than this get a filter field; short ones read fine without it.
    static let filterThreshold = 6

    /// Headers whose name or value contains `query`, ignoring case; all of them when empty.
    static func filtered(_ headers: [HTTPHeader], by query: String) -> [HTTPHeader] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else {
            return headers
        }
        return headers.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.value.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        let visible = Self.filtered(headers, by: filterText)
        VStack(spacing: 0) {
            if headers.count >= Self.filterThreshold {
                filterField
                Divider()
            }
            headerRow
            Divider()
            ForEach(Array(visible.enumerated()), id: \.offset) { index, header in
                row(header)
                if index < visible.count - 1 {
                    Divider()
                }
            }
            if visible.isEmpty {
                Text(String(localized: "No Matching Headers", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
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

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var filterText = ""

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                String(localized: "Filter Headers", bundle: RockxyLocalization.bundle),
                text: $filterText
            )
            .textFieldStyle(.plain)
            .font(.system(size: metrics.secondaryFontSize))
            .accessibilityLabel(String(localized: "Filter Headers", bundle: RockxyLocalization.bundle))
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Clear Filter", bundle: RockxyLocalization.bundle))
                .accessibilityLabel(String(localized: "Clear Filter", bundle: RockxyLocalization.bundle))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text(String(localized: "Key", bundle: RockxyLocalization.bundle))
                .font(.system(size: metrics.fontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            Divider()
            Text(String(localized: "Value", bundle: RockxyLocalization.bundle))
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
        .contentShape(Rectangle())
        .contextMenu {
            headerContextMenu(header)
        }
    }

    @ViewBuilder
    private func headerContextMenu(_ header: HTTPHeader) -> some View {
        Button(String(localized: "Copy Header Name", bundle: RockxyLocalization.bundle)) {
            copyToPasteboard(header.name)
        }
        Button(String(localized: "Copy Header Value", bundle: RockxyLocalization.bundle)) {
            copyToPasteboard(header.value)
        }
        Button(String(localized: "Copy Name: Value", bundle: RockxyLocalization.bundle)) {
            copyToPasteboard("\(header.name): \(header.value)")
        }

        if let source, let coordinator {
            Divider()

            Button(addColumnTitle(for: source)) {
                coordinator.headerColumnStore.addColumn(headerName: header.name, source: source)
            }
            .disabled(
                header.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || coordinator.headerColumnStore.isColumnDefined(headerName: header.name, source: source)
            )

            Divider()

            Button(String(localized: "Filter by Value", bundle: RockxyLocalization.bundle)) {
                if let suggestion = ContextFilterSuggestion.header(header, source: source) {
                    coordinator.applyContextFilter(suggestion)
                }
            }
            .disabled(ContextFilterSuggestion.header(header, source: source) == nil)

            Button(String(localized: "Exclude Value", bundle: RockxyLocalization.bundle)) {
                if let suggestion = ContextFilterSuggestion.header(header, source: source) {
                    coordinator.applyContextFilter(suggestion, excluding: true)
                }
            }
            .disabled(ContextFilterSuggestion.header(header, source: source) == nil)
        }
    }

    private func addColumnTitle(for source: HeaderColumnSource) -> String {
        switch source {
        case .request:
            String(localized: "Add Request Header as Column", bundle: RockxyLocalization.bundle)
        case .response,
             .query,
             .requestBody,
             .responseBody:
            String(localized: "Add Response Header as Column", bundle: RockxyLocalization.bundle)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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

// MARK: - HighlightedInspectorText

struct HighlightedInspectorText: View {
    let text: String
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        Text(text, highlightContext: highlightContext)
    }
}

// MARK: - HeaderDebugBadge

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
                help: String(localized: "Content Security Policy header", bundle: RockxyLocalization.bundle),
                foreground: .red,
                background: .red.opacity(0.12)
            )
        case "access-control-allow-origin",
             "access-control-allow-headers",
             "access-control-allow-methods",
             "access-control-allow-credentials":
            HeaderDebugBadge(
                title: "CORS",
                help: String(localized: "Cross-Origin Resource Sharing header", bundle: RockxyLocalization.bundle),
                foreground: .blue,
                background: .blue.opacity(0.12)
            )
        case "set-cookie",
             "cookie":
            HeaderDebugBadge(
                title: "Cookie",
                help: String(localized: "Cookie header", bundle: RockxyLocalization.bundle),
                foreground: .orange,
                background: .orange.opacity(0.12)
            )
        case "cache-control",
             "etag",
             "expires",
             "last-modified":
            HeaderDebugBadge(
                title: "Cache",
                help: String(localized: "Cache debugging header", bundle: RockxyLocalization.bundle),
                foreground: .indigo,
                background: .indigo.opacity(0.12)
            )
        case "authorization",
             "proxy-authorization",
             "www-authenticate":
            HeaderDebugBadge(
                title: "Auth",
                help: String(localized: "Authentication header", bundle: RockxyLocalization.bundle),
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
                help: String(localized: "Proxy or gateway header", bundle: RockxyLocalization.bundle),
                foreground: .teal,
                background: .teal.opacity(0.12)
            )
        default:
            nil
        }
    }
}
