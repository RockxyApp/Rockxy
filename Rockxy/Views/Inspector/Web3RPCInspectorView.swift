import SwiftUI

// MARK: - Web3RPCInspectorView

/// Displays bounded Web3 JSON-RPC metadata extracted from visible HTTP request and response bodies.
struct Web3RPCInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        if transaction.web3RPCInfo != nil || transaction.x402Info != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let info = transaction.web3RPCInfo {
                        callSummary(info)
                        debugIntentCard(info)
                        metadataGrid(info)
                        batchSummary(info.batch)
                        errorStrip(info.error)
                    }
                    if let payment = transaction.x402Info {
                        paymentSection(payment)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            InspectorEmptyStateView(
                String(localized: "No Web3 Detected", bundle: RockxyLocalization.bundle),
                systemImage: "network",
                description: String(
                    localized: "Open this tab when a request carries JSON-RPC methods such as eth_call, sendTransaction, or getLatestBlockhash.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var batchHeaderRow: some View {
        HStack(spacing: 0) {
            headerCell(String(localized: "Field", bundle: RockxyLocalization.bundle), width: 112)
            headerCell(String(localized: "Value", bundle: RockxyLocalization.bundle), width: nil)
            headerCell(String(localized: "Detail", bundle: RockxyLocalization.bundle), width: 160)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func callSummary(_ info: Web3RPCInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                badge(String(localized: "Web3", bundle: RockxyLocalization.bundle), color: .green)
                badge(info.family.displayName, color: .blue)
                if let statusCode = transaction.response?.statusCode {
                    badge(
                        String(localized: "HTTP \(statusCode)", bundle: RockxyLocalization.bundle),
                        color: statusCode < 400 ? .green : .red
                    )
                }
                if let error = info.error {
                    badge(
                        error.code.map { String(localized: "RPC \($0)", bundle: RockxyLocalization.bundle) } ?? String(
                            localized: "RPC Error",
                            bundle: RockxyLocalization.bundle
                        ),
                        color: .red
                    )
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Method", bundle: RockxyLocalization.bundle))
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
        let provider = summaryMetric(
            String(localized: "Provider", bundle: RockxyLocalization.bundle),
            value: info.providerHost,
            color: .primary
        )
        let requestID = summaryMetric(
            String(localized: "Request ID", bundle: RockxyLocalization.bundle),
            value: info.requestID ?? String(localized: "Batch", bundle: RockxyLocalization.bundle),
            color: .primary
        )
        let chain = summaryMetric(
            String(localized: "Chain", bundle: RockxyLocalization.bundle),
            value: info.chainHint?.chainID ?? String(localized: "Unknown", bundle: RockxyLocalization.bundle),
            color: .primary
        )
        let payload = summaryMetric(
            String(localized: "Payload", bundle: RockxyLocalization.bundle),
            value: payloadSummary(info),
            color: .primary
        )

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

    /// x402 payment lifecycle hints. Only field names are listed for sensitive values; the
    /// payment proof, challenge, and receipt themselves are never shown here.
    private func paymentSection(_ payment: X402Info) -> some View {
        section(
            String(localized: "Payment (x402)", bundle: RockxyLocalization.bundle),
            badgeText: payment.isX402Like ? payment.version.map { "v\($0)" } : nil
        ) {
            VStack(spacing: 0) {
                metadataRow(
                    String(localized: "Stage", bundle: RockxyLocalization.bundle),
                    value: payment.stage.displayName,
                    color: payment.stage.color
                )
                Divider()
                metadataRow(
                    String(localized: "Proof Sent", bundle: RockxyLocalization.bundle),
                    value: payment.hasPaymentProof
                        ? String(localized: "Yes", bundle: RockxyLocalization.bundle)
                        : String(localized: "No", bundle: RockxyLocalization.bundle)
                )
                Divider()
                metadataRow(
                    String(localized: "Requirements", bundle: RockxyLocalization.bundle),
                    value: payment.hasChallenge
                        ? String(localized: "Included", bundle: RockxyLocalization.bundle)
                        : String(localized: "Not seen", bundle: RockxyLocalization.bundle)
                )
                if payment.parseState == .malformed {
                    Divider()
                    metadataRow(
                        String(localized: "Body", bundle: RockxyLocalization.bundle),
                        value: String(
                            localized: "Not valid JSON; hints come from text",
                            bundle: RockxyLocalization.bundle
                        ),
                        color: .orange
                    )
                }
                if !payment.redactionFields.isEmpty {
                    Divider()
                    metadataRow(
                        String(localized: "Sensitive", bundle: RockxyLocalization.bundle),
                        value: payment.redactionFields.joined(separator: ", "),
                        color: .orange
                    )
                }
            }
        }
        .accessibilityIdentifier("web3.x402Payment")
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
        section(
            String(localized: "Debug Intent", bundle: RockxyLocalization.bundle),
            badgeText: info.debugIntent.displayName
        ) {
            VStack(spacing: 0) {
                metadataRow(
                    String(localized: "Intent", bundle: RockxyLocalization.bundle),
                    value: info.debugIntent.explanation,
                    color: info.debugIntent.color
                )
                Divider()
                metadataRow(
                    String(localized: "Outcome", bundle: RockxyLocalization.bundle),
                    value: outcomeText(info),
                    color: outcomeColor(info)
                )
                Divider()
                metadataRow(
                    String(localized: "Next Check", bundle: RockxyLocalization.bundle),
                    value: nextCheckText(info),
                    color: .primary
                )
            }
        }
    }

    private func callSection(_ info: Web3RPCInfo) -> some View {
        section(String(localized: "Call", bundle: RockxyLocalization.bundle)) {
            metadataRow(
                String(localized: "Family", bundle: RockxyLocalization.bundle),
                value: info.family.longDisplayName
            )
            metadataRow(
                String(localized: "Method", bundle: RockxyLocalization.bundle),
                value: info.method ?? batchMethodSummary(info.batch)
            )
            metadataRow(String(localized: "Provider", bundle: RockxyLocalization.bundle), value: info.providerHost)
            metadataRow(
                String(localized: "Request", bundle: RockxyLocalization.bundle),
                value: sizeText(info.requestPayloadSize)
            )
        }
    }

    private func resultSection(_ info: Web3RPCInfo) -> some View {
        section(String(localized: "Result", bundle: RockxyLocalization.bundle)) {
            metadataRow(
                String(localized: "Status", bundle: RockxyLocalization.bundle),
                value: statusText(info),
                color: info.error == nil ? .green : .red
            )
            metadataRow(
                String(localized: "Response", bundle: RockxyLocalization.bundle),
                value: sizeText(info.responsePayloadSize)
            )
            metadataRow(
                String(localized: "Block Hint", bundle: RockxyLocalization.bundle),
                value: info.blockIdentifier ?? String(localized: "Not captured", bundle: RockxyLocalization.bundle)
            )
            metadataRow(
                String(localized: "Tx Hash", bundle: RockxyLocalization.bundle),
                value: info.transactionHash ?? String(localized: "Not returned", bundle: RockxyLocalization.bundle)
            )
        }
    }

    @ViewBuilder
    private func batchSummary(_ batch: Web3RPCBatchSummary?) -> some View {
        if let batch {
            section(
                String(localized: "Batch Calls", bundle: RockxyLocalization.bundle),
                badgeText: String(AttributedString(
                    localized: "^[\(batch.web3RequestCount) call](inflect: true)",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters)
            ) {
                VStack(spacing: 0) {
                    batchHeaderRow
                    Divider()
                    batchMetricRow(
                        String(localized: "Requests", bundle: RockxyLocalization.bundle),
                        value: CountFormatter.format(batch.requestCount),
                        detail: String(
                            localized: "\(batch.web3RequestCount) Web3 methods",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    Divider()
                    batchMetricRow(
                        String(localized: "Responses", bundle: RockxyLocalization.bundle),
                        value: batch.responseCount.map(String.init) ?? String(
                            localized: "Not captured",
                            bundle: RockxyLocalization.bundle
                        ),
                        detail: batch.errorCount == 0 ? String(
                            localized: "No RPC errors",
                            bundle: RockxyLocalization.bundle
                        ) : String(AttributedString(
                            localized: "^[\(batch.errorCount) RPC error](inflect: true)",
                            bundle: RockxyLocalization.bundle,
                            locale: RockxyLocalization.locale
                        ).characters)
                    )
                    if !batch.methods.isEmpty {
                        Divider()
                        batchMetricRow(
                            String(localized: "Methods", bundle: RockxyLocalization.bundle),
                            value: batch.methods.joined(separator: ", "),
                            detail: batch.methods.count >= 6 ? String(
                                localized: "First 6 shown",
                                bundle: RockxyLocalization.bundle
                            ) : String(localized: "Detected", bundle: RockxyLocalization.bundle)
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
                badge(
                    error.code.map { String(localized: "RPC \($0)", bundle: RockxyLocalization.bundle) } ?? String(
                        localized: "RPC Error",
                        bundle: RockxyLocalization.bundle
                    ),
                    color: .red
                )
                Text(error.message ?? String(
                    localized: "Provider returned a JSON-RPC error.",
                    bundle: RockxyLocalization.bundle
                ))
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

    private func batchMetricRow(_ label: String, value: String, detail: String) -> some View {
        HStack(spacing: 0) {
            frameCell(label, width: 112, color: .secondary, monospaced: false)
            frameCell(value, width: nil)
            frameCell(detail, width: 160, color: .secondary, monospaced: false)
        }
    }

    private func section(
        _ title: String,
        badgeText: String? = nil,
        @ViewBuilder content: () -> some View
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
            return String(localized: "Unknown method", bundle: RockxyLocalization.bundle)
        }
        if let first = batch.methods.first {
            return batch.methods.count > 1 ? String(
                localized: "\(first) + \(batch.methods.count - 1)",
                bundle: RockxyLocalization.bundle
            ) : first
        }
        return String(AttributedString(
            localized: "^[\(batch.web3RequestCount) call](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
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
            String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        }
    }

    private func sizeText(_ bytes: Int?) -> String {
        bytes.map(SizeFormatter.format(bytes:)) ?? String(localized: "Not captured", bundle: RockxyLocalization.bundle)
    }

    private func statusText(_ info: Web3RPCInfo) -> String {
        if info.error != nil {
            return String(localized: "RPC error", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "Success", bundle: RockxyLocalization.bundle)
    }

    private func outcomeText(_ info: Web3RPCInfo) -> String {
        if let error = info.error {
            if let code = error.code, let message = error.message {
                return String(localized: "RPC \(code): \(message)", bundle: RockxyLocalization.bundle)
            }
            return error.message ?? String(
                localized: "Provider returned a JSON-RPC error",
                bundle: RockxyLocalization.bundle
            )
        }

        if let statusCode = transaction.response?.statusCode,
           statusCode >= 400
        {
            return String(localized: "HTTP \(statusCode) from provider", bundle: RockxyLocalization.bundle)
        }

        if let batch = info.batch {
            return batch.errorCount == 0 ?
                String(
                    localized: "\(batch.web3RequestCount) batch calls completed",
                    bundle: RockxyLocalization.bundle
                ) :
                String(
                    localized: "\(batch.errorCount) of \(batch.web3RequestCount) batch calls failed",
                    bundle: RockxyLocalization.bundle
                )
        }

        return String(localized: "RPC completed", bundle: RockxyLocalization.bundle)
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
                return String(
                    localized: "Check raw transaction/signature, wallet signer state, nonce, gas, and provider rejection details.",
                    bundle: RockxyLocalization.bundle
                )
            case .batch:
                return String(
                    localized: "Open the raw response and match failed batch ids to their request methods.",
                    bundle: RockxyLocalization.bundle
                )
            case .simulation:
                return String(
                    localized: "Compare call params, block tag, gas estimate, and revert message between attempts.",
                    bundle: RockxyLocalization.bundle
                )
            default:
                return String(
                    localized: "Check provider error code/message, request id, auth headers, and retry timing.",
                    bundle: RockxyLocalization.bundle
                )
            }
        }

        switch info.debugIntent {
        case .batch:
            return String(
                localized: "Verify each subcall belongs together and watch for mixed read/write calls in one request.",
                bundle: RockxyLocalization.bundle
            )
        case .broadcast:
            return String(
                localized: "Follow the returned transaction hash/signature into receipt or confirmation polling.",
                bundle: RockxyLocalization.bundle
            )
        case .simulation:
            return String(
                localized: "Compare block tag, calldata, gas, and returned value before sending a transaction.",
                bundle: RockxyLocalization.bundle
            )
        case .logs:
            return String(
                localized: "Check block range, topic filters, returned tx hash, and receipt correlation.",
                bundle: RockxyLocalization.bundle
            )
        case .subscription:
            return String(
                localized: "Follow subscribe id, notifications, unsubscribe, and any dropped WebSocket frames.",
                bundle: RockxyLocalization.bundle
            )
        case .provider:
            return String(
                localized: "Use this as provider/chain baseline before comparing app calls.",
                bundle: RockxyLocalization.bundle
            )
        case .read:
            return String(
                localized: "Compare account, commitment/block tag, and result size across providers or retries.",
                bundle: RockxyLocalization.bundle
            )
        case .unknown:
            return String(
                localized: "Inspect raw JSON-RPC params and response body to classify this method.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

private extension Web3RPCDebugIntent {
    var displayName: String {
        switch self {
        case .batch:
            String(localized: "Batch", bundle: RockxyLocalization.bundle)
        case .broadcast:
            String(localized: "Broadcast", bundle: RockxyLocalization.bundle)
        case .simulation:
            String(localized: "Simulation", bundle: RockxyLocalization.bundle)
        case .logs:
            String(localized: "Logs", bundle: RockxyLocalization.bundle)
        case .subscription:
            String(localized: "Subscription", bundle: RockxyLocalization.bundle)
        case .provider:
            String(localized: "Provider", bundle: RockxyLocalization.bundle)
        case .read:
            String(localized: "Read", bundle: RockxyLocalization.bundle)
        case .unknown:
            String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        }
    }

    var explanation: String {
        switch self {
        case .batch:
            String(localized: "Multiple JSON-RPC calls shipped together", bundle: RockxyLocalization.bundle)
        case .broadcast:
            String(localized: "Write-like transaction/signature path", bundle: RockxyLocalization.bundle)
        case .simulation:
            String(localized: "Dry-run or gas/compute estimation", bundle: RockxyLocalization.bundle)
        case .logs:
            String(localized: "Event, receipt, or transaction lookup", bundle: RockxyLocalization.bundle)
        case .subscription:
            String(localized: "Realtime subscription lifecycle", bundle: RockxyLocalization.bundle)
        case .provider:
            String(localized: "Provider, chain, or node baseline", bundle: RockxyLocalization.bundle)
        case .read:
            String(localized: "State read with no expected write", bundle: RockxyLocalization.bundle)
        case .unknown:
            String(localized: "Method needs manual inspection", bundle: RockxyLocalization.bundle)
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

// MARK: - X402Stage + Display

extension X402Stage {
    var displayName: String {
        switch self {
        case .ordinaryPaymentRequired:
            String(localized: "HTTP 402 without x402 details", bundle: RockxyLocalization.bundle)
        case .paymentRequired:
            String(localized: "Payment required", bundle: RockxyLocalization.bundle)
        case .paymentProofSubmitted:
            String(localized: "Payment sent, awaiting result", bundle: RockxyLocalization.bundle)
        case .paymentAccepted:
            String(localized: "Payment accepted", bundle: RockxyLocalization.bundle)
        case .providerError:
            String(localized: "Payment rejected", bundle: RockxyLocalization.bundle)
        }
    }

    var color: Color {
        switch self {
        case .ordinaryPaymentRequired,
             .paymentRequired:
            .orange
        case .paymentProofSubmitted:
            .blue
        case .paymentAccepted:
            .green
        case .providerError:
            .red
        }
    }
}
