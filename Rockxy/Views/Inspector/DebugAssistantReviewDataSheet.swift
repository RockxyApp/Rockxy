import SwiftUI

/// Exact, read-only view of the redacted context pack shown before an outbound request.
struct DebugAssistantReviewDataSheet: View {
    // MARK: Internal

    let pack: InvestigationContextPack
    let configuration: AssistantProviderConfiguration?
    let trafficScope: AssistantTrafficScope
    let modelAccessEnabled: Bool
    let conversationPreview: String
    let onSend: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            actionBar
        }
        .font(toolMetrics.font())
        .frame(width: sheetWidth, height: sheetHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "AI Assistant Review Data"))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var sheetWidth: CGFloat {
        max(760, toolMetrics.bodyFontSize * 16 + 520)
    }

    private var sheetHeight: CGFloat {
        max(620, toolMetrics.bodyFontSize * 8 + 500)
    }

    private var canSend: Bool {
        modelAccessEnabled && configuration?.isComplete == true
    }

    private var isLocalExecution: Bool {
        configuration?.executionLocation.isLocal == true
    }

    private var contextPlan: AssistantContextPlan? {
        configuration.map { AssistantContextBudgeter().plan(for: $0) }
    }

    private var previewEditorSettings: InspectorTextEditorSettings {
        var settings = toolMetrics.codeEditorSettings
        settings.wordWrap = true
        return settings
    }

    private var headerSubtitle: String {
        if isLocalExecution {
            return String(localized: "Confirm the redacted traffic and conversation before local inference begins.")
        }
        return String(localized: "Confirm the exact redacted traffic before it leaves this Mac.")
    }

    private var primaryActionTitle: String {
        isLocalExecution ? String(localized: "Run Locally") : String(localized: "Send Redacted Data")
    }

    private var footerStatus: String {
        if !modelAccessEnabled {
            return String(localized: "Model access is disabled in AI Assistant Settings")
        }
        if configuration?.isComplete != true {
            return String(localized: "Configure a provider and model in AI Assistant Settings")
        }
        if isLocalExecution {
            return String(localized: "Inference uses the configured local endpoint")
        }
        return String(localized: "Only the reviewed redacted payload will be sent")
    }

    private var scopeDescription: String {
        switch trafficScope {
        case .selectedOnly:
            String(localized: "\(pack.manifest.requestCount) selected request(s)")
        case .selectedAndRelated:
            String(localized: "\(pack.manifest.requestCount) selected and opted-in related request(s)")
        }
    }

    private var reviewDetails: [ReviewDetail] {
        var details = [
            ReviewDetail(
                title: String(localized: "Provider"),
                value: configuration?.kind.title ?? String(localized: "Not configured")
            ),
            ReviewDetail(
                title: String(localized: "Model"),
                value: configuration?.model ?? "—"
            ),
            ReviewDetail(
                title: String(localized: "Destination"),
                value: configuration?.baseURL ?? String(localized: "No outbound request")
            ),
            ReviewDetail(
                title: String(localized: "Scope"),
                value: scopeDescription
            ),
            ReviewDetail(
                title: String(localized: "Redaction"),
                value: configuration?.redactSensitiveData == true
                    ? String(localized: "Enabled")
                    : String(localized: "Unavailable")
            ),
            ReviewDetail(
                title: String(localized: "Access"),
                value: String(localized: "Read-only analysis")
            ),
            ReviewDetail(
                title: String(localized: "Outbound Size"),
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(pack.manifest.outboundBytes),
                    countStyle: .file
                )
            ),
        ]
        if let contextWindow = contextPlan?.contextWindowTokens {
            details.append(ReviewDetail(
                title: String(localized: "Context Window"),
                value: String(localized: "\(contextWindow.formatted()) tokens")
            ))
        }
        if let outputLimit = contextPlan?.maxOutputTokens {
            details.append(ReviewDetail(
                title: String(localized: "Output Limit"),
                value: String(localized: "\(outputLimit.formatted()) tokens")
            ))
        }
        if !isLocalExecution {
            details.append(ReviewDetail(
                title: String(localized: "Provider Storage"),
                value: configuration?.storeResponses == true
                    ? String(localized: "Allowed")
                    : String(localized: "Disabled where supported")
            ))
        }
        if let region = configuration?.region, !region.isEmpty {
            details.append(ReviewDetail(
                title: String(localized: "Platform / Region"),
                value: region
            ))
        }
        return details
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isLocalExecution ? "lock.shield" : "arrow.up.forward.app")
                .font(.system(size: toolMetrics.compactIconFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Review Data"))
                    .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))
                Text(headerSubtitle)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                destinationSection
                redactionSection
                conversationSection
                previewSection
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.vertical, toolMetrics.formVerticalPadding)
        }
    }

    private var destinationSection: some View {
        reviewSection(String(localized: "Request Summary")) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150), alignment: .topLeading),
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(reviewDetails) { detail in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(detail.title)
                            .font(toolMetrics.metadataFont(weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(detail.value)
                            .font(toolMetrics.font())
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var redactionSection: some View {
        reviewSection(String(localized: "Redaction Manifest")) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                GridRow {
                    manifestRow(
                        String(localized: "Sensitive fields redacted"),
                        value: pack.manifest.redactedFieldCount,
                        systemImage: "checkmark.shield.fill",
                        color: .green
                    )
                    manifestRow(
                        String(localized: "Payloads truncated"),
                        value: pack.manifest.truncatedBodyCount,
                        systemImage: "scissors",
                        color: pack.manifest.truncatedBodyCount == 0 ? .secondary : .orange
                    )
                }
                GridRow {
                    manifestRow(
                        String(localized: "Binary payloads omitted"),
                        value: pack.manifest.omittedBinaryBodyCount,
                        systemImage: "nosign",
                        color: pack.manifest.omittedBinaryBodyCount == 0 ? .secondary : .orange
                    )
                    manifestRow(
                        String(localized: "Requests outside the bound"),
                        value: pack.manifest.omittedTransactionCount,
                        systemImage: "square.stack.3d.down.right",
                        color: pack.manifest.omittedTransactionCount == 0 ? .secondary : .orange
                    )
                }
            }
        }
    }

    private var conversationSection: some View {
        reviewSection(String(localized: "Conversation Sent to Model")) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(conversationPreview)
                    .font(toolMetrics.secondaryFont())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(String(localized: "Exact Data Preview"))
                    .font(toolMetrics.font(weight: .semibold))
                Spacer()
                Text(String(localized: "\(pack.manifest.requestCount) requests"))
                    .font(toolMetrics.metadataFont())
                    .foregroundStyle(.secondary)
            }

            InspectorBodyTextEditor(
                text: pack.preview,
                editorID: "debug-assistant-review-\(pack.preview.hashValue)",
                editorSettings: previewEditorSettings,
                isEditable: false
            )
            .frame(minHeight: 210, idealHeight: 260)
            .overlay {
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Label(footerStatus, systemImage: canSend ? "checkmark.shield" : "lock.shield")
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 12)

            Button(String(localized: "Cancel"), action: onDismiss)
                .keyboardShortcut(.cancelAction)

            Button(primaryActionTitle, action: onSend)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .frame(minHeight: toolMetrics.footerControlHeight + 20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func reviewSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(toolMetrics.font(weight: .semibold))

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func manifestRow(
        _ title: String,
        value: Int,
        systemImage: String,
        color: Color
    )
        -> some View
    {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(title)
                .font(toolMetrics.secondaryFont())
            Spacer(minLength: 8)
            Text(value.formatted())
                .font(toolMetrics.secondaryFont())
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReviewDetail: Identifiable {
    let title: String
    let value: String

    var id: String {
        title
    }
}
