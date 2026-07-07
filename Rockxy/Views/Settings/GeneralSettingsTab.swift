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
            VStack(alignment: .leading, spacing: 18) {
                Text(String(localized: "Proxy"))
                    .font(settingsMetrics.font(weight: .medium))

                sectionCard {
                    generalControlsSection
                }

                Text(String(localized: "Root CA Certificate"))
                    .font(settingsMetrics.font(weight: .medium))

                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        certificateSection

                        if case let .success(message) = certificateStatus {
                            certificateFeedbackRow(message: message, color: .green)
                        } else if case let .error(message) = certificateStatus {
                            certificateFeedbackRow(message: message, color: .red)
                        }
                    }
                }
            }
            .padding(.horizontal, settingsMetrics.contentPadding)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .sheet(item: $caShareController.currentSession, onDismiss: {
            Task { await caShareController.stopSharing(clearSession: true) }
        }) { session in
            RootCAShareSheet(
                session: session,
                fingerprint: caShareController.currentFingerprint,
                onCopyURL: { copyShareURL(session.publicURL) },
                onStop: {
                    Task { await caShareController.stopSharing(clearSession: true) }
                }
            )
        }
        .task {
            await checkCAStatus()
        }
        .onChange(of: ReadinessCoordinator.shared.certReadiness) {
            Task { await checkCAStatus() }
        }
        .onDisappear {
            Task { await caShareController.stopSharing(clearSession: true) }
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
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    @AppStorage(RockxyIdentity.current.defaultsKey("proxyPort")) private var proxyPort =
        9_090
    @AppStorage(RockxyIdentity.current.defaultsKey("recordOnLaunch")) private var recordOnLaunch = true
    @State private var certSnapshot: RootCAStatusSnapshot?
    @State private var certLoading = false
    @State private var showResetConfirmation = false
    @State private var certificateStatus: CertificateStatus = .idle
    @StateObject private var caShareController = CAShareController()

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }

    private func sectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.82),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 0.5)
        }
    }

    private var certificateSection: some View {
        CertificateStatusPanel(
            snapshot: certSnapshot,
            isLoading: certLoading,
            onAction: handleCertAction
        )
    }

    private var generalControlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsRow(label: String(localized: "Port Number:")) {
                TextField("", value: $proxyPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(settingsMetrics.font(monospaced: true))
                    .frame(width: settingsMetrics.fieldWidth(80))
                    .frame(minHeight: settingsMetrics.controlHeight)
            }

            checkboxRow(
                isOn: $recordOnLaunch,
                title: String(localized: "Auto Start Recording Traffic at Launch"),
                description: String(
                    localized: "Start capturing network traffic as soon as the app launches."
                )
            )

            HStack {
                Color.clear.frame(width: settingsMetrics.rowLeading)
                Button(String(localized: "Advanced Proxy Setting…")) {
                    openWindow(id: "advancedProxySettings")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsRow(
        label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(settingsMetrics.font(weight: .medium))
                .frame(width: settingsMetrics.labelWidth, alignment: .trailing)
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
            Color.clear.frame(width: settingsMetrics.rowLeading)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.checkbox)
                Text(description)
                    .font(settingsMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func certificateFeedbackRow(message: String, color: Color) -> some View {
        Text(message)
            .foregroundStyle(color)
            .font(settingsMetrics.secondaryFont())
            .fixedSize(horizontal: false, vertical: true)
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
                        await MainActor.run {
                            AppSettingsManager.shared.updateLastExportedRootCAPath(url.path)
                        }
                        certificateStatus = .success(String(localized: "Root CA exported successfully."))
                        Self.logger.info("Root CA exported to \(url.path)")
                    }

                case .share:
                    let session = try await caShareController.startSharing()
                    certificateStatus = .success(String(localized: "Root CA sharing link started."))
                    Self.logger.info("Root CA sharing started on \(session.host):\(session.port)")

                case .reset:
                    showResetConfirmation = true
                    return

                case .recheck:
                    await checkCAStatus(performValidation: true)
                    return
                }
                await checkCAStatus()
            } catch {
                certificateStatus = .error(action.userFacingFailureMessage(for: error))
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
                await caShareController.stopSharing(clearSession: true)
                try await CertificateManager.shared.reset()
                await MainActor.run {
                    AppSettingsManager.shared.updateLastExportedRootCAPath(nil)
                }
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

    private func copyShareURL(_ url: URL) {
        do {
            try caShareController.copyShareURL(sessionURL: url)
            certificateStatus = .success(String(localized: "Root CA sharing URL copied."))
        } catch {
            certificateStatus = .error(CAShareController.userFacingMessage(for: error))
        }
    }
}
