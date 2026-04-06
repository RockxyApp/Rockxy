import os
import SwiftUI
import UniformTypeIdentifiers

/// Standalone certificate management view for generating, installing, exporting,
/// and resetting the Rockxy root CA used for HTTPS traffic interception.
/// Interacts with `CertificateManager` for all certificate lifecycle operations.
struct CertificateSetupView: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section(String(localized: "Root CA Status")) {
                CertificateStatusPanel(
                    snapshot: certSnapshot,
                    isLoading: certLoading,
                    onAction: handleCertAction
                )
            }

            if !statusMessage.isEmpty {
                Section {
                    Label(statusMessage, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "About")) {
                Text(
                    String(
                        localized: """
                        Rockxy generates a local root Certificate Authority (CA) to create \
                        per-host certificates for HTTPS traffic interception. The root CA \
                        must be installed and trusted in your macOS Keychain. No certificate \
                        data leaves your machine.
                        """
                    )
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    localized: "This will delete the root CA and all generated host certificates. You will need to generate and install a new root CA to resume HTTPS interception."
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

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CertificateSetupView")

    @State private var certSnapshot: RootCAStatusSnapshot?
    @State private var certLoading = false
    @State private var statusMessage = ""
    @State private var showResetConfirmation = false

    private func checkCAStatus(performValidation: Bool = false) async {
        certSnapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: performValidation)
    }

    private func handleCertAction(_ action: CertificateAction) {
        certLoading = true
        statusMessage = ""
        Task {
            defer { certLoading = false }
            do {
                switch action {
                case .generate:
                    try await CertificateManager.shared.ensureRootCA()
                    statusMessage = String(localized: "Root CA generated successfully.")
                    Self.logger.info("Root CA generated")

                case .installAndTrust:
                    try await CertificateManager.shared.installAndTrust()
                    statusMessage = String(localized: "Root CA installed and trusted in Keychain.")
                    Self.logger.info("Root CA installed and trusted")

                case .export:
                    guard let pem = try await CertificateManager.shared.getRootCAPEM() else {
                        statusMessage = String(localized: "No Root CA to export. Generate one first.")
                        return
                    }
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.x509Certificate]
                    panel.nameFieldStringValue = "RockxyRootCA.pem"
                    let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
                    if response == .OK, let url = panel.url {
                        try pem.write(to: url, atomically: true, encoding: .utf8)
                        statusMessage = String(localized: "Certificate exported to \(url.lastPathComponent).")
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
                statusMessage = error.localizedDescription
                Self.logger.error("Certificate action failed: \(error)")
                await checkCAStatus()
            }
        }
    }

    private func resetCertificates() {
        certLoading = true
        statusMessage = ""
        Task {
            defer { certLoading = false }
            do {
                try await CertificateManager.shared.reset()
                statusMessage = String(localized: "All certificates have been reset.")
                await checkCAStatus()
                Self.logger.info("Certificates reset")
            } catch {
                statusMessage = String(localized: "Reset failed: \(error.localizedDescription)")
                Self.logger.error("Certificate reset failed: \(error)")
            }
        }
    }
}
