import AppKit
import Foundation

// Confirmed adb actions that route running Android emulators through Rockxy and back.

// MARK: - AndroidEmulatorSetupFlow

@MainActor
enum AndroidEmulatorSetupFlow {
    // MARK: Internal

    /// True while this run of Rockxy has pointed an emulator at its proxy and not reverted it.
    static var hasRoutedEmulators = false

    /// Lists running emulators, asks before changing them, sets their proxy to
    /// 10.0.2.2:`proxyPort`, and copies the verified root certificate.
    static func route(
        proxyPort: Int,
        proxyRunning: Bool = true,
        controller: AndroidEmulatorProxyController = AndroidEmulatorProxyController()
    )
        async
    {
        // A stopped proxy would leave every routed emulator pointing at a dead port.
        guard proxyRunning else {
            present(
                title: String(localized: "Start the Proxy First", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Emulators lose their connection when routed to a proxy that is not running. Start Rockxy's proxy, then route them.",
                    bundle: RockxyLocalization.bundle
                ),
                style: .warning
            )
            return
        }
        guard let emulators = await runningEmulators(controller) else {
            return
        }
        let list = emulators.map { "• \($0.serial)" }.joined(separator: "\n")
        guard let trustSystemWide = confirmRoute(
            title: String(AttributedString(
                localized: "Route ^[\(emulators.count) running emulator](inflect: true) through Rockxy?",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters),
            message: list + "\n\n" + String(
                localized: "Rockxy sets each emulator's HTTP proxy to \(AndroidEmulatorProxyController.hostLoopbackAlias):\(String(proxyPort)) and copies the root certificate to its Download folder. Revert the proxy before quitting Rockxy, or the emulator loses its connection.",
                bundle: RockxyLocalization.bundle
            )
        ) else {
            return
        }
        let pem: String
        do {
            pem = try await verifiedRootCertificatePEM()
        } catch {
            present(
                title: String(localized: "Certificate Unavailable", bundle: RockxyLocalization.bundle),
                message: error.localizedDescription,
                style: .warning
            )
            return
        }
        let results = await controller.routeThroughRockxy(emulators, proxyPort: proxyPort, certificatePEM: pem)
        let failures = summarize(emulators, results)
        if failures.count < emulators.count {
            hasRoutedEmulators = true
        }
        guard failures.isEmpty else {
            presentFailures(failures)
            return
        }
        guard trustSystemWide else {
            present(
                title: String(localized: "Emulators Use Rockxy", bundle: RockxyLocalization.bundle),
                message: userCertificateInstructions,
                style: .informational
            )
            return
        }
        let trust = await controller.trustSystemWide(emulators, certificatePEM: pem)
        let trustFailures = summarize(emulators, trust)
        if trustFailures.isEmpty {
            present(
                title: String(localized: "Emulators Use Rockxy", bundle: RockxyLocalization.bundle),
                message: emulators.map { "✓ \($0.serial)" }.joined(separator: "\n") + "\n\n" + String(
                    localized: """
                    Apps on these emulators trust Rockxy's certificate until the emulator restarts, and Chrome \
                    until you revert. Enable HTTPS decryption for the hosts you want to read, then relaunch the app.
                    """,
                    bundle: RockxyLocalization.bundle
                ),
                style: .informational
            )
        } else {
            present(
                title: String(localized: "Proxy Set; System Trust Incomplete", bundle: RockxyLocalization.bundle),
                message: trustFailures.map { "✗ \($0.0.serial) — \($0.1)" }.joined(separator: "\n")
                    + "\n\n" + userCertificateInstructions,
                style: .warning
            )
        }
    }

    /// Clears the HTTP proxy on every running emulator.
    static func revert(controller: AndroidEmulatorProxyController = AndroidEmulatorProxyController()) async {
        guard let emulators = await runningEmulators(controller) else {
            return
        }
        let proxyResults = await controller.revertProxy(emulators)
        let trustResults = await controller.removeSystemTrust(emulators)
        let failures = summarize(emulators, proxyResults) + summarize(emulators, trustResults)
        if failures.isEmpty {
            hasRoutedEmulators = false
            present(
                title: String(localized: "Emulator Proxy Reverted", bundle: RockxyLocalization.bundle),
                message: emulators.map { "✓ \($0.serial)" }.joined(separator: "\n"),
                style: .informational
            )
        } else {
            presentFailures(failures)
        }
    }

    /// Clears the emulator proxy without any UI; used while quitting so a routed emulator
    /// is never left pointing at a proxy that no longer exists.
    static func revertQuietly(controller: AndroidEmulatorProxyController = AndroidEmulatorProxyController()) async {
        guard hasRoutedEmulators else {
            return
        }
        hasRoutedEmulators = false
        guard let emulators = try? await controller.runningEmulators(), !emulators.isEmpty else {
            return
        }
        _ = await controller.revertProxy(emulators)
    }

    static func summarize(
        _ emulators: [AndroidEmulator],
        _ results: [AndroidEmulator: Result<Void, AndroidEmulatorError>]
    )
        -> [(AndroidEmulator, String)]
    {
        emulators.compactMap { emulator in
            switch results[emulator] {
            case .success:
                nil
            case let .failure(error):
                (emulator, error.localizedDescription)
            case nil:
                (emulator, AndroidEmulatorError.commandFailed(status: -1, message: nil).localizedDescription)
            }
        }
    }

    // MARK: Private

    private static var userCertificateInstructions: String {
        String(
            localized: """
            To decrypt HTTPS, install rockxy-root-ca.pem from Settings > Security > Encryption & \
            credentials > Install a certificate > CA certificate, and trust user certificates in \
            your app's debug network security config.
            """,
            bundle: RockxyLocalization.bundle
        )
    }

    private static func runningEmulators(_ controller: AndroidEmulatorProxyController) async -> [AndroidEmulator]? {
        do {
            let emulators = try await controller.runningEmulators()
            guard !emulators.isEmpty else {
                present(
                    title: String(localized: "No Running Emulators", bundle: RockxyLocalization.bundle),
                    message: String(
                        localized: "Start an emulator from Android Studio's Device Manager, then try again.",
                        bundle: RockxyLocalization.bundle
                    ),
                    style: .informational
                )
                return nil
            }
            return emulators
        } catch {
            present(
                title: String(localized: "Emulators Unavailable", bundle: RockxyLocalization.bundle),
                message: error.localizedDescription,
                style: .warning
            )
            return nil
        }
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

    /// The route confirmation, with an opt-out checkbox for system-store trust. Returns
    /// whether system trust was chosen, or nil when the user cancels.
    private static func confirmRoute(title: String, message: String) -> Bool? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        let checkbox = NSButton(
            checkboxWithTitle: String(
                localized: "Also trust the certificate system-wide (roots Google APIs emulators until they restart)",
                bundle: RockxyLocalization.bundle
            ),
            target: nil,
            action: nil
        )
        checkbox.state = .on
        checkbox.setAccessibilityIdentifier("androidEmulator.trustSystemWide")
        alert.accessoryView = checkbox
        alert.addButton(withTitle: String(localized: "Route Emulators", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return checkbox.state == .on
    }

    private static func presentFailures(_ failures: [(AndroidEmulator, String)]) {
        present(
            title: String(localized: "Some Emulators Were Not Updated", bundle: RockxyLocalization.bundle),
            message: failures.map { "✗ \($0.0.serial) — \($0.1)" }.joined(separator: "\n"),
            style: .warning
        )
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
