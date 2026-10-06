import AppKit
import Foundation

// Guided, confirmed install of the Rockxy root certificate into booted simulators.

// MARK: - SimulatorCertificateInstallFlow

/// Lists the simulators that are booted now, asks before changing their trust
/// store, installs the verified public root certificate, and reports each
/// simulator's outcome. Trust changes only happen after the user confirms.
@MainActor
enum SimulatorCertificateInstallFlow {
    // MARK: Internal

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

        let before = installer.trustStatus(of: simulators, certificatePEM: certificatePEM)
        guard confirm(simulators, statuses: before) else {
            return
        }

        var results = await installer.installRootCertificate(pem: certificatePEM, into: simulators)
        // simctl can exit cleanly without changing the store; trust only what the store shows.
        let after = installer.trustStatus(of: simulators, certificatePEM: certificatePEM)
        for simulator in simulators where after[simulator] == .missing {
            if case .success = results[simulator] {
                results[simulator] = .failure(.commandFailed(
                    status: 0,
                    message: String(
                        localized: "The certificate is not in the simulator's trust store after installing.",
                        bundle: RockxyLocalization.bundle
                    )
                ))
            }
        }
        presentSummary(simulators: simulators, results: results)
    }

    /// One line per simulator for the confirmation, with its current trust state.
    static func statusLines(
        _ simulators: [BootedSimulator],
        statuses: [BootedSimulator: SimulatorTrustStatus]
    )
        -> String
    {
        simulators.map { simulator in
            switch statuses[simulator] ?? .unknown {
            case .trusted:
                "• " + String(
                    localized: "\(simulator.displayName) — already trusts Rockxy",
                    bundle: RockxyLocalization.bundle
                )
            case .missing:
                "• " + String(
                    localized: "\(simulator.displayName) — certificate not installed",
                    bundle: RockxyLocalization.bundle
                )
            case .unknown:
                "• \(simulator.displayName)"
            }
        }.joined(separator: "\n")
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

    private static func confirm(
        _ simulators: [BootedSimulator],
        statuses: [BootedSimulator: SimulatorTrustStatus]
    )
        -> Bool
    {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(AttributedString(
            localized: "Install the Rockxy root certificate in ^[\(simulators.count) booted simulator](inflect: true)?",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
        alert.informativeText = statusLines(simulators, statuses: statuses) + "\n\n" + String(
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
