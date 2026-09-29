import AppKit
import Foundation

// Confirmed adb actions that route running Android emulators through Rockxy and back.

// MARK: - AndroidEmulatorSetupFlow

@MainActor
enum AndroidEmulatorSetupFlow {
    /// Lists running emulators, asks before changing them, sets their proxy to
    /// 10.0.2.2:`proxyPort`, and copies the verified root certificate.
    static func route(proxyPort: Int, controller: AndroidEmulatorProxyController = AndroidEmulatorProxyController()) async {
        guard let emulators = await runningEmulators(controller) else {
            return
        }
        let list = emulators.map { "• \($0.serial)" }.joined(separator: "\n")
        guard confirm(
            title: String(AttributedString(
                localized: "Route ^[\(emulators.count) running emulator](inflect: true) through Rockxy?",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters),
            message: list + "\n\n" + String(
                localized: "Rockxy sets each emulator's HTTP proxy to \(AndroidEmulatorProxyController.hostLoopbackAlias):\(String(proxyPort)) and copies the root certificate to its Download folder. Revert the proxy before quitting Rockxy, or the emulator loses its connection.",
                bundle: RockxyLocalization.bundle
            ),
            action: String(localized: "Route Emulators", bundle: RockxyLocalization.bundle)
        ) else {
            return
        }
        let pem = try? await verifiedRootCertificatePEM()
        let results = await controller.routeThroughRockxy(emulators, proxyPort: proxyPort, certificatePEM: pem)
        let failures = summarize(emulators, results)
        if failures.isEmpty {
            present(
                title: String(localized: "Emulators Use Rockxy", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: """
                    To decrypt HTTPS, install rockxy-root-ca.pem from Settings > Security > Encryption & \
                    credentials > Install a certificate > CA certificate, and trust user certificates in \
                    your app's debug network security config.
                    """,
                    bundle: RockxyLocalization.bundle
                ),
                style: .informational
            )
        } else {
            presentFailures(failures)
        }
    }

    /// Clears the HTTP proxy on every running emulator.
    static func revert(controller: AndroidEmulatorProxyController = AndroidEmulatorProxyController()) async {
        guard let emulators = await runningEmulators(controller) else {
            return
        }
        let failures = summarize(emulators, await controller.revertProxy(emulators))
        if failures.isEmpty {
            present(
                title: String(localized: "Emulator Proxy Reverted", bundle: RockxyLocalization.bundle),
                message: emulators.map { "✓ \($0.serial)" }.joined(separator: "\n"),
                style: .informational
            )
        } else {
            presentFailures(failures)
        }
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

    private static func confirm(title: String, message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        return alert.runModal() == .alertFirstButtonReturn
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
