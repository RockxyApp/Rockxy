import SwiftUI

// MARK: - MacCertificateSetupGuideView

struct MacCertificateSetupGuideView: View {
    @State private var selectedTab = Tab.automatic
    @State private var snapshot: RootCAStatusSnapshot?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker(String(localized: "Setup Mode"), selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            .padding(.top, 20)

            Group {
                switch selectedTab {
                case .automatic:
                    automaticTab
                case .manual:
                    manualTab
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)

            Spacer(minLength: 18)
            footer
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { await refreshStatus(validate: true) }
        .alert(String(localized: "Certificate Setup Failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 40, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(String(localized: "Mac Setup Guide"))
                .font(.system(size: 34, weight: .regular))
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
    }

    private var automaticTab: some View {
        VStack(spacing: 18) {
            statusCard

            HStack(spacing: 12) {
                Button {
                    Task { await installAndTrust() }
                } label: {
                    Label(String(localized: "Install and Trust"), systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || CertificateSetupState(snapshot: snapshot ?? .empty).isReady)

                Button {
                    Task { await refreshStatus(validate: true) }
                } label: {
                    Label(String(localized: "Recheck"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
        }
    }

    private var statusCard: some View {
        let state = CertificateSetupState(snapshot: snapshot ?? .empty)
        return VStack(spacing: 12) {
            Image(systemName: state.systemImageName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(state.isReady ? .green : .orange)
                .symbolRenderingMode(.hierarchical)

            Text(String(localized: "Install and Trust Rockxy CA Certificate in Keychain Access"))
                .font(.title3.weight(.semibold))

            Text(state.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                Text(state.title)
                    .font(.headline)
                if let fingerprint = snapshot?.fingerprintSHA256 {
                    Text(fingerprint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private var manualTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            guideSection(
                number: 1,
                title: String(localized: "Generate and Add Rockxy CA Certificate to System Keychain"),
                symbol: "certificate",
                lines: [
                    String(localized: "Choose System or login keychain in Keychain Access."),
                    String(localized: "Use Install and Trust to generate the CA, or export the PEM file and drag it into Keychain Access.")
                ]
            )

            guideSection(
                number: 2,
                title: String(localized: "Trust the Rockxy CA Certificate"),
                symbol: "key.fill",
                lines: [
                    String(localized: "Open Keychain Access and search for Rockxy CA."),
                    String(localized: "Open the certificate, expand Trust, set Secure Sockets Layer to Always Trust, then close and save.")
                ]
            )

            guideSection(
                number: 3,
                title: String(localized: "Terminal Alternative"),
                symbol: "terminal",
                lines: [
                    String(localized: "Export the PEM certificate, then use security add-trusted-cert with administrator approval."),
                    String(localized: "Recheck the status above after changing trust settings.")
                ]
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                CertificateExportPanelPresenter().export(format: .rootCertificatePEM)
            } label: {
                Label(String(localized: "Export PEM"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            Spacer()

            if let snapshot {
                let state = CertificateSetupState(snapshot: snapshot)
                Label(state.message, systemImage: state.systemImageName)
                    .font(.callout)
                    .foregroundStyle(state.isReady ? .green : .secondary)
                    .lineLimit(1)
            }

            if let helpURL = URL(string: "https://github.com/RockxyApp/Rockxy/blob/main/docs/installation.mdx#trust-the-root-certificate") {
                HelpLink(destination: helpURL)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 22)
    }

    private func guideSection(number: Int, title: String, symbol: String, lines: [String]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 28)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(number). \(title)")
                    .font(.headline)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func installAndTrust() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await CertificateManager.shared.installAndTrust()
            await refreshStatus(validate: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshStatus(validate: Bool) async {
        snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: validate)
    }

    private enum Tab: CaseIterable, Identifiable {
        case automatic
        case manual

        var id: Self { self }

        var title: String {
            switch self {
            case .automatic:
                String(localized: "Automatic")
            case .manual:
                String(localized: "Manual")
            }
        }
    }
}

private extension RootCAStatusSnapshot {
    static let empty = RootCAStatusSnapshot(
        hasGeneratedCertificate: false,
        isInstalledInKeychain: false,
        hasTrustSettings: false,
        isSystemTrustValidated: false,
        notValidBefore: nil,
        notValidAfter: nil,
        fingerprintSHA256: nil,
        commonName: nil,
        lastValidationErrorMessage: nil
    )
}
