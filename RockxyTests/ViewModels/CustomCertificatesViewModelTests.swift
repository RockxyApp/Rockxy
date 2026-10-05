import Crypto
import Foundation
@testable import Rockxy
import SwiftASN1
import Testing
import X509

// MARK: - CustomCertificatesViewModelTests

@MainActor
@Suite(.serialized)
struct CustomCertificatesViewModelTests {
    @Test("Empty manager starts with an honest unavailable root state")
    func emptyManagerHasUnavailableRootState() {
        let environment = makeEnvironment()
        defer { environment.cleanup() }

        let viewModel = CustomCertificatesViewModel(manager: environment.manager)

        #expect(viewModel.rootStatus == .unavailable)
        #expect(viewModel.canPreview == false)
        #expect(viewModel.canPerformPrimaryDestructive == false)
    }

    @Test("Custom root is never reported active when its private key is unavailable")
    func customRootRequiresUsableIssuerSnapshot() throws {
        let environment = makeEnvironment()
        defer { environment.cleanup() }
        let root = try RootCAGenerator.generate()
        let metadata = try environment.manager.importRoot(
            displayName: "Unavailable Root",
            certificatePEM: try pem(root.certificate),
            privateKeyPEM: root.privateKey.pemRepresentation
        )
        environment.store.delete(account: metadata.keychainAccount)
        let viewModel = CustomCertificatesViewModel(manager: environment.manager)

        #expect(viewModel.rootStatus == .customVerifying)
        let generation = viewModel.beginRootRefresh()
        #expect(
            viewModel.applyDefaultRoot(
                certificate: nil,
                snapshot: emptySnapshot,
                customRootAvailability: false,
                generation: generation
            )
        )
        #expect(viewModel.rootStatus == .customUnavailable)
        #expect(viewModel.rootStatusText == "Custom Root Unavailable")

        let activeGeneration = viewModel.beginRootRefresh()
        #expect(
            viewModel.applyDefaultRoot(
                certificate: nil,
                snapshot: emptySnapshot,
                customRootAvailability: true,
                generation: activeGeneration
            )
        )
        #expect(viewModel.rootStatus == .customActive)
    }

    @Test("Preview and delete target the selected server certificate")
    func selectedServerCertificateOwnsActions() throws {
        let environment = makeEnvironment()
        defer { environment.cleanup() }
        let first = try importServer(host: "one.example.com", into: environment.manager)
        _ = try importServer(host: "two.example.com", into: environment.manager)
        let viewModel = CustomCertificatesViewModel(manager: environment.manager)

        viewModel.mode = .server
        viewModel.selectedServerID = first.id
        viewModel.requestPrimaryDeletion()

        #expect(viewModel.selectedListEntry?.id == first.id)
        #expect(viewModel.canPreview)
        #expect(viewModel.pendingDeletion?.target == .certificate(first.id))
    }

    @Test("Confirmed delete removes only the selected row and selects its neighbor")
    func deletingSelectionPreservesOtherRows() async throws {
        let environment = makeEnvironment()
        defer { environment.cleanup() }
        let first = try importServer(host: "one.example.com", into: environment.manager)
        let second = try importServer(host: "two.example.com", into: environment.manager)
        let viewModel = CustomCertificatesViewModel(manager: environment.manager)

        viewModel.mode = .server
        viewModel.selectedServerID = first.id
        viewModel.requestPrimaryDeletion()
        await viewModel.confirmPendingDeletion()

        #expect(environment.manager.metadata(kind: .server).map(\.id) == [second.id])
        #expect(viewModel.serverEntries.map(\.id) == [second.id])
        #expect(viewModel.selectedServerID == second.id)
        #expect(viewModel.statusTone == .success)
    }

    @Test("A confirmed delete still runs after the dialog clears the pending request")
    func confirmationSurvivesDialogDismissal() async throws {
        let environment = makeEnvironment()
        defer { environment.cleanup() }
        let first = try importServer(host: "one.example.com", into: environment.manager)
        let second = try importServer(host: "two.example.com", into: environment.manager)
        let viewModel = CustomCertificatesViewModel(manager: environment.manager)

        viewModel.mode = .server
        viewModel.selectedServerID = first.id
        viewModel.requestPrimaryDeletion()
        let shown = try #require(viewModel.pendingDeletion)
        // SwiftUI sets the dialog's isPresented binding to false before the async action runs.
        viewModel.pendingDeletion = nil
        await viewModel.confirmDeletion(shown)

        #expect(environment.manager.metadata(kind: .server).map(\.id) == [second.id])
        #expect(viewModel.statusTone == .success)
    }

    @Test("Switching tabs clears the previous tab's result message")
    func switchingTabsClearsStatus() async throws {
        let environment = makeEnvironment()
        defer { environment.cleanup() }
        let first = try importServer(host: "one.example.com", into: environment.manager)
        let viewModel = CustomCertificatesViewModel(manager: environment.manager)

        viewModel.mode = .server
        viewModel.selectedServerID = first.id
        viewModel.requestPrimaryDeletion()
        await viewModel.confirmPendingDeletion()
        #expect(viewModel.statusMessage == "Certificate deleted.")

        viewModel.mode = .client
        #expect(viewModel.statusMessage == nil)
    }

    @Test("Host input uses bare-host validation and canonical normalization")
    func validatesAndNormalizesHostPatterns() {
        let environment = makeEnvironment()
        defer { environment.cleanup() }
        let viewModel = CustomCertificatesViewModel(manager: environment.manager)

        #expect(viewModel.hostValidationMessage(for: "https://api.example.com/path") != nil)
        #expect(viewModel.hostValidationMessage(for: "*.example.com") == nil)
        #expect(viewModel.normalizedHostPattern("  API.Example.COM  ") == "api.example.com")
    }

    @Test("Only the newest default-root refresh result can update visible state")
    func staleRootRefreshCannotOverwriteNewerState() {
        let environment = makeEnvironment()
        defer { environment.cleanup() }
        let viewModel = CustomCertificatesViewModel(manager: environment.manager)
        let staleGeneration = viewModel.beginRootRefresh()
        let currentGeneration = viewModel.beginRootRefresh()

        #expect(
            viewModel.applyDefaultRoot(
                certificate: nil,
                snapshot: emptySnapshot,
                generation: staleGeneration
            ) == false
        )
        #expect(viewModel.isLoadingDefaultRoot)
        #expect(
            viewModel.applyDefaultRoot(
                certificate: nil,
                snapshot: emptySnapshot,
                generation: currentGeneration
            )
        )
        #expect(viewModel.isLoadingDefaultRoot == false)
    }

    @Test("Async import selects the persisted identity and normalizes its host")
    func asyncImportSelectsPersistedIdentity() async throws {
        let environment = makeEnvironment()
        defer { environment.cleanup() }
        let identity = try makeLeafIdentity(host: "import.example.com")
        let certificateURL = environment.directory.appendingPathComponent("leaf.pem")
        let keyURL = environment.directory.appendingPathComponent("leaf.key")
        try FileManager.default.createDirectory(
            at: environment.directory,
            withIntermediateDirectories: true
        )
        try Data(identity.certificatePEM.utf8).write(to: certificateURL)
        try Data(identity.privateKeyPEM.utf8).write(to: keyURL)
        let viewModel = CustomCertificatesViewModel(manager: environment.manager)
        viewModel.mode = .server

        await viewModel.importCertificateAndKey(
            certificateURL: certificateURL,
            privateKeyURL: keyURL,
            displayName: "Imported Leaf",
            kind: .server,
            hostPattern: "  IMPORT.Example.COM "
        )

        let imported = try #require(environment.manager.metadata(kind: .server).last)
        #expect(imported.hostPattern == "import.example.com")
        #expect(viewModel.selectedServerID == imported.id)
        #expect(viewModel.statusTone == .success)
    }

    // MARK: Private

    private struct Environment {
        let directory: URL
        let manager: CustomCertificateManager
        let store: MemoryStore

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private final class MemoryStore: SecureDataStore, @unchecked Sendable {
        func save(_ data: Data, account: String) {
            lock.withLock {
                values[account] = data
            }
        }

        func load(account: String) -> Data? {
            lock.withLock { values[account] }
        }

        func delete(account: String) {
            lock.withLock {
                _ = values.removeValue(forKey: account)
            }
        }

        private let lock = NSLock()
        private var values: [String: Data] = [:]
    }

    private func makeEnvironment() -> Environment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyCustomCertificateViewModelTests-\(UUID().uuidString)", isDirectory: true)
        let store = MemoryStore()
        let manager = CustomCertificateManager(
            storageURL: directory.appendingPathComponent("custom-certificates.json"),
            secureStore: store
        )
        return Environment(directory: directory, manager: manager, store: store)
    }

    private var emptySnapshot: RootCAStatusSnapshot {
        RootCAStatusSnapshot(
            hasGeneratedCertificate: false,
            isInstalledInKeychain: false,
            hasTrustSettings: false,
            isSystemTrustValidated: false,
            notValidBefore: nil,
            notValidAfter: nil,
            fingerprintSHA256: nil,
            commonName: nil,
            lastValidationErrorMessage: nil
        )
    }

    private func importServer(
        host: String,
        into manager: CustomCertificateManager
    )
        throws -> CustomCertificateMetadata
    {
        let identity = try makeLeafIdentity(host: host)
        return try manager.importServerIdentity(
            hostPattern: host,
            displayName: host,
            certificatePEM: identity.certificatePEM,
            privateKeyPEM: identity.privateKeyPEM
        )
    }

    private func makeLeafIdentity(host: String) throws -> (certificatePEM: String, privateKeyPEM: String) {
        let root = try RootCAGenerator.generate()
        let leaf = try HostCertGenerator.generate(
            host: host,
            issuer: root.certificate,
            issuerKey: root.privateKey
        )
        return (try pem(leaf.certificate), leaf.privateKey.pemRepresentation)
    }

    private func pem(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
    }
}
