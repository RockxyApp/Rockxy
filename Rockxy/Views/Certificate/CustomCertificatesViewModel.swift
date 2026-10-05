import Foundation

// MARK: - CustomCertificateStatusTone

enum CustomCertificateStatusTone: Equatable {
    case neutral
    case success
    case warning
    case error
}

// MARK: - CustomCertificateFileError

enum CustomCertificateFileError: LocalizedError, Equatable {
    case fileTooLarge

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            String(localized: "Certificate files must be 16 MB or smaller.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - CustomCertificatesViewModel

/// State owner for the Custom Certificates window.
///
/// Presents the root / server / client custom-certificate lists with real
/// UUID-backed selection. Every preview and destructive action targets the
/// selected certificate — never the newest or all entries implicitly. Host
/// patterns are trimmed, lowercased, and validated with `SSLHostPatternValidation`
/// before any Keychain or metadata write. Expensive file reads and certificate /
/// P12 parsing run off the main actor, and the asynchronous default-root refresh
/// is generation-checked so a late result cannot overwrite newer state.
@MainActor @Observable
final class CustomCertificatesViewModel {
    // MARK: Lifecycle

    init(manager: CustomCertificateManager = .shared) {
        self.manager = manager
        reload()
    }

    // MARK: Internal

    enum Mode: String, CaseIterable, Identifiable {
        case root
        case server
        case client

        // MARK: Internal

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .root:
                String(localized: "Root Certificate", bundle: RockxyLocalization.bundle)
            case .server:
                String(localized: "Server Certificates", bundle: RockxyLocalization.bundle)
            case .client:
                String(localized: "Client Certificates", bundle: RockxyLocalization.bundle)
            }
        }

        var kind: CustomCertificateKind {
            switch self {
            case .root:
                .root
            case .server:
                .server
            case .client:
                .client
            }
        }
    }

    enum RootTrustStatus: Equatable {
        case customVerifying
        case customActive
        case customUnavailable
        case installedTrusted
        case installedNotTrusted
        case generated
        case unavailable
    }

    struct DeletionRequest: Identifiable, Equatable {
        enum Target: Equatable {
            case revertRoot
            case certificate(UUID)
        }

        let id = UUID()
        let target: Target
        let title: String
        let message: String
        let confirmLabel: String
    }

    let manager: CustomCertificateManager

    var selectedServerID: UUID?
    var selectedClientID: UUID?
    var errorMessage: String?
    var pendingDeletion: DeletionRequest?
    private(set) var statusMessage: String?
    private(set) var statusTone: CustomCertificateStatusTone = .neutral
    private(set) var rootLoadErrorMessage: String?

    var defaultRootCertificate: CertificatePreviewItem?
    var defaultRootSnapshot: RootCAStatusSnapshot?

    private(set) var rootEntries: [CustomCertificateMetadata] = []
    private(set) var serverEntries: [CustomCertificateMetadata] = []
    private(set) var clientEntries: [CustomCertificateMetadata] = []
    private(set) var isLoadingDefaultRoot = false
    private(set) var isImporting = false
    private(set) var isDeleting = false
    private(set) var rootRefreshGeneration = 0
    private(set) var importGeneration = 0
    private(set) var customRootAvailability: Bool?

    var mode: Mode = .root {
        didSet {
            guard oldValue != mode else {
                return
            }
            if isImporting {
                importGeneration += 1
            }
            // A result belongs to the tab it happened on ("Certificate deleted.", "Rockxy is using
            // its default root certificate."); it must not read as a statement about the new tab.
            if !isBusy {
                statusMessage = nil
                statusTone = .neutral
            }
            reconcileSelection()
        }
    }

    var isBusy: Bool {
        isImporting || isDeleting
    }

    // MARK: - Derived Root State

    var activeRootEntry: CustomCertificateMetadata? {
        rootEntries.last
    }

    var hasCustomRoot: Bool {
        !rootEntries.isEmpty
    }

    var rootStatus: RootTrustStatus {
        if hasCustomRoot {
            if customRootAvailability == true {
                return .customActive
            }
            if customRootAvailability == false {
                return .customUnavailable
            }
            return .customVerifying
        }
        if defaultRootSnapshot?.isInstalledInKeychain == true,
           defaultRootSnapshot?.isSystemTrustValidated == true
        {
            return .installedTrusted
        }
        if defaultRootSnapshot?.isInstalledInKeychain == true {
            return .installedNotTrusted
        }
        if defaultRootSnapshot?.hasGeneratedCertificate == true {
            return .generated
        }
        return .unavailable
    }

    var rootTitle: String {
        if let activeRootEntry {
            return activeRootEntry.displayName
        }
        return rootStatus == .unavailable
            ? String(localized: "No Root Certificate", bundle: RockxyLocalization.bundle)
            : String(localized: "Rockxy Default Root Certificate", bundle: RockxyLocalization.bundle)
    }

    var rootSubtitle: String {
        switch rootStatus {
        case .customVerifying:
            String(localized: "Rockxy is verifying this custom root certificate and its private key.", bundle: RockxyLocalization.bundle)
        case .customActive:
            String(localized: "Rockxy signs generated host certificates with this imported root.", bundle: RockxyLocalization.bundle)
        case .customUnavailable:
            String(localized: "Rockxy cannot access this custom root certificate and its private key.", bundle: RockxyLocalization.bundle)
        case .installedTrusted,
             .installedNotTrusted,
             .generated:
            String(localized: "Rockxy signs generated host certificates with its default root.", bundle: RockxyLocalization.bundle)
        case .unavailable:
            String(localized: "No root certificate is loaded. HTTPS interception is unavailable.", bundle: RockxyLocalization.bundle)
        }
    }

    var rootStatusText: String {
        switch rootStatus {
        case .customVerifying:
            String(localized: "Verifying Custom Root…", bundle: RockxyLocalization.bundle)
        case .customActive:
            String(localized: "Custom Root Active", bundle: RockxyLocalization.bundle)
        case .customUnavailable:
            String(localized: "Custom Root Unavailable", bundle: RockxyLocalization.bundle)
        case .installedTrusted:
            String(localized: "Installed & Trusted", bundle: RockxyLocalization.bundle)
        case .installedNotTrusted:
            String(localized: "Installed, Trust Not Verified", bundle: RockxyLocalization.bundle)
        case .generated:
            String(localized: "Generated, Not Installed", bundle: RockxyLocalization.bundle)
        case .unavailable:
            String(localized: "No Default Root Available", bundle: RockxyLocalization.bundle)
        }
    }

    // MARK: - Selection

    var selectedServerEntry: CustomCertificateMetadata? {
        serverEntries.first { $0.id == selectedServerID }
    }

    var selectedClientEntry: CustomCertificateMetadata? {
        clientEntries.first { $0.id == selectedClientID }
    }

    /// The certificate a preview / delete action would target for the current mode.
    var selectedListEntry: CustomCertificateMetadata? {
        switch mode {
        case .root:
            activeRootEntry
        case .server:
            selectedServerEntry
        case .client:
            selectedClientEntry
        }
    }

    var previewItem: CertificatePreviewItem? {
        switch mode {
        case .root:
            if let entry = activeRootEntry, let item = try? CertificatePreviewItem(metadata: entry) {
                return item
            }
            return defaultRootCertificate
        case .server:
            return selectedServerEntry.flatMap { try? CertificatePreviewItem(metadata: $0) }
        case .client:
            return selectedClientEntry.flatMap { try? CertificatePreviewItem(metadata: $0) }
        }
    }

    var canPreview: Bool {
        previewItem != nil
    }

    var primaryDestructiveTitle: String {
        mode == .root ? String(localized: "Revert to Default…", bundle: RockxyLocalization.bundle) : String(localized: "Delete…", bundle: RockxyLocalization.bundle)
    }

    var canPerformPrimaryDestructive: Bool {
        switch mode {
        case .root:
            hasCustomRoot
        case .server:
            selectedServerEntry != nil
        case .client:
            selectedClientEntry != nil
        }
    }

    func reload() {
        let updatedRootEntries = manager.metadata(kind: .root)
        if updatedRootEntries.map(\.id) != rootEntries.map(\.id) {
            customRootAvailability = nil
        }
        rootEntries = updatedRootEntries
        serverEntries = manager.metadata(kind: .server)
        clientEntries = manager.metadata(kind: .client)
    }

    /// Drops any selection that no longer corresponds to a visible certificate.
    func reconcileSelection() {
        if let id = selectedServerID, !serverEntries.contains(where: { $0.id == id }) {
            selectedServerID = nil
        }
        if let id = selectedClientID, !clientEntries.contains(where: { $0.id == id }) {
            selectedClientID = nil
        }
    }

    /// Selects the certificate with `id` in whichever list owns it.
    func select(id: UUID) {
        if serverEntries.contains(where: { $0.id == id }) {
            selectedServerID = id
        } else if clientEntries.contains(where: { $0.id == id }) {
            selectedClientID = id
        }
    }

    // MARK: - Host Validation

    func hostValidationMessage(for rawValue: String) -> String? {
        SSLHostPatternValidation.message(for: rawValue)
    }

    func normalizedHostPattern(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Deletion

    func requestPrimaryDeletion() {
        switch mode {
        case .root:
            guard let entry = activeRootEntry else {
                return
            }
            pendingDeletion = revertRootRequest(for: entry)
        case .server:
            guard let entry = selectedServerEntry else {
                return
            }
            pendingDeletion = certificateDeletionRequest(
                for: entry,
                role: String(localized: "server", bundle: RockxyLocalization.bundle)
            )
        case .client:
            guard let entry = selectedClientEntry else {
                return
            }
            pendingDeletion = certificateDeletionRequest(
                for: entry,
                role: String(localized: "client", bundle: RockxyLocalization.bundle)
            )
        }
    }

    func requestDeletion(certificateID id: UUID) {
        if let entry = serverEntries.first(where: { $0.id == id }) {
            selectedServerID = id
            pendingDeletion = certificateDeletionRequest(
                for: entry,
                role: String(localized: "server", bundle: RockxyLocalization.bundle)
            )
        } else if let entry = clientEntries.first(where: { $0.id == id }) {
            selectedClientID = id
            pendingDeletion = certificateDeletionRequest(
                for: entry,
                role: String(localized: "client", bundle: RockxyLocalization.bundle)
            )
        }
    }

    func confirmPendingDeletion() async {
        guard let request = pendingDeletion else {
            return
        }
        await confirmDeletion(request)
    }

    /// Carries out the request the confirmation dialog showed. The dialog clears
    /// `pendingDeletion` as it dismisses, before an async confirmation runs, so the
    /// confirmed request is passed in rather than read back from that property.
    func confirmDeletion(_ request: DeletionRequest) async {
        pendingDeletion = nil
        guard !isBusy else {
            return
        }
        isDeleting = true
        statusMessage = nil
        let manager = self.manager
        do {
            switch request.target {
            case .revertRoot:
                try await Task.detached(priority: .userInitiated) {
                    try manager.deleteAll(kind: .root)
                }.value
            case let .certificate(id):
                try await deleteCertificate(id: id)
            }
            isDeleting = false
            reload()
            reconcileSelection()
            statusMessage = request.target == .revertRoot
                ? String(localized: "Rockxy is using its default root certificate.", bundle: RockxyLocalization.bundle)
                : String(localized: "Certificate deleted.", bundle: RockxyLocalization.bundle)
            statusTone = .success
        } catch {
            isDeleting = false
            errorMessage = error.localizedDescription
            statusMessage = String(localized: "The certificate was not changed.", bundle: RockxyLocalization.bundle)
            statusTone = .error
        }
    }

    // MARK: - Import

    func importCertificateAndKey(
        certificateURL: URL,
        privateKeyURL: URL,
        displayName: String,
        kind: CustomCertificateKind,
        hostPattern rawHost: String?
    )
        async
    {
        await runImport(kind: kind, rawHost: rawHost) { manager, normalizedHost in
            let certificateData = try Self.readBoundedData(from: certificateURL)
            let privateKeyData = try Self.readBoundedData(from: privateKeyURL)
            let identity = try CustomCertificateImportIdentity.fromCertificateAndPrivateKey(
                certificateData: certificateData,
                privateKeyData: privateKeyData,
                displayName: displayName
            )
            return try Self.performImport(identity, kind: kind, hostPattern: normalizedHost, manager: manager)
        }
    }

    func importPKCS12(
        url: URL,
        displayName: String,
        passphrase: String,
        kind: CustomCertificateKind,
        hostPattern rawHost: String?
    )
        async
    {
        await runImport(kind: kind, rawHost: rawHost) { manager, normalizedHost in
            let data = try Self.readBoundedData(from: url)
            let identity = try CustomCertificateImportIdentity.fromPKCS12(
                data: data,
                displayName: displayName,
                passphrase: passphrase
            )
            return try Self.performImport(identity, kind: kind, hostPattern: normalizedHost, manager: manager)
        }
    }

    // MARK: - Default Root Refresh

    /// Bumps the refresh generation and marks the loading state. The returned token
    /// gates a later `applyDefaultRoot` so a stale async result cannot land.
    @discardableResult
    func beginRootRefresh() -> Int {
        rootRefreshGeneration += 1
        isLoadingDefaultRoot = true
        return rootRefreshGeneration
    }

    /// Applies a default-root result only if `generation` is still current.
    @discardableResult
    func applyDefaultRoot(
        certificate: CertificatePreviewItem?,
        snapshot: RootCAStatusSnapshot?,
        customRootAvailability: Bool? = nil,
        generation: Int
    )
        -> Bool
    {
        guard generation == rootRefreshGeneration else {
            return false
        }
        defaultRootCertificate = certificate
        defaultRootSnapshot = snapshot
        self.customRootAvailability = hasCustomRoot ? customRootAvailability : nil
        isLoadingDefaultRoot = false
        return true
    }

    func refreshDefaultRoot() async {
        let generation = beginRootRefresh()
        let manager = self.manager
        let shouldValidateCustomRoot = hasCustomRoot
        let customRootAvailability: Bool? = if shouldValidateCustomRoot {
            await Task.detached(priority: .userInitiated) {
                do {
                    return try manager.activeRootIssuerSnapshot() != nil
                } catch {
                    return false
                }
            }.value
        } else {
            nil
        }
        do {
            let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
            let material = try await CertificateManager.shared.exportMaterial()
            let item: CertificatePreviewItem? = material.certificate.flatMap { certificate in
                try? CertificatePreviewItem(
                    certificate: certificate,
                    displayName: String(localized: "Rockxy Default Root Certificate", bundle: RockxyLocalization.bundle),
                    fingerprintSHA256: snapshot.fingerprintSHA256
                )
            }
            if applyDefaultRoot(
                certificate: item,
                snapshot: snapshot,
                customRootAvailability: customRootAvailability,
                generation: generation
            ) {
                rootLoadErrorMessage = nil
            }
        } catch {
            let snapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
            if applyDefaultRoot(
                certificate: nil,
                snapshot: snapshot,
                customRootAvailability: customRootAvailability,
                generation: generation
            ) {
                rootLoadErrorMessage = String(localized: "Rockxy could not load the default root certificate details.", bundle: RockxyLocalization.bundle)
            }
        }
    }

    // MARK: Private

    private static func mode(for kind: CustomCertificateKind) -> Mode {
        switch kind {
        case .root:
            .root
        case .server:
            .server
        case .client:
            .client
        }
    }

    nonisolated private static func performImport(
        _ identity: CustomCertificateImportIdentity,
        kind: CustomCertificateKind,
        hostPattern: String?,
        manager: CustomCertificateManager
    )
        throws -> CustomCertificateMetadata
    {
        switch kind {
        case .root:
            try manager.importRoot(
                displayName: identity.displayName,
                certificatePEM: identity.certificatePEM,
                privateKeyPEM: identity.privateKeyPEM
            )
        case .server:
            try manager.importServerIdentity(
                hostPattern: hostPattern ?? "",
                displayName: identity.displayName,
                certificatePEM: identity.certificatePEM,
                privateKeyPEM: identity.privateKeyPEM
            )
        case .client:
            try manager.importClientIdentity(
                hostPattern: hostPattern ?? "",
                displayName: identity.displayName,
                certificatePEM: identity.certificatePEM,
                privateKeyPEM: identity.privateKeyPEM
            )
        }
    }

    nonisolated private static func readBoundedData(from url: URL) throws -> Data {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > 16 * 1_024 * 1_024 {
            throw CustomCertificateFileError.fileTooLarge
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 16 * 1_024 * 1_024 else {
            throw CustomCertificateFileError.fileTooLarge
        }
        return data
    }

    private func runImport(
        kind: CustomCertificateKind,
        rawHost: String?,
        _ work: @escaping @Sendable (CustomCertificateManager, String?) throws -> CustomCertificateMetadata
    )
        async
    {
        guard !isImporting else {
            return
        }

        var normalizedHost: String?
        if kind != .root {
            let raw = rawHost ?? ""
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = String(localized: "Enter a host pattern for this certificate before importing.", bundle: RockxyLocalization.bundle)
                return
            }
            if let message = SSLHostPatternValidation.message(for: raw) {
                errorMessage = message
                return
            }
            normalizedHost = normalizedHostPattern(raw)
        }

        isImporting = true
        importGeneration += 1
        let generation = importGeneration
        let modeAtStart = mode
        statusMessage = nil
        let manager = self.manager
        let capturedHost = normalizedHost
        do {
            let metadata = try await Task.detached(priority: .userInitiated) {
                try work(manager, capturedHost)
            }.value
            isImporting = false
            // Always reload authoritative storage after a completed mutation. Only
            // move selection/mode when this is still the newest visible intent.
            reload()
            if metadata.kind == .root {
                await refreshDefaultRoot()
            }
            if generation == importGeneration, mode == modeAtStart {
                mode = Self.mode(for: metadata.kind)
                select(imported: metadata)
                statusMessage = String(localized: "Imported \(metadata.displayName).", bundle: RockxyLocalization.bundle)
                statusTone = .success
            }
        } catch {
            isImporting = false
            if generation == importGeneration {
                errorMessage = error.localizedDescription
                statusMessage = String(localized: "No certificate was imported.", bundle: RockxyLocalization.bundle)
                statusTone = .error
            }
        }
    }

    private func select(imported metadata: CustomCertificateMetadata) {
        switch metadata.kind {
        case .root:
            break
        case .server:
            selectedServerID = metadata.id
        case .client:
            selectedClientID = metadata.id
        }
    }

    private func deleteCertificate(id: UUID) async throws {
        let listMode: Mode? = serverEntries.contains { $0.id == id }
            ? .server
            : clientEntries.contains { $0.id == id } ? .client : nil
        let before = listMode.map { entries(for: $0) } ?? []
        let removedIndex = before.firstIndex { $0.id == id }

        let manager = self.manager
        try await Task.detached(priority: .userInitiated) {
            try manager.delete(id: id)
        }.value
        reload()

        if let listMode {
            let after = entries(for: listMode)
            let fallback: UUID? = if let removedIndex, !after.isEmpty {
                after[min(removedIndex, after.count - 1)].id
            } else {
                nil
            }
            setSelectedID(fallback, for: listMode)
        }
        reconcileSelection()
    }

    private func entries(for mode: Mode) -> [CustomCertificateMetadata] {
        switch mode {
        case .root:
            rootEntries
        case .server:
            serverEntries
        case .client:
            clientEntries
        }
    }

    private func setSelectedID(_ id: UUID?, for mode: Mode) {
        switch mode {
        case .root:
            break
        case .server:
            selectedServerID = id
        case .client:
            selectedClientID = id
        }
    }

    private func revertRootRequest(for entry: CustomCertificateMetadata) -> DeletionRequest {
        DeletionRequest(
            target: .revertRoot,
            title: String(localized: "Revert to Default Root Certificate?", bundle: RockxyLocalization.bundle),
            message: String(
                localized: """
                Rockxy will remove the custom root certificate “\(entry.displayName)” and resume signing \
                intercepted TLS connections with its generated root. Existing custom server and client \
                certificates are kept.
                """, bundle: RockxyLocalization.bundle
            ),
            confirmLabel: String(localized: "Revert", bundle: RockxyLocalization.bundle)
        )
    }

    private func certificateDeletionRequest(
        for entry: CustomCertificateMetadata,
        role: String
    )
        -> DeletionRequest
    {
        let hostClause = entry.hostPattern.map { String(localized: " for the host pattern \($0)", bundle: RockxyLocalization.bundle) } ?? ""
        return DeletionRequest(
            target: .certificate(entry.id),
            title: String(localized: "Delete Certificate?", bundle: RockxyLocalization.bundle),
            message: String(
                localized: """
                Rockxy will remove the custom \(role) certificate “\(entry.displayName)”\(hostClause) and \
                delete its private key from the Keychain. This cannot be undone.
                """, bundle: RockxyLocalization.bundle
            ),
            confirmLabel: String(localized: "Delete", bundle: RockxyLocalization.bundle)
        )
    }
}
