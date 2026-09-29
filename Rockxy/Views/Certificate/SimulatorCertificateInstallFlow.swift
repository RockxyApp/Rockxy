import AppKit
import Foundation

// Guided, confirmed install of the Rockxy root certificate into booted simulators.

// MARK: - SimulatorCertificateInstallFlow

/// Lists the simulators that are booted now, asks before changing their trust
/// store, installs the verified public root certificate, and reports each
/// simulator's outcome. Trust changes only happen after the user confirms.
@MainActor
enum SimulatorCertificateInstallFlow {
    static func run(installer: SimulatorCertificateInstaller = SimulatorCertificateInstaller()) async {
        let simulators: [BootedSimulator]
        do {
            simulators = try await installer.bootedSimulators()
        } catch {
            present(
                title: String(localized: "Simulators Unavailable", bundle: RockxyLocalization.bundle),
                message: error.localizedDescription,
                style: .warning
            )
            return
        }

        guard !simulators.isEmpty else {
            present(
                title: String(localized: "No Booted Simulators", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Boot an iOS, watchOS, or visionOS simulator from Xcode or the Simulator app, then try again.",
                    bundle: RockxyLocalization.bundle
                ),
                style: .informational
            )
            return
        }

        guard confirm(simulators) else {
            return
        }

        let certificatePEM: String
        do {
            certificatePEM = try await verifiedRootCertificatePEM()
        } catch {
            present(
                title: String(localized: "Certificate Unavailable", bundle: RockxyLocalization.bundle),
                message: error.localizedDescription,
                style: .warning
            )
            return
        }

        let results = await installer.installRootCertificate(pem: certificatePEM, into: simulators)
        presentSummary(simulators: simulators, results: results)
    }

    static func summary(
        simulators: [BootedSimulator],
        results: [BootedSimulator: Result<Void, SimulatorCertificateInstallerError>]
    )
        -> (installed: [BootedSimulator], failed: [(BootedSimulator, String)])
    {
        var installed: [BootedSimulator] = []
        var failed: [(BootedSimulator, String)] = []
        for simulator in simulators {
            switch results[simulator] {
            case .success:
                installed.append(simulator)
            case let .failure(error):
                failed.append((simulator, error.localizedDescription))
            case nil:
                failed.append((simulator, SimulatorCertificateInstallerError.unreadableDeviceList.localizedDescription))
            }
        }
        return (installed, failed)
    }

    // MARK: Private

    private static func confirm(_ simulators: [BootedSimulator]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(AttributedString(
            localized: "Install the Rockxy root certificate in ^[\(simulators.count) booted simulator](inflect: true)?",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
        let list = simulators.map { "• \($0.displayName)" }.joined(separator: "\n")
        alert.informativeText = list + "\n\n" + String(
            localized: "These simulators will trust HTTPS certificates that Rockxy issues. Erasing a simulator removes the certificate.",
            bundle: RockxyLocalization.bundle
        )
        alert.addButton(withTitle: String(localized: "Install", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func verifiedRootCertificatePEM() async throws -> String {
        try await CertificateManager.shared.ensureRootCA()
        guard let pem = try await CertificateManager.shared.getRootCAPEM() else {
            throw RootCADownloadError.noRootCA
        }
        let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
        _ = try RootCAFingerprintVerifier.verifiedFingerprint(
            certificatePEM: pem,
            expectedFingerprint: snapshot.fingerprintSHA256
        )
        return pem
    }

    private static func presentSummary(
        simulators: [BootedSimulator],
        results: [BootedSimulator: Result<Void, SimulatorCertificateInstallerError>]
    ) {
        let outcome = summary(simulators: simulators, results: results)
        var lines: [String] = outcome.installed.map { "✓ \($0.displayName)" }
        lines += outcome.failed.map { "✗ \($0.0.displayName) — \($0.1)" }
        if outcome.failed.isEmpty {
            present(
                title: String(localized: "Certificate Installed", bundle: RockxyLocalization.bundle),
                message: lines.joined(separator: "\n") + "\n\n" + String(
                    localized: "Relaunch the app in the simulator, then enable HTTPS decryption for its hosts.",
                    bundle: RockxyLocalization.bundle
                ),
                style: .informational
            )
        } else {
            present(
                title: String(localized: "Some Simulators Were Not Updated", bundle: RockxyLocalization.bundle),
                message: lines.joined(separator: "\n"),
                style: .warning
            )
        }
    }

    private static func present(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
        alert.runModal()
    }
}
