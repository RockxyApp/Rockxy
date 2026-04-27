import AppKit
import Combine
import Foundation

// MARK: - CAShareController

@MainActor
final class CAShareController: ObservableObject {
    @Published var currentSession: RootCADownloadSession?
    @Published var currentFingerprint: String?

    func startSharing() async throws -> RootCADownloadSession {
        currentSession = nil
        currentFingerprint = nil

        try await CertificateManager.shared.ensureRootCA()
        guard let pem = try await CertificateManager.shared.getRootCAPEM() else {
            throw RootCADownloadError.noRootCA
        }

        let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
        let fingerprint = try RootCAFingerprintVerifier.verifiedFingerprint(
            certificatePEM: pem,
            expectedFingerprint: snapshot.fingerprintSHA256
        )
        let session = try await shareServer.start(certificatePEM: pem)

        currentFingerprint = fingerprint
        currentSession = session
        return session
    }

    func copyShareURL(sessionURL: URL) throws {
        guard currentFingerprint != nil else {
            throw RootCAShareValidationError.missingFingerprint
        }
        guard currentSession?.publicURL == sessionURL else {
            throw RootCADownloadError.invalidSessionURL
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sessionURL.absoluteString, forType: .string)
    }

    func stopSharing(clearSession: Bool) async {
        await shareServer.stop()
        if clearSession {
            currentSession = nil
            currentFingerprint = nil
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        switch error {
        case let error as RootCADownloadError:
            switch error {
            case .tokenGenerationFailed:
                String(localized: "Could not create a secure certificate sharing token. Try again.")
            case .invalidSessionURL:
                String(localized: "Could not build the certificate sharing URL. Try again.")
            case .noReachableLANAddress:
                String(localized: "No reachable Wi-Fi or Ethernet IPv4 address was found. Connect this Mac to the same network as the device, then try again.")
            case .noRootCA:
                String(localized: "No Root CA certificate is available. Generate a Root CA first.")
            case .portUnavailable:
                String(localized: "Could not start the temporary certificate sharing server. Try again.")
            }
        case let error as RootCAShareValidationError:
            error.localizedDescription
        default:
            String(localized: "Certificate sharing could not be started. Check your network and try again.")
        }
    }

    private let shareServer = RootCADownloadServer()
}
