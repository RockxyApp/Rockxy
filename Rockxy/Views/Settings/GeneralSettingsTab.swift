import os
import SwiftUI
import UniformTypeIdentifiers

// General settings tab covering proxy configuration (port, auto-start)
// and root CA certificate management (generate, export, reset).

// MARK: - GeneralSettingsTab

struct GeneralSettingsTab: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Port Number
                settingsRow(label: String(localized: "Port Number:")) {
                    TextField("", value: $proxyPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                // Auto Start Recording
                checkboxRow(
                    isOn: $recordOnLaunch,
                    title: String(localized: "Auto Start Recording Traffic at Launch"),
                    description: String(
                        localized: "Start capturing network traffic as soon as the app launches."
                    )
                )

                // Advanced Proxy Setting button
                HStack {
                    Color.clear.frame(width: 176)
                    Button(String(localized: "Advanced Proxy Setting…")) {
                        openWindow(id: "advancedProxySettings")
                    }
                }

                sectionDivider

                // Certificate section
                certificateSection

                // Certificate status feedback
                if case let .success(message) = certificateStatus {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 176)
                        Text(message)
                            .foregroundStyle(.green)
                            .font(Theme.Typography.caption)
                    }
                } else if case let .error(message) = certificateStatus {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 176)
                        Text(message)
                            .foregroundStyle(.red)
                            .font(Theme.Typography.caption)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
        }
        .onChange(of: proxyPort) { _, newValue in
            AppSettingsManager.shared.updateProxyPort(newValue)
        }
        .onChange(of: recordOnLaunch) { _, newValue in
            AppSettingsManager.shared.updateRecordOnLaunch(newValue)
        }
        .alert(
            String(localized: "Reset Certificates"),
            isPresented: $showResetConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Reset"), role: .destructive) {
                resetCertificates()
            }
        } message: {
            Text(
                String(
                    localized: "This will delete the root CA and all generated host certificates. You will need to generate and install a new root CA."
                )
            )
        }
        .task {
            await checkCAStatus()
        }
        .onChange(of: ReadinessCoordinator.shared.certReadiness) {
            Task { await checkCAStatus() }
        }
    }

    // MARK: Private

    private enum CertificateStatus {
        case idle
        case success(String)
        case error(String)
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "GeneralSettingsTab")

    @Environment(\.openWindow) private var openWindow

    @AppStorage(RockxyIdentity.current.defaultsKey("proxyPort")) private var proxyPort =
        9_090
    @AppStorage(RockxyIdentity.current.defaultsKey("recordOnLaunch")) private var recordOnLaunch = true
    @State private var certSnapshot: RootCAStatusSnapshot?
    @State private var certLoading = false
    @State private var showResetConfirmation = false
    @State private var certificateStatus: CertificateStatus = .idle

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 0)
    }

    private var certificateSection: some View {
        settingsRow(label: String(localized: "Root CA Certificate:")) {
            CertificateStatusPanel(
                snapshot: certSnapshot,
                isLoading: certLoading,
                onAction: handleCertAction
            )
        }
    }

    private func settingsRow(
        label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 160, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.top, 2)
            content()
        }
    }

    private func checkboxRow(
        isOn: Binding<Bool>,
        title: String,
        description: String
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: 176)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.checkbox)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Certificate Actions

    private func checkCAStatus(performValidation: Bool = false) async {
        certSnapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: performValidation)
    }

    private func handleCertAction(_ action: CertificateAction) {
        certLoading = true
        certificateStatus = .idle
        Task {
            defer { certLoading = false }
            do {
                switch action {
                case .generate:
                    try await CertificateManager.shared.ensureRootCA()
                    certificateStatus = .success(String(localized: "Root CA generated successfully."))
                    Self.logger.info("Root CA generated")

                case .installAndTrust:
                    try await CertificateManager.shared.installAndTrust()
                    certificateStatus = .success(String(localized: "Root CA installed and trusted."))
                    Self.logger.info("Root CA installed and trusted")

                case .export:
                    guard let pem = try await CertificateManager.shared.getRootCAPEM() else {
                        certificateStatus = .error(
                            String(localized: "No Root CA certificate to export. Generate one first.")
                        )
                        return
                    }
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.x509Certificate]
                    panel.nameFieldStringValue = "RockxyRootCA.pem"
                    let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
                    if response == .OK, let url = panel.url {
                        try pem.write(to: url, atomically: true, encoding: .utf8)
                        certificateStatus = .success(String(localized: "Root CA exported successfully."))
                        Self.logger.info("Root CA exported to \(url.path)")
                    }

                case .reset:
                    showResetConfirmation = true
                    return

                case .recheck:
                    await checkCAStatus(performValidation: true)
                    return
                }
                await checkCAStatus()
            } catch {
                certificateStatus = .error(error.localizedDescription)
                Self.logger.error("Certificate action failed: \(error)")
                await checkCAStatus()
            }
        }
    }

    private func resetCertificates() {
        certLoading = true
        certificateStatus = .idle
        Task {
            defer { certLoading = false }
            do {
                try await CertificateManager.shared.reset()
                certificateStatus = .success(String(localized: "All certificates have been reset."))
                await checkCAStatus()
                Self.logger.info("Certificates reset")
            } catch {
                certificateStatus = .error(
                    String(localized: "Failed to reset certificates: \(error.localizedDescription)")
                )
                Self.logger.error("Certificate reset failed: \(error)")
            }
        }
    }
}
