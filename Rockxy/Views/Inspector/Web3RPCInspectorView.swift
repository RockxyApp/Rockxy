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
                    debugIntentCard(info)
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
                String(localized: "No Web3 Detected"),
                systemImage: "network",
                description: String(localized: "Open this tab when a request carries JSON-RPC methods such as eth_call, sendTransaction, or getLatestBlockhash.")
            )
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private func callSummary(_ info: Web3RPCInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                badge(String(localized: "Web3"), color: .green)
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

            summaryMetrics(info)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func summaryMetrics(_ info: Web3RPCInfo) -> some View {
        let provider = summaryMetric(String(localized: "Provider"), value: info.providerHost, color: .primary)
        let requestID = summaryMetric(String(localized: "Request ID"), value: info.requestID ?? String(localized: "Batch"), color: .primary)
        let chain = summaryMetric(String(localized: "Chain"), value: info.chainHint?.chainID ?? String(localized: "Unknown"), color: .primary)
        let payload = summaryMetric(String(localized: "Payload"), value: payloadSummary(info), color: .primary)

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                provider
                requestID
                chain
                payload
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    provider
                    requestID
                }
                HStack(alignment: .top, spacing: 8) {
                    chain
                    payload
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                provider
                requestID
                chain
                payload
            }
        }
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

    private func debugIntentCard(_ info: Web3RPCInfo) -> some View {
        section(String(localized: "Debug Intent"), badgeText: info.debugIntent.displayName) {
            VStack(spacing: 0) {
                metadataRow(String(localized: "Intent"), value: info.debugIntent.explanation, color: info.debugIntent.color)
                Divider()
                metadataRow(String(localized: "Outcome"), value: outcomeText(info), color: outcomeColor(info))
                Divider()
                metadataRow(String(localized: "Next Check"), value: nextCheckText(info), color: .primary)
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

    private func summaryMetric(_ label: String, value: String, color: Color) -> some View {
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
        .frame(minWidth: 136, maxWidth: .infinity, alignment: .leading)
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

    private func outcomeText(_ info: Web3RPCInfo) -> String {
        if let error = info.error {
            if let code = error.code, let message = error.message {
                return String(localized: "RPC \(code): \(message)")
            }
            return error.message ?? String(localized: "Provider returned a JSON-RPC error")
        }

        if let statusCode = transaction.response?.statusCode,
           statusCode >= 400
        {
            return String(localized: "HTTP \(statusCode) from provider")
        }

        if let batch = info.batch {
            return batch.errorCount == 0 ?
                String(localized: "\(batch.web3RequestCount) batch calls completed") :
                String(localized: "\(batch.errorCount) of \(batch.web3RequestCount) batch calls failed")
        }

        return String(localized: "RPC completed")
    }

    private func outcomeColor(_ info: Web3RPCInfo) -> Color {
        if info.error != nil {
            return .red
        }
        if let statusCode = transaction.response?.statusCode,
           statusCode >= 400
        {
            return .red
        }
        if let batch = info.batch,
           batch.errorCount > 0
        {
            return .orange
        }
        return .green
    }

    private func nextCheckText(_ info: Web3RPCInfo) -> String {
        if info.error != nil {
            switch info.debugIntent {
            case .broadcast:
                return String(localized: "Check raw transaction/signature, wallet signer state, nonce, gas, and provider rejection details.")
            case .batch:
                return String(localized: "Open the raw response and match failed batch ids to their request methods.")
            case .simulation:
                return String(localized: "Compare call params, block tag, gas estimate, and revert message between attempts.")
            default:
                return String(localized: "Check provider error code/message, request id, auth headers, and retry timing.")
            }
        }

        switch info.debugIntent {
        case .batch:
            return String(localized: "Verify each subcall belongs together and watch for mixed read/write calls in one request.")
        case .broadcast:
            return String(localized: "Follow the returned transaction hash/signature into receipt or confirmation polling.")
        case .simulation:
            return String(localized: "Compare block tag, calldata, gas, and returned value before sending a transaction.")
        case .logs:
            return String(localized: "Check block range, topic filters, returned tx hash, and receipt correlation.")
        case .subscription:
            return String(localized: "Follow subscribe id, notifications, unsubscribe, and any dropped WebSocket frames.")
        case .provider:
            return String(localized: "Use this as provider/chain baseline before comparing app calls.")
        case .read:
            return String(localized: "Compare account, commitment/block tag, and result size across providers or retries.")
        case .unknown:
            return String(localized: "Inspect raw JSON-RPC params and response body to classify this method.")
        }
    }
}

private extension Web3RPCDebugIntent {
    var displayName: String {
        switch self {
        case .batch:
            String(localized: "Batch")
        case .broadcast:
            String(localized: "Broadcast")
        case .simulation:
            String(localized: "Simulation")
        case .logs:
            String(localized: "Logs")
        case .subscription:
            String(localized: "Subscription")
        case .provider:
            String(localized: "Provider")
        case .read:
            String(localized: "Read")
        case .unknown:
            String(localized: "Unknown")
        }
    }

    var explanation: String {
        switch self {
        case .batch:
            String(localized: "Multiple JSON-RPC calls shipped together")
        case .broadcast:
            String(localized: "Write-like transaction/signature path")
        case .simulation:
            String(localized: "Dry-run or gas/compute estimation")
        case .logs:
            String(localized: "Event, receipt, or transaction lookup")
        case .subscription:
            String(localized: "Realtime subscription lifecycle")
        case .provider:
            String(localized: "Provider, chain, or node baseline")
        case .read:
            String(localized: "State read with no expected write")
        case .unknown:
            String(localized: "Method needs manual inspection")
        }
    }

    var color: Color {
        switch self {
        case .broadcast:
            .orange
        case .simulation:
            .blue
        case .logs:
            .purple
        case .subscription:
            .indigo
        case .batch:
            .teal
        case .provider:
            .secondary
        case .read:
            .green
        case .unknown:
            .secondary
        }
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
            "EVM RPC"
        case .solana:
            "Solana RPC"
        }
    }
}
