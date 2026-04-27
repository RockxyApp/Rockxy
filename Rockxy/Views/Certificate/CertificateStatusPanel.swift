import SwiftUI

// MARK: - CertificateAction

/// Actions the panel can request from its parent view.
enum CertificateAction {
    case generate
    case installAndTrust
    case export
    case share
    case reset
    case recheck
}

// MARK: - CertificateStatusPanel

/// Shared diagnostics panel for root CA certificate status.
/// Renders a 3-zone layout (summary, diagnostics grid, actions) driven by
/// `RootCAStatusSnapshot`. Reused in both `GeneralSettingsTab` and `CertificateSetupView`.
struct CertificateStatusPanel: View {
    // MARK: Internal

    let snapshot: RootCAStatusSnapshot?
    let isLoading: Bool
    let onAction: (CertificateAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            summaryRow
            diagnosticsGrid
            expiryCallout
            errorCallout
            actionRow
        }
    }

    // MARK: Private

    private static let expiryWarningDays = 30
    private static let expiryWarningSeconds: TimeInterval = .init(expiryWarningDays) * 24 * 3_600

    private var state: PanelState {
        guard let snapshot else {
            return .notAvailable
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

    private var systemValidationText: String {
        guard let snapshot, snapshot.hasTrustSettings else {
            return String(localized: "Not Checked")
        }
        return snapshot.isSystemTrustValidated
            ? String(localized: "Passed")
            : String(localized: "Failed")
    }

    private var systemValidationColor: Color {
        guard let snapshot, snapshot.hasTrustSettings else {
            return .secondary
        }
        return snapshot.isSystemTrustValidated ? .green : .red
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
                localized: "Certificate has expired. Generate a new certificate and trust it to restore HTTPS interception."
            )
        }
        let daysRemaining = Int(expiryDate.timeIntervalSinceNow / (24 * 3_600))
        if daysRemaining < Self.expiryWarningDays {
            return String(
                localized: "Certificate expires in \(daysRemaining) days. Generate a new certificate and re-trust to maintain HTTPS interception."
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
        HStack(spacing: Theme.Layout.controlSpacing) {
            Image(systemName: state.iconName)
                .foregroundStyle(state.iconColor)
                .font(.system(size: 16))
                .accessibilityLabel(
                    String(localized: "Root CA status: \(state.accessibilityLabel)")
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(Theme.Typography.sectionTitle)
                Text(state.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Zone B: Diagnostics Grid

    private var diagnosticsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            diagnosticRow(
                label: String(localized: "Generated:"),
                value: snapshot?.hasGeneratedCertificate == true
                    ? String(localized: "Yes")
                    : String(localized: "No"),
                color: snapshot?.hasGeneratedCertificate == true ? .primary : .secondary
            )

            diagnosticRow(
                label: String(localized: "Installed:"),
                value: snapshot?.isInstalledInKeychain == true
                    ? String(localized: "Yes")
                    : String(localized: "No"),
                color: snapshot?.isInstalledInKeychain == true ? .primary : .secondary
            )

            diagnosticRow(
                label: String(localized: "Trust Settings:"),
                value: snapshot?.hasTrustSettings == true
                    ? String(localized: "Present")
                    : String(localized: "Missing"),
                color: snapshot?.hasTrustSettings == true ? .primary : .orange
            )

            diagnosticRow(
                label: String(localized: "System Validation:"),
                value: systemValidationText,
                color: systemValidationColor
            )

            if snapshot?.hasGeneratedCertificate == true {
                diagnosticRow(
                    label: String(localized: "Valid From:"),
                    value: snapshot?.notValidBefore?
                        .formatted(date: .abbreviated, time: .omitted) ?? "\u{2014}",
                    color: .primary
                )

                diagnosticRow(
                    label: String(localized: "Valid Until:"),
                    value: snapshot?.notValidAfter?
                        .formatted(date: .abbreviated, time: .omitted) ?? "\u{2014}",
                    color: expiryColor
                )

                diagnosticRow(
                    label: String(localized: "Fingerprint:"),
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
                    .font(.system(size: 10))
                Text(message)
                    .font(.system(size: 10))
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
        if let snapshot,
           snapshot.hasTrustSettings,
           !snapshot.isSystemTrustValidated
        {
            let message = snapshot.lastValidationErrorMessage
                ?? String(
                    localized: "Trust settings were applied but macOS still does not trust generated certificates. Try Reset Certificate, then Install & Trust again."
                )
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 10))
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.badgeCornerRadius))
            .accessibilityElement(children: .combine)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            switch state {
            case .notAvailable:
                Button(String(localized: "Generate New\u{2026}")) {
                    onAction(.generate)
                }
                .disabled(isLoading)

            case .generatedOnly:
                Button(String(localized: "Install & Trust")) {
                    onAction(.installAndTrust)
                }
                .disabled(isLoading)
                Button(String(localized: "Share Certificate\u{2026}")) {
                    onAction(.share)
                }
                .disabled(isLoading)
                Button(String(localized: "Generate New\u{2026}")) {
                    onAction(.generate)
                }
                .disabled(isLoading)

            case .trustIncomplete:
                Button(String(localized: "Install & Trust")) {
                    onAction(.installAndTrust)
                }
                .disabled(isLoading)
                Button(String(localized: "Share Certificate\u{2026}")) {
                    onAction(.share)
                }
                .disabled(isLoading)
                Button(String(localized: "Reset Certificate"), role: .destructive) {
                    onAction(.reset)
                }
                .disabled(isLoading)
                Button(String(localized: "Recheck Status")) {
                    onAction(.recheck)
                }
                .disabled(isLoading)

            case .installedNotTrusted:
                Button(String(localized: "Install & Trust")) {
                    onAction(.installAndTrust)
                }
                .disabled(isLoading)
                Button(String(localized: "Share Certificate\u{2026}")) {
                    onAction(.share)
                }
                .disabled(isLoading)
                Button(String(localized: "Reset Certificate"), role: .destructive) {
                    onAction(.reset)
                }
                .disabled(isLoading)
                Button(String(localized: "Recheck Status")) {
                    onAction(.recheck)
                }
                .disabled(isLoading)

            case .trusted:
                Button(String(localized: "Export Certificate\u{2026}")) {
                    onAction(.export)
                }
                .disabled(isLoading)
                Button(String(localized: "Share Certificate\u{2026}")) {
                    onAction(.share)
                }
                .disabled(isLoading)
                Button(String(localized: "Generate New\u{2026}")) {
                    onAction(.generate)
                }
                .disabled(isLoading)
                Button(String(localized: "Reset Certificate"), role: .destructive) {
                    onAction(.reset)
                }
                .disabled(isLoading)
            }
        }
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
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
        }
    }

    var iconColor: Color {
        switch self {
        case .trusted:
            .green
        case .trustIncomplete,
             .installedNotTrusted,
             .generatedOnly:
            .orange
        case .notAvailable:
            .secondary
        }
    }

    var title: String {
        switch self {
        case .trusted:
            String(localized: "Root CA Trusted")
        case .trustIncomplete:
            String(localized: "Trust Incomplete")
        case .installedNotTrusted:
            String(localized: "Root CA Installed, Not Trusted")
        case .generatedOnly:
            String(localized: "Root CA Not Installed")
        case .notAvailable:
            String(localized: "No Root CA")
        }
    }

    var subtitle: String {
        switch self {
        case .trusted:
            String(localized: "HTTPS interception is ready.")
        case .trustIncomplete:
            String(localized: "Trust settings exist but macOS validation failed.")
        case .installedNotTrusted:
            String(localized: "The certificate is in the keychain but trust settings are missing.")
        case .generatedOnly:
            String(localized: "Install and trust the certificate to enable HTTPS interception.")
        case .notAvailable:
            String(localized: "Generate a root certificate to get started.")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .trusted:
            String(localized: "trusted")
        case .trustIncomplete:
            String(localized: "trust incomplete")
        case .installedNotTrusted:
            String(localized: "installed not trusted")
        case .generatedOnly:
            String(localized: "not installed")
        case .notAvailable:
            String(localized: "not available")
        }
    }
}
