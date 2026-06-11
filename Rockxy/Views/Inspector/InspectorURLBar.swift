import SwiftUI

/// Horizontal bar at the top of the inspector panel showing the HTTP method badge,
/// status code, and full URL with the host portion highlighted in teal for quick identification.
struct InspectorURLBar: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        HStack(spacing: 8) {
            methodBadge
            if let response = transaction.response {
                StatusCodeBadge(statusCode: response.statusCode)
                Text(response.statusMessage)
                    .font(.system(size: metrics.controlFontSize))
                    .foregroundStyle(.secondary)
            } else {
                transactionStatePill
            }
            urlText
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.Inspector.urlBarBackground)
    }

    // MARK: Private

    @ViewBuilder private var methodBadge: some View {
        if transaction.request.method == "CONNECT" {
            Text(transaction.request.method)
                .font(.system(size: metrics.badgeFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .darkGray))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            StatusBadge(method: transaction.request.method)
        }
    }

    /// Shows ACTIVE/PENDING state when no response has arrived yet.
    private var transactionStatePill: some View {
        let label: String
        let backgroundColor: Color
        switch transaction.state {
        case .active:
            label = String(localized: "ACTIVE")
            backgroundColor = .yellow
        case .pending:
            label = String(localized: "PENDING")
            backgroundColor = .gray
        case .completed,
             .failed,
             .blocked:
            label = ""
            backgroundColor = .clear
        }
        return Text(label)
            .font(.system(size: metrics.badgeFontSize, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(backgroundColor)
            .clipShape(Capsule())
            .opacity(label.isEmpty ? 0 : 1)
    }

    /// Splits the URL into segments to highlight the host portion in teal,
    /// making domain identification faster when scanning many requests.
    private var urlText: some View {
        let urlString = transaction.request.url.absoluteString
        let host = transaction.request.host

        if !highlightContext.isEmpty {
            return AnyView(
                HighlightedInspectorText(text: urlString, highlightContext: highlightContext)
                    .font(.system(size: metrics.controlFontSize, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            )
        }

        return AnyView(HStack(spacing: 0) {
            if let hostRange = urlString.range(of: host), !host.isEmpty {
                Text(urlString[urlString.startIndex ..< hostRange.lowerBound])
                    .font(.system(size: metrics.controlFontSize, design: .monospaced))
                Text(urlString[hostRange])
                    .font(.system(size: metrics.controlFontSize, design: .monospaced))
                    .foregroundStyle(Color.teal)
                Text(urlString[hostRange.upperBound...])
                    .font(.system(size: metrics.controlFontSize, design: .monospaced))
            } else {
                Text(urlString)
                    .font(.system(size: metrics.controlFontSize, design: .monospaced))
            }
        }
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled))
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
