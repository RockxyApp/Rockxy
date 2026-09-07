import SwiftUI

// MARK: - CertificateAction

/// Actions the panel can request from its parent view.
enum CertificateAction: Equatable {
    case generate
    case installAndTrust
    case export
    case share
    case reset
    case recheck
}

@MainActor
extension CertificateAction {
    func userFacingFailureMessage(for error: Error) -> String {
        if self == .share {
            return CAShareController.userFacingMessage(for: error)
        }

        return error.localizedDescription
    }
}

// MARK: - CertificateStatusPanel

/// Shared diagnostics panel for root CA certificate status.
/// Renders a 3-zone layout (summary, diagnostics grid, actions) driven by
/// `RootCAStatusSnapshot`. Reused in both `GeneralSettingsTab` and `CertificateSetupView`.
struct CertificateStatusPanel: View {
    // MARK: Internal

    let snapshot: RootCAStatusSnapshot?
    let isLoading: Bool
    var pinsActionsToBottom = false
    let onAction: (CertificateAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            summaryRow
            diagnosticsGrid
            expiryCallout
            errorCallout
            if pinsActionsToBottom {
                Spacer(minLength: 12)
            }
            actionRow
        }
        .frame(maxWidth: .infinity, maxHeight: pinsActionsToBottom ? .infinity : nil, alignment: .topLeading)
    }

    // MARK: Private

    private static let expiryWarningDays = 30
    private static let expiryWarningSeconds: TimeInterval = .init(expiryWarningDays) * 24 * 3_600

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private var titleFont: Font {
        settingsMetrics.font(weight: .medium)
    }

    private var secondaryFont: Font {
        settingsMetrics.secondaryFont()
    }

    private var secondaryMonospacedFont: Font {
        settingsMetrics.secondaryFont(monospaced: true)
    }

    private var metadataFont: Font {
        settingsMetrics.metadataFont()
    }

    private var actionFont: Font {
        settingsMetrics.font()
    }

    private var summaryIconFontSize: CGFloat {
        max(16, settingsMetrics.bodyFontSize + 3)
    }

    private var state: PanelState {
        guard let snapshot else {
            return .notAvailable
        }
        // An unreadable status is not "no root CA": the booleans below it are fail-closed
        // defaults, and offering Generate or Reset for them would destroy or replace a
        // certificate that may be installed and trusted.
        if snapshot.isStatusUnavailable {
            return .statusUnavailable
        }
        if snapshot.isSystemTrustValidated {
            return .trusted
        }
        if snapshot.isInstalledInKeychain, snapshot.hasTrustSettings {
            return .trustIncomplete
        }
        if snapshot.isInstalledInKeychain {
            return .installedNotTrusted
        }
        if snapshot.hasGeneratedCertificate {
            return .generatedOnly
        }
        return .notAvailable
    }

    /// Copy for a diagnostic field whose real value could not be read. Never "No", "Missing", or
    /// "Failed": each of those is a claim about the certificate that this answer does not make.
    private var unavailableValueText: String {
        String(localized: "Unavailable", bundle: RockxyLocalization.bundle)
    }

    private var isStatusUnavailable: Bool {
        snapshot?.isStatusUnavailable == true
    }

    private var systemValidationText: String {
        guard let snapshot else {
            return String(localized: "Not Checked", bundle: RockxyLocalization.bundle)
        }
        if snapshot.isStatusUnavailable {
            return unavailableValueText
        }
        guard snapshot.hasTrustSettings else {
            return String(localized: "Not Checked", bundle: RockxyLocalization.bundle)
        }
        return snapshot.isSystemTrustValidated
            ? String(localized: "Passed", bundle: RockxyLocalization.bundle)
            : String(localized: "Failed", bundle: RockxyLocalization.bundle)
    }

    private var systemValidationColor: Color {
        guard let snapshot else {
            return .secondary
        }
        if snapshot.isStatusUnavailable {
            return .orange
        }
        guard snapshot.hasTrustSettings else {
            return .secondary
        }
        return snapshot.isSystemTrustValidated ? .green : .red
    }

    /// The callout message, or `nil` when there is nothing to explain.
    ///
    /// The unavailable reason is shown even though `hasTrustSettings` is false — that flag is the
    /// fail-closed default for a read that did not complete, and gating the callout on it is what
    /// hid the diagnostic that explains the state.
    private var calloutMessage: String? {
        guard let snapshot else {
            return nil
        }
        if snapshot.isStatusUnavailable {
            return snapshot.statusReadErrorMessage ?? String(
                localized: "Rockxy could not read the certificate status, so nothing was changed. Recheck the status once your keychain is available.",
                bundle: RockxyLocalization.bundle
            )
        }
        guard snapshot.hasTrustSettings, !snapshot.isSystemTrustValidated else {
            return nil
        }
        return snapshot.lastValidationErrorMessage
            ?? String(
                localized: "macOS has not validated the certificate for TLS. Recheck the status before changing your certificate or trust settings.",
                bundle: RockxyLocalization.bundle
            )
    }

    private var expiryColor: Color {
        guard let expiryDate = snapshot?.notValidAfter else {
            return .primary
        }
        if expiryDate < Date() {
            return .red
        }
        if expiryDate.timeIntervalSinceNow < Self.expiryWarningSeconds {
            return .orange
        }
        return .primary
    }

    private var expiryWarningMessage: String? {
        guard let expiryDate = snapshot?.notValidAfter else {
            return nil
        }
        if expiryDate < Date() {
            return String(
                localized: "Certificate has expired. Generate a new certificate and trust it to restore HTTPS interception.",
                bundle: RockxyLocalization.bundle
            )
        }
        let daysRemaining = Int(expiryDate.timeIntervalSinceNow / (24 * 3_600))
        if daysRemaining < Self.expiryWarningDays {
            return String(
                localized: "Certificate expires in \(daysRemaining) days. Generate a new certificate and re-trust to maintain HTTPS interception.",
                bundle: RockxyLocalization.bundle
            )
        }
        return nil
    }

    private var truncatedFingerprint: String {
        guard let fp = snapshot?.fingerprintSHA256 else {
            return "\u{2014}"
        }
        if fp.count > 24 {
            return String(fp.prefix(24)) + "\u{2026}"
        }
        return fp
    }

    // MARK: - Zone A: Summary Row

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: Theme.Layout.controlSpacing) {
            Image(systemName: state.iconName)
                .foregroundStyle(state.iconColor)
                .font(.system(size: summaryIconFontSize))
                .padding(.top, 2)
                .accessibilityLabel(
                    String(localized: "Root CA status: \(state.accessibilityLabel)", bundle: RockxyLocalization.bundle)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(titleFont)
                Text(state.subtitle)
                    .font(secondaryFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Zone B: Diagnostics Grid

    private var diagnosticsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            if snapshot?.isGeneratedStateKnown == false {
                diagnosticRow(
                    label: String(localized: "Generated:", bundle: RockxyLocalization.bundle),
                    value: unavailableValueText,
                    color: .orange
                )
            } else {
                diagnosticRow(
                    label: String(localized: "Generated:", bundle: RockxyLocalization.bundle),
                    value: snapshot?.hasGeneratedCertificate == true
                        ? String(localized: "Yes", bundle: RockxyLocalization.bundle)
                        : String(localized: "No", bundle: RockxyLocalization.bundle),
                    color: snapshot?.hasGeneratedCertificate == true ? .primary : .secondary
                )
            }

            if isStatusUnavailable {
                diagnosticRow(
                    label: String(localized: "Installed:", bundle: RockxyLocalization.bundle),
                    value: unavailableValueText,
                    color: .orange
                )
                diagnosticRow(
                    label: String(localized: "Trust Settings:", bundle: RockxyLocalization.bundle),
                    value: unavailableValueText,
                    color: .orange
                )
            } else {
                diagnosticRow(
                    label: String(localized: "Installed:", bundle: RockxyLocalization.bundle),
                    value: snapshot?.isInstalledInKeychain == true
                        ? String(localized: "Yes", bundle: RockxyLocalization.bundle)
                        : String(localized: "No", bundle: RockxyLocalization.bundle),
                    color: snapshot?.isInstalledInKeychain == true ? .primary : .secondary
                )
                diagnosticRow(
                    label: String(localized: "Trust Settings:", bundle: RockxyLocalization.bundle),
                    value: snapshot?.hasTrustSettings == true
                        ? String(localized: "Present", bundle: RockxyLocalization.bundle)
                        : String(localized: "Missing", bundle: RockxyLocalization.bundle),
                    color: snapshot?.hasTrustSettings == true ? .primary : .orange
                )
            }

            diagnosticRow(
                label: String(localized: "System Validation:", bundle: RockxyLocalization.bundle),
                value: systemValidationText,
                color: systemValidationColor
            )

            if snapshot?.hasGeneratedCertificate == true {
                diagnosticRow(
                    label: String(localized: "Valid From:", bundle: RockxyLocalization.bundle),
                    value: snapshot?.notValidBefore?
                        .formatted(date: .abbreviated, time: .omitted) ?? "\u{2014}",
                    color: .primary
                )

                diagnosticRow(
                    label: String(localized: "Valid Until:", bundle: RockxyLocalization.bundle),
                    value: snapshot?.notValidAfter?
                        .formatted(date: .abbreviated, time: .omitted) ?? "\u{2014}",
                    color: expiryColor
                )

                diagnosticRow(
                    label: String(localized: "Fingerprint:", bundle: RockxyLocalization.bundle),
                    value: truncatedFingerprint,
                    color: .primary,
                    fullAccessibilityValue: snapshot?.fingerprintSHA256
                )
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Zone C: Error Callout + Actions

    @ViewBuilder private var expiryCallout: some View {
        if let message = expiryWarningMessage {
            let isExpired = snapshot?.notValidAfter.map { $0 < Date() } ?? false
            let tintColor: Color = isExpired ? .red : .orange
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(tintColor)
                    .font(metadataFont)
                Text(message)
                    .font(secondaryFont)
                    .foregroundStyle(tintColor)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tintColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.badgeCornerRadius))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var errorCallout: some View {
        if let message = calloutMessage {
            let tint: Color = isStatusUnavailable ? .orange : .red
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: isStatusUnavailable ? "questionmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(tint)
                    .font(metadataFont)
                Text(message)
                    .font(secondaryFont)
                    .foregroundStyle(tint)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.badgeCornerRadius))
            .accessibilityElement(children: .combine)
        }
    }

    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                actionButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                actionButtons
            }
        }
        .font(actionFont)
    }

    @ViewBuilder private var actionButtons: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
        }

        switch state {
        case .statusUnavailable:
            // Recheck only. Generate, Reset, and Install & Trust would each act on — or ask for
            // administrator approval for — a certificate whose real state is unknown.
            Button(String(localized: "Recheck Status", bundle: RockxyLocalization.bundle)) {
                onAction(.recheck)
            }
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(isLoading)
            if snapshot?.hasGeneratedCertificate == true {
                // Sharing only ever exports the public certificate this app already holds, so it
                // stays available when that material is known.
                shareCertificateButton
            }

        case .notAvailable:
            Button(String(localized: "Generate New\u{2026}", bundle: RockxyLocalization.bundle)) {
                onAction(.generate)
            }
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(isLoading)

        case .generatedOnly:
            Button(String(localized: "Install & Trust", bundle: RockxyLocalization.bundle)) {
                onAction(.installAndTrust)
            }
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(isLoading)
            shareCertificateButton
            Button(String(localized: "Generate New\u{2026}", bundle: RockxyLocalization.bundle)) {
                onAction(.generate)
            }
            .disabled(isLoading)

        case .trustIncomplete:
            Button(String(localized: "Install & Trust", bundle: RockxyLocalization.bundle)) {
                onAction(.installAndTrust)
            }
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(isLoading)
            shareCertificateButton
            Button(String(localized: "Reset Certificate", bundle: RockxyLocalization.bundle), role: .destructive) {
                onAction(.reset)
            }
            .disabled(isLoading)
            Button(String(localized: "Recheck Status", bundle: RockxyLocalization.bundle)) {
                onAction(.recheck)
            }
            .disabled(isLoading)

        case .installedNotTrusted:
            Button(String(localized: "Install & Trust", bundle: RockxyLocalization.bundle)) {
                onAction(.installAndTrust)
            }
            .rockxyGlassButtonStyle(prominent: true)
            .disabled(isLoading)
            shareCertificateButton
            Button(String(localized: "Reset Certificate", bundle: RockxyLocalization.bundle), role: .destructive) {
                onAction(.reset)
            }
            .disabled(isLoading)
            Button(String(localized: "Recheck Status", bundle: RockxyLocalization.bundle)) {
                onAction(.recheck)
            }
            .disabled(isLoading)

        case .trusted:
            Button(String(localized: "Export Certificate\u{2026}", bundle: RockxyLocalization.bundle)) {
                onAction(.export)
            }
            .disabled(isLoading)
            shareCertificateButton
            Button(String(localized: "Generate New\u{2026}", bundle: RockxyLocalization.bundle)) {
                onAction(.generate)
            }
            .disabled(isLoading)
            Button(String(localized: "Reset Certificate", bundle: RockxyLocalization.bundle), role: .destructive) {
                onAction(.reset)
            }
            .disabled(isLoading)
        }
    }

    private var shareCertificateButton: some View {
        Button(String(localized: "Share Certificate\u{2026}", bundle: RockxyLocalization.bundle)) {
            onAction(.share)
        }
        .disabled(isLoading)
    }

    private func diagnosticRow(
        label: String,
        value: String,
        color: Color,
        fullAccessibilityValue: String? = nil
    )
        -> some View
    {
        GridRow {
            Text(label)
                .font(metadataFont)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(secondaryMonospacedFont)
                .foregroundStyle(color)
                .accessibilityLabel(fullAccessibilityValue ?? value)
        }
    }
}

// MARK: - PanelState

private enum PanelState {
    case trusted
    case trustIncomplete
    case installedNotTrusted
    case generatedOnly
    case notAvailable
    case statusUnavailable

    // MARK: Internal

    var iconName: String {
        switch self {
        case .trusted:
            "checkmark.shield.fill"
        case .trustIncomplete,
             .installedNotTrusted:
            "exclamationmark.triangle.fill"
        case .generatedOnly:
            "arrow.down.circle"
        case .notAvailable:
            "xmark.shield"
        case .statusUnavailable:
            "questionmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .trusted:
            .green
        case .trustIncomplete,
             .installedNotTrusted,
             .generatedOnly,
             .statusUnavailable:
            .orange
        case .notAvailable:
            .secondary
        }
    }

    var title: String {
        switch self {
        case .trusted:
            String(localized: "Root CA Trusted", bundle: RockxyLocalization.bundle)
        case .trustIncomplete:
            String(localized: "Trust Incomplete", bundle: RockxyLocalization.bundle)
        case .installedNotTrusted:
            String(localized: "Root CA Installed, Not Trusted", bundle: RockxyLocalization.bundle)
        case .generatedOnly:
            String(localized: "Root CA Not Installed", bundle: RockxyLocalization.bundle)
        case .notAvailable:
            String(localized: "No Root CA", bundle: RockxyLocalization.bundle)
        case .statusUnavailable:
            String(localized: "Certificate Status Unavailable", bundle: RockxyLocalization.bundle)
        }
    }

    var subtitle: String {
        switch self {
        case .trusted:
            String(localized: "Root CA trust is ready for HTTPS decryption.", bundle: RockxyLocalization.bundle)
        case .trustIncomplete:
            String(localized: "Trust settings exist but macOS validation failed.", bundle: RockxyLocalization.bundle)
        case .installedNotTrusted:
            String(
                localized: "The certificate is in the keychain but trust settings are missing.",
                bundle: RockxyLocalization.bundle
            )
        case .generatedOnly:
            String(
                localized: "Install and trust the certificate to enable HTTPS interception.",
                bundle: RockxyLocalization.bundle
            )
        case .notAvailable:
            String(localized: "Generate a root certificate to get started.", bundle: RockxyLocalization.bundle)
        case .statusUnavailable:
            String(
                localized: "Rockxy could not read the Keychain or trust state. Nothing was changed.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .trusted:
            String(localized: "trusted", bundle: RockxyLocalization.bundle)
        case .trustIncomplete:
            String(localized: "trust incomplete", bundle: RockxyLocalization.bundle)
        case .installedNotTrusted:
            String(localized: "installed not trusted", bundle: RockxyLocalization.bundle)
        case .generatedOnly:
            String(localized: "not installed", bundle: RockxyLocalization.bundle)
        case .notAvailable:
            String(localized: "not available", bundle: RockxyLocalization.bundle)
        case .statusUnavailable:
            String(localized: "status unavailable", bundle: RockxyLocalization.bundle)
        }
    }
}
