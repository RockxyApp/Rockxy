import SwiftUI

// MARK: - Web3RPCInspectorView

/// Displays bounded Web3 JSON-RPC metadata extracted from visible HTTP request and response bodies.
struct Web3RPCInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        if let info = transaction.web3RPCInfo {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    callSummary(info)
                    metadataGrid(info)
                    batchSummary(info.batch)
                    errorStrip(info.error)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            InspectorEmptyStateView(
                String(localized: "No Web3 RPC Data"),
                systemImage: "network",
                description: String(localized: "This transaction does not include Web3 JSON-RPC metadata.")
            )
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private func callSummary(_ info: Web3RPCInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                badge(String(localized: "Web3 JSON-RPC"), color: .purple)
                badge(info.family.displayName, color: .blue)
                if let statusCode = transaction.response?.statusCode {
                    badge(String(localized: "HTTP \(statusCode)"), color: statusCode < 400 ? .green : .red)
                }
                if let error = info.error {
                    badge(error.code.map { String(localized: "RPC \($0)") } ?? String(localized: "RPC Error"), color: .red)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Method"))
                    .font(.system(size: metrics.metadataFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(info.method ?? batchMethodSummary(info.batch))
                    .font(.system(size: metrics.primaryFontSize, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 8) {
                metric(String(localized: "Provider"), value: info.providerHost, color: .primary)
                metric(String(localized: "Request ID"), value: info.requestID ?? String(localized: "Batch"), color: .primary)
                metric(String(localized: "Chain"), value: info.chainHint?.chainID ?? String(localized: "Unknown"), color: .primary)
                metric(String(localized: "Payload"), value: payloadSummary(info), color: .primary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private var summaryColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading),
        ]
    }

    private func metadataGrid(_ info: Web3RPCInfo) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                callSection(info)
                resultSection(info)
            }
            VStack(alignment: .leading, spacing: 12) {
                callSection(info)
                resultSection(info)
            }
        }
    }

    private func callSection(_ info: Web3RPCInfo) -> some View {
        section(String(localized: "Call")) {
            metadataRow(String(localized: "Family"), value: info.family.longDisplayName)
            metadataRow(String(localized: "Method"), value: info.method ?? batchMethodSummary(info.batch))
            metadataRow(String(localized: "Provider"), value: info.providerHost)
            metadataRow(String(localized: "Request"), value: sizeText(info.requestPayloadSize))
        }
    }

    private func resultSection(_ info: Web3RPCInfo) -> some View {
        section(String(localized: "Result")) {
            metadataRow(String(localized: "Status"), value: statusText(info), color: info.error == nil ? .green : .red)
            metadataRow(String(localized: "Response"), value: sizeText(info.responsePayloadSize))
            metadataRow(String(localized: "Block Hint"), value: info.blockIdentifier ?? String(localized: "Not captured"))
            metadataRow(String(localized: "Tx Hash"), value: info.transactionHash ?? String(localized: "Not returned"))
        }
    }

    @ViewBuilder
    private func batchSummary(_ batch: Web3RPCBatchSummary?) -> some View {
        if let batch {
            section(String(localized: "Batch Calls"), badgeText: String(localized: "\(batch.web3RequestCount) calls")) {
                VStack(spacing: 0) {
                    batchHeaderRow
                    Divider()
                    batchMetricRow(
                        String(localized: "Requests"),
                        value: "\(batch.requestCount)",
                        detail: String(localized: "\(batch.web3RequestCount) Web3 methods")
                    )
                    Divider()
                    batchMetricRow(
                        String(localized: "Responses"),
                        value: batch.responseCount.map(String.init) ?? String(localized: "Not captured"),
                        detail: batch.errorCount == 0 ? String(localized: "No RPC errors") : String(localized: "\(batch.errorCount) RPC errors")
                    )
                    if !batch.methods.isEmpty {
                        Divider()
                        batchMetricRow(
                            String(localized: "Methods"),
                            value: batch.methods.joined(separator: ", "),
                            detail: batch.methods.count >= 6 ? String(localized: "First 6 shown") : String(localized: "Detected")
                        )
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private func errorStrip(_ error: Web3RPCError?) -> some View {
        if let error {
            HStack(alignment: .top, spacing: 10) {
                badge(error.code.map { String(localized: "RPC \($0)") } ?? String(localized: "RPC Error"), color: .red)
                Text(error.message ?? String(localized: "Provider returned a JSON-RPC error."))
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.red.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.35), lineWidth: 0.5)
            }
        }
    }

    private var batchHeaderRow: some View {
        HStack(spacing: 0) {
            headerCell(String(localized: "Field"), width: 112)
            headerCell(String(localized: "Value"), width: nil)
            headerCell(String(localized: "Detail"), width: 160)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func batchMetricRow(_ label: String, value: String, detail: String) -> some View {
        HStack(spacing: 0) {
            frameCell(label, width: 112, color: .secondary, monospaced: false)
            frameCell(value, width: nil)
            frameCell(detail, width: 160, color: .secondary, monospaced: false)
        }
    }

    private func section<Content: View>(
        _ title: String,
        badgeText: String? = nil,
        @ViewBuilder content: () -> Content
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: metrics.primaryFontSize, weight: .semibold))
                if let badgeText {
                    badge(badgeText, color: .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func metadataRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: metrics.metadataFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            Divider()
            Text(value)
                .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
    }

    private func headerCell(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(.system(size: metrics.metadataFontSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func frameCell(
        _ text: String,
        width: CGFloat?,
        color: Color = .primary,
        monospaced: Bool = true
    )
        -> some View
    {
        Text(text)
            .font(.system(size: metrics.metadataFontSize, design: monospaced ? .monospaced : .default))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: metrics.badgeFontSize, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func metric(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: metrics.badgeFontSize, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func batchMethodSummary(_ batch: Web3RPCBatchSummary?) -> String {
        guard let batch else {
            return String(localized: "Unknown method")
        }
        if let first = batch.methods.first {
            return batch.methods.count > 1 ? String(localized: "\(first) + \(batch.methods.count - 1)") : first
        }
        return String(localized: "\(batch.web3RequestCount) calls")
    }

    private func payloadSummary(_ info: Web3RPCInfo) -> String {
        switch (info.requestPayloadSize, info.responsePayloadSize) {
        case let (.some(request), .some(response)):
            "\(SizeFormatter.format(bytes: request)) / \(SizeFormatter.format(bytes: response))"
        case let (.some(request), .none):
            SizeFormatter.format(bytes: request)
        case let (.none, .some(response)):
            SizeFormatter.format(bytes: response)
        case (.none, .none):
            String(localized: "Unknown")
        }
    }

    private func sizeText(_ bytes: Int?) -> String {
        bytes.map(SizeFormatter.format(bytes:)) ?? String(localized: "Not captured")
    }

    private func statusText(_ info: Web3RPCInfo) -> String {
        if info.error != nil {
            return String(localized: "RPC error")
        }
        return String(localized: "Success")
    }
}

private extension Web3RPCFamily {
    var displayName: String {
        switch self {
        case .evm:
            "EVM"
        case .solana:
            "Solana"
        }
    }

    var longDisplayName: String {
        switch self {
        case .evm:
            "EVM JSON-RPC"
        case .solana:
            "Solana JSON-RPC"
        }
    }
}
