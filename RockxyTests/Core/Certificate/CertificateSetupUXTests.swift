import Crypto
import Foundation
@testable import Rockxy
import Testing
import X509

// MARK: - CertificateSetupUXTests

struct CertificateSetupUXTests {
    // MARK: Internal

    @Test("certificate status maps all setup states")
    func certificateStatusMapping() {
        #expect(CertificateSetupState(snapshot: snapshot(generated: true, installed: true, trusted: true)) ==
            .installedAndTrusted)
        #expect(CertificateSetupState(snapshot: snapshot(generated: true, installed: true, trusted: false)) ==
            .installedNotTrusted)
        #expect(CertificateSetupState(snapshot: snapshot(generated: true, installed: false, trusted: false)) ==
            .generatedOnly)
        #expect(CertificateSetupState(snapshot: snapshot(generated: false, installed: false, trusted: false)) ==
            .missing)
    }

    @Test("certificate menu routes every action to the expected destination")
    func menuRoutes() {
        let router = CertificateMenuActionRouter()

        #expect(router.route(for: .installOnMac) == .openCertificateSetupGuide)
        #expect(router.route(for: .installOniOSDevice) == .openDeveloperSetup(targetID: .iosDevice, tab: .setup))
        #expect(router.route(for: .installOniOSSimulator) == .openDeveloperSetup(targetID: .iosSimulator, tab: .setup))
        #expect(router.route(for: .installOnAndroidDevice) == .openDeveloperSetup(
            targetID: .androidDevice,
            tab: .setup
        ))
        #expect(router.route(for: .installOnAndroidEmulator) == .openDeveloperSetup(
            targetID: .androidEmulator,
            tab: .setup
        ))
        #expect(router.route(for: .installOnJavaVMs) == .openDeveloperSetup(targetID: .javaVMs, tab: .setup))
        #expect(router.route(for: .installOnFirefox) == .openDeveloperSetup(targetID: .firefox, tab: .setup))
        #expect(router.route(for: .installOnDevelopment(.flutter)) == .openDeveloperSetup(
            targetID: .flutter,
            tab: .setup
        ))
        #expect(router.route(for: .addCustomCertificates) == .openCustomCertificates)
        #expect(router.route(for: .export(.rootCertificatePEM)) == .export(.rootCertificatePEM))
        #expect(router.route(for: .resetAll) == .resetAll)
    }

    @Test("manage certificates targets the General settings tab")
    func manageCertificatesSelectsGeneralSettings() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "CertificateSetupUXTests.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RockxySettingsTab.select(.general, defaults: defaults)

        #expect(defaults.string(forKey: RockxySettingsTab.defaultsKey) == RockxySettingsTab.general.rawValue)
    }

    @Test("manual trust command uses the public root CA PEM path")
    func rootCAPublicPEMPath() async throws {
        let overrides = try await installSharedTestOverrides()
        defer { overrides.cleanup() }

        let url = CertificateStore.rootCACertificateURL

        #expect(url.deletingLastPathComponent() == overrides.storageDir)
        #expect(url.lastPathComponent == "rootCA.pem")
    }

    @Test("export service builds PEM DER P12 and private key payloads")
    func exportPayloadSuccess() async throws {
        let root = try RootCAGenerator.generate()
        let service = CertificateExportService {
            CertificateExportMaterial(certificate: root.certificate, privateKey: root.privateKey)
        }

        let pem = try await service.payload(for: .rootCertificatePEM)
        let der = try await service.payload(for: .rootCertificateDER)
        let p12 = try await service.payload(for: .rootCertificateP12)
        let privateKey = try await service.payload(for: .privateKey)

        #expect(String(data: pem.data, encoding: .utf8)?.contains("BEGIN CERTIFICATE") == true)
        #expect(der.data.isEmpty == false)
        #expect(p12.data.isEmpty == false)
        #expect(p12.containsPrivateMaterial)
        #expect(String(data: privateKey.data, encoding: .utf8)?.contains("BEGIN PRIVATE KEY") == true)
        #expect(privateKey.containsPrivateMaterial)
    }

    @Test("export service reports missing certificate and key")
    func exportMissingMaterial() async throws {
        let noCertificate = CertificateExportService {
            CertificateExportMaterial(certificate: nil, privateKey: nil)
        }
        await #expect(throws: CertificateExportError.missingCertificate) {
            _ = try await noCertificate.payload(for: .rootCertificatePEM)
        }

        let root = try RootCAGenerator.generate()
        let noKey = CertificateExportService {
            CertificateExportMaterial(certificate: root.certificate, privateKey: nil)
        }
        await #expect(throws: CertificateExportError.missingPrivateKey) {
            _ = try await noKey.payload(for: .privateKey)
        }
    }

    @Test("export service surfaces write failures")
    func exportWriteFailure() async throws {
        struct WriteFailure: Error {}
        let root = try RootCAGenerator.generate()
        let service = CertificateExportService(
            materialProvider: {
                CertificateExportMaterial(certificate: root.certificate, privateKey: root.privateKey)
            },
            writeHandler: { _, _ in throw WriteFailure() }
        )
        let payload = try await service.payload(for: .rootCertificatePEM)

        #expect(throws: WriteFailure.self) {
            try service.export(payload, to: URL(fileURLWithPath: "/tmp/unused.pem"))
        }
    }

    // MARK: Private

    private func snapshot(generated: Bool, installed: Bool, trusted: Bool) -> RootCAStatusSnapshot {
        RootCAStatusSnapshot(
            hasGeneratedCertificate: generated,
            isInstalledInKeychain: installed,
            hasTrustSettings: trusted,
            isSystemTrustValidated: trusted,
            notValidBefore: nil,
            notValidAfter: nil,
            fingerprintSHA256: nil,
            commonName: nil,
            lastValidationErrorMessage: nil
        )
    }
}
