import os
import SwiftUI

// Renders the certificate wizard interface for certificate onboarding.

// MARK: - WizardStep

/// Steps in the certificate setup wizard flow.
private enum WizardStep: Int, CaseIterable {
    case welcome = 0
    case generate
    case installTrust
    case verify
    case complete

    // MARK: Internal

    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome")
        case .generate: String(localized: "Generate")
        case .installTrust: String(localized: "Install")
        case .verify: String(localized: "Verify")
        case .complete: String(localized: "Complete")
        }
    }
}

// MARK: - CertificateWizardView

/// Guided first-run certificate setup wizard. Walks users through generating a root CA,
/// installing it in the macOS Keychain, and verifying trust — required for HTTPS interception.
///
/// Shown as a sheet on first launch when no trusted root CA exists, and accessible
/// from the Help menu via "Certificate Setup Wizard...".
struct CertificateWizardView: View {
    // MARK: Internal

    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider()

            ZStack {
                ForEach(WizardStep.allCases, id: \.rawValue) { step in
                    if step == currentStep {
                        stepContent(for: step)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .leading)
                            ))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Divider()

            navigationBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 500, height: 420)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CertificateWizard")

    @State private var currentStep: WizardStep = .welcome
    @State private var isGenerating = false
    @State private var generateSuccess = false
    @State private var generateError: String?
    @State private var isInstalling = false
    @State private var installSuccess = false
    @State private var installError: String?
    @State private var isVerifying = false
    @State private var isInstalled = false
    @State private var isTrusted = false
    @State private var verifyCompleted = false

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(stepColor(for: step))
                    .frame(width: 10, height: 10)

                if step != WizardStep.allCases.last {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 2)
                }
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 4)

            Text(String(localized: "HTTPS Traffic Interception"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                String(
                    localized: """
                    Rockxy needs a Root CA certificate to inspect HTTPS traffic. \
                    This wizard will generate a local certificate, install it in your \
                    macOS Keychain, and verify the setup. No certificate data leaves your machine.
                    """
                )
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
        }
        .padding(24)
    }

    private var generateStep: some View {
        VStack(spacing: 16) {
            if generateSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if isGenerating {
                ProgressView()
                    .controlSize(.large)
            } else if let error = generateError {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Text(String(localized: "Generate Root CA"))
                .font(.title2)
                .fontWeight(.semibold)

            if generateSuccess {
                Text(String(localized: "Root CA certificate generated successfully."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if !isGenerating, generateError == nil {
                Text(
                    String(
                        localized: "A P-256 elliptic curve root certificate will be created locally on this machine."
                    )
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }
        }
        .padding(24)
        .animation(.easeInOut(duration: 0.3), value: generateSuccess)
        .animation(.easeInOut(duration: 0.3), value: isGenerating)
        .task {
            await generateRootCA()
        }
    }

    private var installTrustStep: some View {
        VStack(spacing: 16) {
            if installSuccess {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if isInstalling {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
            }

            Text(String(localized: "Install & Trust Certificate"))
                .font(.title2)
                .fontWeight(.semibold)

            if installSuccess {
                Text(String(localized: "Certificate installed and trusted in your Keychain."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if let error = installError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            } else {
                Text(
                    String(
                        localized: """
                        This will install the root certificate in your macOS Keychain and mark \
                        it as trusted. macOS will prompt you for your password to authorize this change.
                        """
                    )
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }

            if !installSuccess, !isInstalling {
                Button {
                    installAndTrust()
                } label: {
                    Label(String(localized: "Install & Trust"), systemImage: "checkmark.shield.fill")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding(24)
        .animation(.easeInOut(duration: 0.3), value: installSuccess)
        .animation(.easeInOut(duration: 0.3), value: isInstalling)
    }

    private var verifyStep: some View {
        VStack(spacing: 16) {
            if isVerifying {
                ProgressView()
                    .controlSize(.large)
            } else if isTrusted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
            } else if isInstalled {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
            }

            Text(String(localized: "Verify Certificate"))
                .font(.title2)
                .fontWeight(.semibold)

            if isVerifying {
                Text(String(localized: "Checking certificate status..."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if isTrusted {
                Text(String(localized: "Certificate is installed and trusted. HTTPS interception is ready."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            } else if isInstalled {
                Text(
                    String(
                        localized: "Certificate is installed but not trusted. Go back and try \"Install & Trust\" again."
                    )
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            } else {
                Text(String(localized: "Certificate is not installed. Go back and install it."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if verifyCompleted, !isTrusted {
                Button {
                    verifyCompleted = false
                    Task { await verifyCertificate() }
                } label: {
                    Label(String(localized: "Retry Verification"), systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .padding(24)
        .animation(.easeInOut(duration: 0.3), value: verifyCompleted)
        .task {
            await verifyCertificate()
        }
    }

    private var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text(String(localized: "You\u{2019}re All Set!"))
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                completionCheckmark(String(localized: "Root CA certificate generated"))
                completionCheckmark(String(localized: "Installed in macOS Keychain"))
                completionCheckmark(String(localized: "Marked as trusted for TLS"))
                completionCheckmark(String(localized: "Ready for HTTPS interception"))
            }
            .padding(.top, 4)
        }
        .padding(24)
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            if currentStep.rawValue > WizardStep.welcome.rawValue,
               currentStep != .complete
            {
                Button(String(localized: "Back")) {
                    goBack()
                }
                .disabled(isGenerating || isInstalling || isVerifying)
            }

            Spacer()

            switch currentStep {
            case .welcome:
                Button(String(localized: "Get Started")) {
                    goForward()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .generate:
                Button(String(localized: "Next")) {
                    goForward()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!generateSuccess)

            case .installTrust:
                Button(String(localized: "Next")) {
                    goForward()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!installSuccess)

            case .verify:
                Button(String(localized: "Next")) {
                    goForward()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isTrusted)

            case .complete:
                Button(String(localized: "Start Using Rockxy")) {
                    Self.logger.info("Certificate wizard completed")
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private func stepContent(for step: WizardStep) -> some View {
        switch step {
        case .welcome:
            welcomeStep
        case .generate:
            generateStep
        case .installTrust:
            installTrustStep
        case .verify:
            verifyStep
        case .complete:
            completeStep
        }
    }

    private func completionCheckmark(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
            Text(text)
                .font(.body)
        }
    }

    private func stepColor(for step: WizardStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            Color.accentColor
        } else if step == currentStep {
            Color.accentColor
        } else {
            .secondary.opacity(0.3)
        }
    }

    // MARK: - Navigation

    private func goForward() {
        guard let nextIndex = WizardStep(rawValue: currentStep.rawValue + 1) else {
            return
        }
        withAnimation {
            currentStep = nextIndex
        }
    }

    private func goBack() {
        guard let prevIndex = WizardStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        withAnimation {
            currentStep = prevIndex
        }
    }

    private func generateRootCA() async {
        guard !generateSuccess else {
            return
        }
        isGenerating = true
        generateError = nil
        do {
            try await CertificateManager.shared.ensureRootCA()
            generateSuccess = true
            Self.logger.info("Wizard: Root CA generated")
        } catch {
            generateError = String(
                localized: "Failed to generate certificate: \(error.localizedDescription)"
            )
            Self.logger.error("Wizard: Root CA generation failed: \(error)")
        }
        isGenerating = false
    }

    private func installAndTrust() {
        isInstalling = true
        installError = nil
        Task {
            do {
                try await CertificateManager.shared.installAndTrust()
                installSuccess = true
                Self.logger.info("Wizard: Root CA installed and trusted")
            } catch {
                installError = String(
                    localized: "Installation failed: \(error.localizedDescription)"
                )
                Self.logger.error("Wizard: Root CA install failed: \(error)")
            }
            isInstalling = false
        }
    }

    private func verifyCertificate() async {
        isVerifying = true
        isInstalled = await CertificateManager.shared.isRootCAInstalled()
        isTrusted = await CertificateManager.shared.isRootCATrusted()
        isVerifying = false
        verifyCompleted = true
        Self.logger.info("Wizard: Verify — installed=\(isInstalled), trusted=\(isTrusted)")
    }
}
