import AppKit
import Security
import SecurityInterface
import SwiftASN1
import SwiftUI
import UniformTypeIdentifiers
import X509

// MARK: - CustomCertificatesView

struct CustomCertificatesView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            Divider()
            content
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: min(900, max(720, toolMetrics.bodyFontSize * 18 + 486)),
            minHeight: min(680, max(520, toolMetrics.bodyFontSize * 8 + 420))
        )
        .task {
            await viewModel.refreshDefaultRoot()
        }
        .onChange(of: viewModel.mode) { _, newMode in
            if newMode == .root {
                Task { await viewModel.refreshDefaultRoot() }
            }
        }
        .onChange(of: viewModel.serverEntries.map(\.id)) { _, _ in
            viewModel.reconcileSelection()
        }
        .onChange(of: viewModel.clientEntries.map(\.id)) { _, _ in
            viewModel.reconcileSelection()
        }
        .alert(
            String(localized: "Custom Certificate Failed", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            viewModel.pendingDeletion?.title ?? "",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: {
                    if !$0 {
                        viewModel.pendingDeletion = nil
                    }
                }
            ),
            presenting: viewModel.pendingDeletion
        ) { request in
            Button(request.confirmLabel, role: .destructive) {
                confirmDeletion()
            }
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {
                viewModel.pendingDeletion = nil
            }
        } message: { request in
            Text(request.message)
        }
        .onDeleteCommand {
            guard !viewModel.isBusy else {
                return
            }
            viewModel.requestPrimaryDeletion()
        }
    }

    // MARK: Private

    private struct HostSelection {
        let value: String?
    }

    private static let helpURL = URL(string: "https://docs.rockxy.io/features/custom-certificates")

    @State private var viewModel = CustomCertificatesViewModel()
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var rootDetailLabelWidth: CGFloat {
        min(220, max(toolMetrics.formLabelWidth, toolMetrics.bodyFontSize * 7.2))
    }

    private var rootStatusSymbol: String {
        switch viewModel.rootStatus {
        case .customVerifying:
            "arrow.triangle.2.circlepath"
        case .customActive:
            "checkmark.seal.fill"
        case .customUnavailable:
            "xmark.shield.fill"
        case .installedTrusted:
            "checkmark.shield.fill"
        case .installedNotTrusted:
            "exclamationmark.shield.fill"
        case .generated:
            "shield.lefthalf.filled"
        case .unavailable:
            "xmark.shield"
        }
    }

    private var rootStatusColor: Color {
        switch viewModel.rootStatus {
        case .customVerifying:
            .secondary
        case .customActive,
             .installedTrusted:
            .green
        case .customUnavailable:
            .red
        case .installedNotTrusted:
            .orange
        case .generated,
             .unavailable:
            .secondary
        }
    }

    private var statusSymbol: String {
        switch viewModel.statusTone {
        case .neutral:
            "info.circle"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch viewModel.statusTone {
        case .neutral:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }

    private var modePicker: some View {
        HStack {
            Spacer(minLength: 0)
            Picker(
                String(localized: "Certificate Type", bundle: RockxyLocalization.bundle),
                selection: $viewModel.mode
            ) {
                ForEach(CustomCertificatesViewModel.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: min(560, max(420, toolMetrics.bodyFontSize * 18)))
            .disabled(viewModel.isBusy)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    @ViewBuilder private var content: some View {
        switch viewModel.mode {
        case .root:
            rootContent
        case .server:
            listContent(
                entries: viewModel.serverEntries,
                selection: $viewModel.selectedServerID,
                role: .server
            )
        case .client:
            listContent(
                entries: viewModel.clientEntries,
                selection: $viewModel.selectedClientID,
                role: .client
            )
        }
    }

    // MARK: - Root

    private var rootContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                rootSummaryCard
                if let certificate = viewModel.previewItem {
                    rootDetails(certificate)
                } else if viewModel.isLoadingDefaultRoot {
                    loadingRow
                } else if viewModel.rootStatus == .customUnavailable {
                    Label(
                        String(
                            localized:
                            "Re-import this custom root and private key, or revert to Rockxy's default root certificate.",
                            bundle: RockxyLocalization.bundle
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                } else if let rootLoadErrorMessage = viewModel.rootLoadErrorMessage {
                    Label(rootLoadErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.orange)
                } else {
                    certificateEmptyState(
                        title: String(localized: "No Root Certificate", bundle: RockxyLocalization.bundle),
                        systemImage: "shield.slash",
                        description: String(
                            localized:
                            "Create and trust Rockxy's root certificate from the Mac Setup Guide before intercepting HTTPS.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: toolMetrics.tableRowHeight * 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rootSummaryCard: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: toolMetrics.compactIconFontSize + 5))
                .foregroundStyle(viewModel.hasCustomRoot ? Color.accentColor : Color.secondary)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.rootTitle)
                    .font(toolMetrics.font(weight: .medium))
                    .textSelection(.enabled)
                Text(viewModel.rootSubtitle)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(viewModel.rootStatusText, systemImage: rootStatusSymbol)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(rootStatusColor)
            }
            Spacer(minLength: 0)
        }
        .padding(toolMetrics.controlSpacing + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            ProgressView().controlSize(.small)
            Text(String(localized: "Loading certificate details…", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            importButtons

            Button(viewModel.primaryDestructiveTitle, role: .destructive) {
                viewModel.requestPrimaryDeletion()
            }
            .rockxyGlassButtonStyle()
            .disabled(!viewModel.canPerformPrimaryDestructive || viewModel.isBusy)

            if viewModel.isBusy {
                ProgressView().controlSize(.small)
                Text(viewModel
                    .isImporting ? String(localized: "Importing…", bundle: RockxyLocalization.bundle) : String(
                        localized: "Deleting…",
                        bundle: RockxyLocalization.bundle
                    ))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            } else if let statusMessage = viewModel.statusMessage {
                Label(statusMessage, systemImage: statusSymbol)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }

            Spacer()

            Button(String(localized: "Preview", bundle: RockxyLocalization.bundle)) {
                presentPreview()
            }
            .rockxyGlassButtonStyle()
            .disabled(!viewModel.canPreview || viewModel.isBusy)

            if let helpURL = Self.helpURL {
                HelpLink(destination: helpURL)
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    /// One or two import actions are direct buttons rather than a pull-down: a menu holding a
    /// single item only adds a step, and the HIG reserves pull-downs for three or more commands.
    @ViewBuilder
    private var importButtons: some View {
        if viewModel.mode != .root {
            Button(String(localized: "Import PEM / DER…", bundle: RockxyLocalization.bundle)) {
                importPEMOrDER(kind: viewModel.mode.kind)
            }
            .rockxyGlassButtonStyle()
            .disabled(viewModel.isBusy)
        }
        Button(String(localized: "Import P12…", bundle: RockxyLocalization.bundle)) {
            importPKCS12(kind: viewModel.mode.kind)
        }
        .rockxyGlassButtonStyle()
        .disabled(viewModel.isBusy)
    }

    private func rootDetails(_ certificate: CertificatePreviewItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            detailRow(String(localized: "Common Name", bundle: RockxyLocalization.bundle), certificate.commonName)
            detailRow(
                String(localized: "Not Valid Before", bundle: RockxyLocalization.bundle),
                certificate.notValidBefore.map(Self.format)
            )
            detailRow(
                String(localized: "Not Valid After", bundle: RockxyLocalization.bundle),
                certificate.notValidAfter.map(Self.format)
            )
            detailRow(
                String(localized: "SHA-256", bundle: RockxyLocalization.bundle),
                certificate.fingerprintSHA256,
                monospaced: true
            )
            detailRow(String(localized: "Subject", bundle: RockxyLocalization.bundle), certificate.subjectSummary)
            detailRow(String(localized: "Issuer", bundle: RockxyLocalization.bundle), certificate.issuerSummary)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?, monospaced: Bool = false) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: toolMetrics.controlSpacing) {
                Text(label)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: rootDetailLabelWidth, alignment: .trailing)
                Text(value)
                    .font(toolMetrics.secondaryFont(monospaced: monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(monospaced ? 1 : 2)
                    .truncationMode(monospaced ? .middle : .tail)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Server / Client Lists

    private func listContent(
        entries: [CustomCertificateMetadata],
        selection: Binding<UUID?>,
        role: CustomCertificateKind
    )
        -> some View
    {
        Table(entries, selection: selection) {
            TableColumn(String(localized: "Host", bundle: RockxyLocalization.bundle)) { entry in
                Text(entry.hostPattern ?? "—")
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.hostPattern ?? "")
            }
            .width(min: 150, ideal: 220)

            TableColumn(String(localized: "Certificate", bundle: RockxyLocalization.bundle)) { entry in
                Text(entry.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.displayName)
            }
            .width(min: 150, ideal: 240)

            TableColumn(String(localized: "Expires", bundle: RockxyLocalization.bundle)) { entry in
                Text(entry.notValidAfter.map(Self.format) ?? String(
                    localized: "Unknown",
                    bundle: RockxyLocalization.bundle
                ))
                .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 170)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            listContextMenu(ids: ids)
        }
        .overlay {
            if entries.isEmpty {
                emptyState(for: role)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    @ViewBuilder
    private func listContextMenu(ids: Set<UUID>) -> some View {
        Button(String(localized: "Preview", bundle: RockxyLocalization.bundle)) {
            if let id = ids.first {
                viewModel.select(id: id)
                presentPreview()
            }
        }
        .disabled(ids.isEmpty)

        Divider()

        Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
            if let id = ids.first {
                viewModel.requestDeletion(certificateID: id)
            }
        }
        .disabled(ids.isEmpty)
    }

    private func emptyState(for role: CustomCertificateKind) -> some View {
        switch role {
        case .server:
            certificateEmptyState(
                title: String(localized: "No Server Certificates", bundle: RockxyLocalization.bundle),
                systemImage: "lock.doc",
                description: String(
                    localized: "Import a certificate and private key to present a pinned server identity for matching hosts.",
                    bundle: RockxyLocalization.bundle
                )
            )
        default:
            certificateEmptyState(
                title: String(localized: "No Client Certificates", bundle: RockxyLocalization.bundle),
                systemImage: "lock.doc",
                description: String(
                    localized: "Import a certificate and private key to answer mutual-TLS challenges from matching hosts.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    private func certificateEmptyState(
        title: String,
        systemImage: String,
        description: String
    )
        -> some View
    {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: max(22, toolMetrics.emptyStateFontSize + 8)))
                .foregroundStyle(.secondary)
            Text(title)
                .font(toolMetrics.font(weight: .medium))
            Text(description)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(toolMetrics.contentHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    nonisolated private static func format(_ date: Date) -> String {
        TimestampFormatter.string(date, date: .abbreviated, time: .shortened)
    }

    private func confirmDeletion() {
        let wasRoot = viewModel.mode == .root
        Task {
            await viewModel.confirmPendingDeletion()
            if wasRoot {
                await viewModel.refreshDefaultRoot()
            }
        }
    }

    private func presentPreview() {
        guard let item = viewModel.previewItem else {
            return
        }
        let panel = SFCertificatePanel.shared()
        panel?.runModal(for: item.secTrust, showGroup: true)
    }

    private func importPEMOrDER(kind: CustomCertificateKind) {
        guard let certificateURL = chooseFile(
            title: String(localized: "Choose Certificate PEM or DER", bundle: RockxyLocalization.bundle),
            allowedContentTypes: CertificateImportFileType.certificateTypes
        ),
            let privateKeyURL = chooseFile(
                title: String(localized: "Choose Private Key PEM or DER", bundle: RockxyLocalization.bundle),
                allowedContentTypes: CertificateImportFileType.privateKeyTypes
            ) else
        {
            return
        }
        guard let hostPattern = collectHostIfNeeded(kind: kind) else {
            return
        }
        let displayName = certificateURL.deletingPathExtension().lastPathComponent
        Task {
            await viewModel.importCertificateAndKey(
                certificateURL: certificateURL,
                privateKeyURL: privateKeyURL,
                displayName: displayName,
                kind: kind,
                hostPattern: hostPattern.value
            )
        }
    }

    private func importPKCS12(kind: CustomCertificateKind) {
        guard let pkcs12URL = chooseFile(
            title: String(localized: "Choose P12 Certificate", bundle: RockxyLocalization.bundle),
            allowedContentTypes: CertificateImportFileType.pkcs12Types
        ),
            let passphrase = promptPKCS12Passphrase() else
        {
            return
        }
        guard let hostPattern = collectHostIfNeeded(kind: kind) else {
            return
        }
        let displayName = pkcs12URL.deletingPathExtension().lastPathComponent
        Task {
            await viewModel.importPKCS12(
                url: pkcs12URL,
                displayName: displayName,
                passphrase: passphrase,
                kind: kind,
                hostPattern: hostPattern.value
            )
        }
    }

    /// Collects a host pattern for server / client imports. Returns `nil` when the user
    /// cancels the prompt so the import is aborted before any Keychain / metadata write.
    private func collectHostIfNeeded(kind: CustomCertificateKind) -> HostSelection? {
        switch kind {
        case .root:
            HostSelection(value: nil)
        case .server:
            promptHostPattern(
                title: String(localized: "Server Certificate Host", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Enter the host or wildcard pattern this server certificate should match.",
                    bundle: RockxyLocalization.bundle
                )
            ).map { HostSelection(value: $0) }
        case .client:
            promptHostPattern(
                title: String(localized: "Client Certificate Host", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Enter the upstream host or wildcard pattern that should receive this client identity.",
                    bundle: RockxyLocalization.bundle
                )
            ).map { HostSelection(value: $0) }
        }
    }

    private func chooseFile(title: String, allowedContentTypes: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedContentTypes
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func promptPKCS12Passphrase() -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "P12 Password", bundle: RockxyLocalization.bundle)
        alert
            .informativeText =
            String(
                localized: "Enter the password for this P12 file. Leave it empty if the file has no password.",
                bundle: RockxyLocalization.bundle
            )
        alert.addButton(withTitle: String(localized: "Import", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = String(localized: "Password", bundle: RockxyLocalization.bundle)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return field.stringValue
    }

    private func promptHostPattern(title: String, message: String) -> String? {
        var validationMessage: String?
        while true {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = validationMessage ?? message
            alert.alertStyle = validationMessage == nil ? .informational : .warning
            alert.addButton(withTitle: String(localized: "Continue", bundle: RockxyLocalization.bundle))
            alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            field.placeholderString = "api.example.com or *.example.com"
            alert.accessoryView = field

            guard alert.runModal() == .alertFirstButtonReturn else {
                return nil
            }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                validationMessage = String(localized: "Enter a host pattern.", bundle: RockxyLocalization.bundle)
                continue
            }
            if let message = viewModel.hostValidationMessage(for: value) {
                validationMessage = message
                continue
            }
            return viewModel.normalizedHostPattern(value)
        }
    }
}

// MARK: - CertificateImportFileType

private enum CertificateImportFileType {
    // MARK: Internal

    static let certificateTypes = extensions(["pem", "der", "cer", "crt"])
    static let privateKeyTypes = extensions(["pem", "key", "der"])
    static let pkcs12Types = extensions(["p12", "pfx"])

    // MARK: Private

    private static func extensions(_ values: [String]) -> [UTType] {
        values.map { UTType(filenameExtension: $0) ?? .data }
    }
}

// MARK: - CertificatePreviewItem

struct CertificatePreviewItem {
    // MARK: Lifecycle

    init(metadata: CustomCertificateMetadata) throws {
        try self.init(
            certificate: Certificate(pemEncoded: metadata.certificatePEM),
            displayName: metadata.displayName,
            fingerprintSHA256: metadata.fingerprintSHA256
        )
    }

    init(
        certificate: Certificate,
        displayName: String?,
        fingerprintSHA256: String?
    )
        throws
    {
        self.displayName = displayName ?? Self.commonName(from: certificate.subject) ?? String(
            localized: "Certificate",
            bundle: RockxyLocalization.bundle
        )
        notValidBefore = certificate.notValidBefore
        notValidAfter = certificate.notValidAfter
        self.fingerprintSHA256 = fingerprintSHA256 ?? Self.fingerprint(certificate)
        commonName = Self.commonName(from: certificate.subject)
        subjectSummary = Self.summary(from: certificate.subject)
        issuerSummary = Self.summary(from: certificate.issuer)
        secCertificate = try Self.secCertificate(from: certificate)
        secTrust = try Self.secTrust(for: secCertificate)
    }

    // MARK: Internal

    let displayName: String
    let notValidBefore: Date?
    let notValidAfter: Date?
    let fingerprintSHA256: String?
    let commonName: String?
    let subjectSummary: String
    let issuerSummary: String
    let secCertificate: SecCertificate
    let secTrust: SecTrust

    // MARK: Private

    private static func secCertificate(from certificate: Certificate) throws -> SecCertificate {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        let data = Data(serializer.serializedBytes)
        guard let secCertificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw CustomCertificatePreviewError.invalidCertificate
        }
        return secCertificate
    }

    private static func secTrust(for certificate: SecCertificate) throws -> SecTrust {
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
        guard status == errSecSuccess, let trust else {
            throw CustomCertificatePreviewError.invalidCertificate
        }
        return trust
    }

    private static func fingerprint(_ certificate: Certificate) -> String? {
        var serializer = DER.Serializer()
        guard (try? certificate.serialize(into: &serializer)) != nil else {
            return nil
        }
        return KeychainHelper.computeFingerprintSHA256(Data(serializer.serializedBytes))
    }

    private static func commonName(from name: DistinguishedName) -> String? {
        for relativeDistinguishedName in name {
            for attribute in relativeDistinguishedName
                where attribute.type == ASN1ObjectIdentifier.NameAttributes.commonName
            {
                return String(describing: attribute.value)
            }
        }
        return nil
    }

    private static func summary(from name: DistinguishedName) -> String {
        let values = rows(from: name).map(\.value)
        return values.isEmpty ? String(describing: name) : values.joined(separator: ", ")
    }

    private static func rows(from name: DistinguishedName) -> [CertificateNameRow] {
        name.flatMap { relativeDistinguishedName in
            relativeDistinguishedName.map { attribute in
                CertificateNameRow(label: label(for: attribute.type), value: String(describing: attribute.value))
            }
        }
    }

    private static func label(for oid: ASN1ObjectIdentifier) -> String {
        switch oid {
        case ASN1ObjectIdentifier.NameAttributes.commonName:
            String(localized: "Common Name", bundle: RockxyLocalization.bundle)
        case ASN1ObjectIdentifier.NameAttributes.countryName:
            String(localized: "Country or Region", bundle: RockxyLocalization.bundle)
        case ASN1ObjectIdentifier.NameAttributes.localityName:
            String(localized: "Locality", bundle: RockxyLocalization.bundle)
        case ASN1ObjectIdentifier.NameAttributes.organizationName:
            String(localized: "Organization", bundle: RockxyLocalization.bundle)
        case ASN1ObjectIdentifier.NameAttributes.organizationalUnitName:
            String(localized: "Organizational Unit", bundle: RockxyLocalization.bundle)
        case ASN1ObjectIdentifier.NameAttributes.stateOrProvinceName:
            String(localized: "State/Province", bundle: RockxyLocalization.bundle)
        default:
            String(describing: oid)
        }
    }
}

// MARK: - CertificateNameRow

private struct CertificateNameRow: Identifiable {
    let label: String
    let value: String

    var id: String {
        "\(label)-\(value)"
    }
}

// MARK: - CustomCertificatePreviewError

private enum CustomCertificatePreviewError: LocalizedError {
    case invalidCertificate

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            String(localized: "The certificate could not be converted for preview.", bundle: RockxyLocalization.bundle)
        }
    }
}
