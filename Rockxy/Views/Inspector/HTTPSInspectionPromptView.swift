import AppKit
import SwiftUI

// MARK: - HTTPSInspectionPromptView

/// Compact controls for CONNECT tunnels whose payload was not decrypted.
struct HTTPSInspectionPromptView: View {
    // MARK: Internal

    let prompt: HTTPSInspectionPromptModel
    let onAction: (HTTPSInspectionPromptAction) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                header

                if let insight = prompt.insight {
                    connectionInsight(insight)
                }

                if prompt.requiresCertificateSetup {
                    certificateAction
                } else {
                    scopeControls
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var isInsightExpanded = false

    private var promptActionLabelWidth: CGFloat {
        max(78, metrics.controlFontSize * 6.25)
    }

    private var scopeFooter: String {
        if prompt.hostScope?.state == .ready {
            return String(
                localized: "Ready for new connections. Repeat the request; WebSocket and streaming connections must reconnect.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(localized: "This response stays encrypted.", bundle: RockxyLocalization.bundle)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if prompt.requiresCertificateSetup {
                Image(systemName: "exclamationmark.lock.fill")
                    .font(.system(size: metrics.primaryFontSize, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }

            Text(
                prompt.requiresCertificateSetup
                    ? String(localized: "Certificate Required", bundle: RockxyLocalization.bundle)
                    : String(localized: "Encrypted HTTPS", bundle: RockxyLocalization.bundle)
            )
            .font(.system(size: metrics.controlFontSize, weight: .semibold))

            Spacer(minLength: 8)

            Button {
                onAction(.openSSLProxyingList)
            } label: {
                Label(String(localized: "Settings…", bundle: RockxyLocalization.bundle), systemImage: "gearshape")
                    .lineLimit(1)
                    .frame(minWidth: promptActionLabelWidth)
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)
            .fixedSize()
            .help(String(localized: "Open HTTPS Decryption Settings", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Open HTTPS Decryption Settings", bundle: RockxyLocalization.bundle))
        }
    }

    private var certificateAction: some View {
        Button(String(localized: "Install & Trust…", bundle: RockxyLocalization.bundle)) {
            if let action = prompt.certificateAction {
                onAction(action)
            }
        }
        .rockxyGlassButtonStyle(prominent: true)
        .controlSize(.small)
        .accessibilityHint(String(
            localized: "Installs and trusts the Rockxy root certificate",
            bundle: RockxyLocalization.bundle
        ))
    }

    private var insightDetailsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isInsightExpanded.toggle()
            }
        } label: {
            HStack(spacing: 3) {
                Text(isInsightExpanded ? String(localized: "Hide", bundle: RockxyLocalization.bundle) : String(
                    localized: "Details",
                    bundle: RockxyLocalization.bundle
                ))
                Image(systemName: isInsightExpanded ? "chevron.up" : "chevron.down")
            }
            .font(.system(size: metrics.metadataFontSize, weight: .medium))
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityHint(String(
            localized: "Shows the evidence and recommended next step",
            bundle: RockxyLocalization.bundle
        ))
    }

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                if let hostScope = prompt.hostScope {
                    scopeActionRow(scope: hostScope)
                }

                if let appScope = prompt.appScope {
                    Divider()
                    scopeActionRow(scope: appScope)
                }
            }

            Text(scopeFooter)
                .font(.system(size: metrics.metadataFontSize))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func connectionInsight(_ insight: HTTPSConnectionInsight) -> some View {
        if insight.isWarning {
            warningInsight(insight)
        } else {
            standardInsight(insight)
        }
    }

    private func standardInsight(_ insight: HTTPSConnectionInsight) -> some View {
        Text(insight.summary)
            .font(.system(size: metrics.metadataFontSize))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func warningInsight(_ insight: HTTPSConnectionInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: insight.systemImage)
                    .font(.system(size: metrics.controlFontSize, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .frame(width: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.system(size: metrics.controlFontSize, weight: .semibold))
                    Text(insight.summary)
                        .font(.system(size: metrics.metadataFontSize))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                insightDetailsButton
            }

            if isInsightExpanded {
                insightDetails(insight)
                    .padding(.leading, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(nsColor: .systemOrange).opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .systemOrange).opacity(0.25), lineWidth: 0.5)
        }
    }

    private func insightDetails(_ insight: HTTPSConnectionInsight) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            insightDetail(
                label: String(localized: "Evidence", bundle: RockxyLocalization.bundle),
                text: insight.evidence
            )
            insightDetail(
                label: String(localized: "Next Step", bundle: RockxyLocalization.bundle),
                text: insight.nextStep
            )
        }
    }

    private func insightDetail(label: String, text: String) -> some View {
        (Text("\(label): ").bold() + Text(text))
            .font(.system(size: metrics.metadataFontSize))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func scopeActionRow(scope: HTTPSInspectionScopePresentation) -> some View {
        HStack(spacing: 8) {
            Text(scope.value)
                .font(.system(size: metrics.controlFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            scopeTrailingControl(scope)
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private func scopeTrailingControl(_ scope: HTTPSInspectionScopePresentation) -> some View {
        switch scope.control {
        case .button:
            scopeActionButton(scope)

        case .status:
            Label(String(localized: "Ready", bundle: RockxyLocalization.bundle), systemImage: "checkmark.circle.fill")
                .font(.system(size: metrics.metadataFontSize, weight: .medium))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .fixedSize()
                .accessibilityLabel(scope.actionDescription)
        }
    }

    @ViewBuilder
    private func scopeActionButton(_ scope: HTTPSInspectionScopePresentation) -> some View {
        if let action = scope.action, let controlTitle = scope.controlTitle {
            if let secondaryAction = scope.secondaryAction,
               let secondaryControlTitle = scope.secondaryControlTitle
            {
                Menu {
                    Button(controlTitle) { onAction(action) }
                    Button(secondaryControlTitle) { onAction(secondaryAction) }
                } label: {
                    Text(String(localized: "Choose Behavior", bundle: RockxyLocalization.bundle))
                        .lineLimit(1)
                        .frame(minWidth: promptActionLabelWidth)
                }
                .menuIndicator(.visible)
                .fixedSize()
                .help(scope.actionDescription)
                .accessibilityLabel(scope.actionDescription)
                .accessibilityHint(String(
                    localized: "Choose Decrypt or Tunnel behavior for new application connections.",
                    bundle: RockxyLocalization.bundle
                ))
            } else {
                Button {
                    onAction(action)
                } label: {
                    Text(controlTitle)
                        .lineLimit(1)
                        .frame(minWidth: promptActionLabelWidth)
                }
                .rockxyGlassButtonStyle()
                .controlSize(.small)
                .fixedSize()
                .help(scope.actionDescription)
                .accessibilityLabel(scope.actionDescription)
                .accessibilityHint(String(
                    localized: "The current captured response is unchanged",
                    bundle: RockxyLocalization.bundle
                ))
            }
        }
    }
}

// MARK: - HTTPSInspectionScopePresentation

struct HTTPSInspectionScopePresentation: Equatable {
    enum Control: Equatable {
        case button
        case status
    }

    enum State: Equatable {
        case available
        case partial
        case ready
    }

    enum Kind: Equatable {
        case host
        case appHosts
    }

    init(
        kind: Kind,
        value: String,
        state: State,
        control: Control,
        action: HTTPSInspectionPromptAction?,
        controlTitle: String?,
        actionDescription: String,
        secondaryAction: HTTPSInspectionPromptAction? = nil,
        secondaryControlTitle: String? = nil
    ) {
        self.kind = kind
        self.value = value
        self.state = state
        self.control = control
        self.action = action
        self.controlTitle = controlTitle
        self.actionDescription = actionDescription
        self.secondaryAction = secondaryAction
        self.secondaryControlTitle = secondaryControlTitle
    }

    let kind: Kind
    let value: String
    let state: State
    let control: Control
    let action: HTTPSInspectionPromptAction?
    let controlTitle: String?
    let actionDescription: String
    let secondaryAction: HTTPSInspectionPromptAction?
    let secondaryControlTitle: String?

    static func host(
        value: String,
        isReady: Bool,
        requiresRetry: Bool = false,
        decryptBlockedReason: String? = nil
    )
        -> HTTPSInspectionScopePresentation
    {
        if let decryptBlockedReason {
            return HTTPSInspectionScopePresentation(
                kind: .host,
                value: value,
                state: .available,
                control: .button,
                action: .openSSLProxyingList,
                controlTitle: String(localized: "Review Rules", bundle: RockxyLocalization.bundle),
                actionDescription: decryptBlockedReason
            )
        }

        if requiresRetry {
            return HTTPSInspectionScopePresentation(
                kind: .host,
                value: value,
                state: .partial,
                control: .button,
                action: .retryDomain(value),
                controlTitle: String(localized: "Retry", bundle: RockxyLocalization.bundle),
                actionDescription: String(
                    localized: "Retry HTTPS decryption for \(value) on the next connection",
                    bundle: RockxyLocalization.bundle
                )
            )
        }

        return HTTPSInspectionScopePresentation(
            kind: .host,
            value: value,
            state: isReady ? .ready : .available,
            control: isReady ? .status : .button,
            action: isReady ? nil : .enableDomain(value),
            controlTitle: isReady ? nil : String(localized: "Decrypt Host", bundle: RockxyLocalization.bundle),
            actionDescription: isReady ?
                String(
                    localized: "HTTPS decryption is ready for new connections to \(value)",
                    bundle: RockxyLocalization.bundle
                ) :
                String(
                    localized: "Turn on HTTPS decryption for new connections to \(value)",
                    bundle: RockxyLocalization.bundle
                )
        )
    }

    static func appHosts(
        name: String,
        enabledHostCount: Int,
        knownHostCount: Int,
        currentHostEnabled: Bool,
        fallbackDomain: String
    )
        -> HTTPSInspectionScopePresentation?
    {
        let total = max(knownHostCount, 1)
        let enabled = min(max(enabledHostCount, 0), total)
        let remaining = total - enabled
        let additionalDisabledHostCount = max(remaining - (currentHostEnabled ? 0 : 1), 0)
        guard additionalDisabledHostCount > 0 else {
            return nil
        }

        let state: State = if enabled > 0 {
            .partial
        } else {
            .available
        }

        return HTTPSInspectionScopePresentation(
            kind: .appHosts,
            value: name,
            state: state,
            control: .button,
            action: .enableApp(name, fallbackDomain: fallbackDomain),
            // A name-only transaction has no stable application identity. This action expands
            // the app's observed domains into host rules, which apply to every client. Do not
            // label it "Decrypt App" — that would imply application-scoped isolation and can
            // unexpectedly decrypt the same hosts in Safari or another application.
            controlTitle: String(localized: "Decrypt Observed Hosts", bundle: RockxyLocalization.bundle),
            actionDescription: String(
                localized: "Add host decryption rules for other known hosts used by \(name); these rules apply to every application",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    static func application(
        identity: ClientApplicationIdentity,
        isDecryptReady: Bool
    ) -> HTTPSInspectionScopePresentation {
        HTTPSInspectionScopePresentation(
            kind: .appHosts,
            value: identity.displayName,
            state: isDecryptReady ? .ready : .available,
            control: .button,
            action: .setApplication(identity, .include),
            controlTitle: String(localized: "Decrypt App", bundle: RockxyLocalization.bundle),
            actionDescription: String(
                localized: "Choose how Rockxy handles HTTPS from this application on new connections",
                bundle: RockxyLocalization.bundle
            ),
            secondaryAction: .setApplication(identity, .exclude),
            secondaryControlTitle: String(localized: "Tunnel App", bundle: RockxyLocalization.bundle)
        )
    }
}
