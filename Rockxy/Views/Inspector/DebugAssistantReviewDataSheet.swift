import SwiftUI

/// Exact, read-only view of the redacted context pack shown before an outbound request.
struct DebugAssistantReviewDataSheet: View {
    // MARK: Internal

    let pack: InvestigationContextPack
    let configuration: AssistantProviderConfiguration?
    let trafficScope: AssistantTrafficScope
    let modelAccessEnabled: Bool
    let onSend: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Review Data"))
                    .font(.title2.weight(.semibold))
                Text(
                    headerSubtitle
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    destinationSection
                    redactionSection
                    previewSection
                }
                .padding(20)
            }

            Divider()
            HStack(spacing: 10) {
                Label(footerStatus, systemImage: canSend ? "checkmark.shield" : "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Cancel"), action: onDismiss)
                Button(primaryActionTitle, action: onSend)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 560, idealHeight: 650)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "AI Assistant Review Data"))
    }

    // MARK: Private

    private var canSend: Bool {
        modelAccessEnabled && configuration?.isComplete == true
    }

    private var isLocalExecution: Bool {
        configuration?.executionLocation.isLocal == true
    }

    private var contextPlan: AssistantContextPlan? {
        configuration.map { AssistantContextBudgeter().plan(for: $0) }
    }

    private var headerSubtitle: String {
        if isLocalExecution {
            return String(localized: "Inspect the exact redacted traffic that the local model will process on this Mac.")
        }
        return String(localized: "Inspect the exact redacted traffic before it leaves this Mac.")
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
            return String(localized: "Inference stays on this Mac through the configured local endpoint")
        }
        return String(localized: "Only the reviewed redacted payload will be sent")
    }

    private var destinationSection: some View {
        GroupBox(String(localized: "Outbound Request")) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                reviewRow(
                    String(localized: "Provider"),
                    configuration?.kind.title ?? String(localized: "Not configured")
                )
                reviewRow(String(localized: "Model"), configuration?.model ?? "—")
                reviewRow(
                    String(localized: "Destination"),
                    configuration?.baseURL ?? String(localized: "No outbound request")
                )
                if let region = configuration?.region, !region.isEmpty {
                    reviewRow(String(localized: "Platform / Region"), region)
                }
                reviewRow(
                    String(localized: "Redaction"),
                    configuration?.redactSensitiveData == true
                        ? String(localized: "Enabled")
                        : String(localized: "Unavailable")
                )
                if !isLocalExecution {
                    reviewRow(
                        String(localized: "Provider Storage"),
                        configuration?.storeResponses == true
                            ? String(localized: "Allowed")
                            : String(localized: "Disabled where supported")
                    )
                }
                if let contextWindow = contextPlan?.contextWindowTokens {
                    reviewRow(
                        String(localized: "Context Window"),
                        String(localized: "\(contextWindow.formatted()) tokens")
                    )
                }
                if let outputLimit = contextPlan?.maxOutputTokens {
                    reviewRow(
                        String(localized: "Output Limit"),
                        String(localized: "\(outputLimit.formatted()) tokens")
                    )
                }
                reviewRow(
                    String(localized: "Scope"),
                    scopeDescription
                )
                reviewRow(String(localized: "Access"), String(localized: "Read-only analysis"))
                reviewRow(
                    String(localized: "Outbound Size"),
                    ByteCountFormatter.string(fromByteCount: Int64(pack.manifest.outboundBytes), countStyle: .file)
                )
            }
            .padding(8)
        }
    }

    private var scopeDescription: String {
        switch trafficScope {
        case .selectedOnly:
            String(localized: "\(pack.manifest.requestCount) selected request(s)")
        case .selectedAndRelated:
            String(localized: "\(pack.manifest.requestCount) selected and opted-in related request(s)")
        }
    }

    private var redactionSection: some View {
        GroupBox(String(localized: "Redaction Manifest")) {
            VStack(alignment: .leading, spacing: 8) {
                manifestRow(
                    String(localized: "Sensitive fields redacted"),
                    value: "\(pack.manifest.redactedFieldCount)",
                    systemImage: "checkmark.shield.fill",
                    color: .green
                )
                manifestRow(
                    String(localized: "Payloads truncated"),
                    value: "\(pack.manifest.truncatedBodyCount)",
                    systemImage: "scissors",
                    color: pack.manifest.truncatedBodyCount == 0 ? .secondary : .orange
                )
                manifestRow(
                    String(localized: "Binary payloads omitted"),
                    value: "\(pack.manifest.omittedBinaryBodyCount)",
                    systemImage: "nosign",
                    color: pack.manifest.omittedBinaryBodyCount == 0 ? .secondary : .orange
                )
                manifestRow(
                    String(localized: "Requests outside the bound"),
                    value: "\(pack.manifest.omittedTransactionCount)",
                    systemImage: "square.stack.3d.down.right",
                    color: pack.manifest.omittedTransactionCount == 0 ? .secondary : .orange
                )
            }
            .padding(8)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Exact Data Preview"))
                    .font(.headline)
                Spacer()
                Text(String(localized: "\(pack.manifest.requestCount) requests"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView([.horizontal, .vertical]) {
                Text(pack.preview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .frame(minHeight: 180, idealHeight: 240)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func manifestRow(_ title: String, value: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
