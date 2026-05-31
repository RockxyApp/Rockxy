import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - CustomCertificatesView

struct CustomCertificatesView: View {
    @State private var selectedTab = Tab.root
    @State private var rootEntries: [CustomCertificateMetadata] = []
    @State private var serverEntries: [CustomCertificateMetadata] = []
    @State private var clientEntries: [CustomCertificateMetadata] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Picker(String(localized: "Certificate Type"), selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 560)
            .padding(.top, 20)

            content
                .padding(28)

            Spacer(minLength: 0)
            bottomBar
        }
        .frame(minWidth: 900, minHeight: 540)
        .onAppear(perform: reload)
        .alert(String(localized: "Custom Certificate Failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "certificate")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "Custom Certificates"))
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .root:
            RootCertificateTab(entries: rootEntries)
        case .server:
            CertificateListTab(
                title: String(localized: "Config Server Certificates used when establishing SSL connections to clients"),
                subtitle: String(localized: "Suitable for apps that use certificate pinning."),
                entries: serverEntries,
                firstColumnTitle: String(localized: "Host"),
                emptyMessage: String(localized: "No custom server certificates have been imported.")
            )
        case .client:
            CertificateListTab(
                title: String(localized: "Config Client Certificates used when establishing SSL connections to selected servers"),
                subtitle: String(localized: "Suitable for upstream services that require mutual TLS."),
                entries: clientEntries,
                firstColumnTitle: String(localized: "Host"),
                emptyMessage: String(localized: "No client certificates have been imported.")
            )
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(selectedTab == .root ? String(localized: "Revert") : String(localized: "Delete")) {
                deleteSelectedKind()
            }
                .buttonStyle(.bordered)
                .disabled(currentEntries.isEmpty)

            Button(String(localized: "How to generate self-signed certificates")) {
                if let helpURL = URL(string: "https://docs.rockxy.io/troubleshooting/certificates-and-https-issues") {
                    NSWorkspace.shared.open(helpURL)
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            if let helpURL = URL(string: "https://docs.rockxy.io/troubleshooting/certificates-and-https-issues") {
                HelpLink(destination: helpURL)
            }

            Button(String(localized: "Preview")) {}
                .buttonStyle(.bordered)
                .disabled(true)

            Menu {
                Button(String(localized: "Root Certificate…")) {
                    importCertificate(kind: .root)
                }
                Button(String(localized: "Server Certificate…")) {
                    importCertificate(kind: .server)
                }
                Button(String(localized: "Client Certificate…")) {
                    importCertificate(kind: .client)
                }
            } label: {
                Label(String(localized: "Import"), systemImage: "chevron.down")
            }
            .menuStyle(.button)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    private var currentEntries: [CustomCertificateMetadata] {
        switch selectedTab {
        case .root:
            rootEntries
        case .server:
            serverEntries
        case .client:
            clientEntries
        }
    }

    private func reload() {
        rootEntries = CustomCertificateManager.shared.metadata(kind: .root)
        serverEntries = CustomCertificateManager.shared.metadata(kind: .server)
        clientEntries = CustomCertificateManager.shared.metadata(kind: .client)
    }

    private func deleteSelectedKind() {
        do {
            try CustomCertificateManager.shared.deleteAll(kind: selectedTab.kind)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importCertificate(kind: CustomCertificateKind) {
        do {
            guard let certificateURL = chooseFile(title: String(localized: "Choose Certificate PEM")),
                  let privateKeyURL = chooseFile(title: String(localized: "Choose Private Key PEM")) else {
                return
            }
            let certificatePEM = try String(contentsOf: certificateURL, encoding: .utf8)
            let privateKeyPEM = try String(contentsOf: privateKeyURL, encoding: .utf8)
            let displayName = certificateURL.deletingPathExtension().lastPathComponent

            switch kind {
            case .root:
                try CustomCertificateManager.shared.importRoot(
                    displayName: displayName,
                    certificatePEM: certificatePEM,
                    privateKeyPEM: privateKeyPEM
                )
                selectedTab = .root
            case .server:
                guard let hostPattern = promptHostPattern(
                    title: String(localized: "Server Certificate Host"),
                    message: String(localized: "Enter the host or wildcard pattern this server certificate should match.")
                ) else {
                    return
                }
                try CustomCertificateManager.shared.importServerIdentity(
                    hostPattern: hostPattern,
                    displayName: displayName,
                    certificatePEM: certificatePEM,
                    privateKeyPEM: privateKeyPEM
                )
                selectedTab = .server
            case .client:
                guard let hostPattern = promptHostPattern(
                    title: String(localized: "Client Certificate Host"),
                    message: String(localized: "Enter the upstream host or wildcard pattern that should receive this client identity.")
                ) else {
                    return
                }
                try CustomCertificateManager.shared.importClientIdentity(
                    hostPattern: hostPattern,
                    displayName: displayName,
                    certificatePEM: certificatePEM,
                    privateKeyPEM: privateKeyPEM
                )
                selectedTab = .client
            }
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseFile(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "pem") ?? .data]
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func promptHostPattern(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "api.example.com or *.example.com"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private enum Tab: CaseIterable, Identifiable {
        case root
        case server
        case client

        var id: Self { self }

        var title: String {
            switch self {
            case .root:
                String(localized: "Root Certificate")
            case .server:
                String(localized: "Server Certificates")
            case .client:
                String(localized: "Client Certificates")
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
}

// MARK: - RootCertificateTab

private struct RootCertificateTab: View {
    let entries: [CustomCertificateMetadata]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rootTitle)
                    .font(.title3)
                Text(String(localized: "This certificate is used for generating proxy certificates during SSL handshakes to clients and servers."))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                Image(systemName: "certificate.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.yellow)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entries.last?.displayName ?? String(localized: "Rockxy Default Root Certificate"))
                        .font(.headline)
                    if let entry = entries.last {
                        Text(validityText(for: entry))
                            .foregroundStyle(.secondary)
                        Label(String(localized: "Custom Root Active"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text(String(localized: "No custom root has been imported. Rockxy will use its default root CA."))
                            .foregroundStyle(.secondary)
                        Label(String(localized: "Default Root Active"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
            }
            .padding(18)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rootTitle: String {
        if entries.isEmpty {
            String(localized: "Rockxy is using the Default Rockxy Root Certificate")
        } else {
            String(localized: "Rockxy is using a Custom Root Certificate")
        }
    }

    private func validityText(for entry: CustomCertificateMetadata) -> String {
        let before = entry.notValidBefore?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Unknown")
        let after = entry.notValidAfter?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Unknown")
        return String(localized: "Valid from \(before) to \(after)")
    }
}

// MARK: - CertificateListTab

private struct CertificateListTab: View {
    let title: String
    let subtitle: String
    let entries: [CustomCertificateMetadata]
    let firstColumnTitle: String
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Table(entries) {
                TableColumn(firstColumnTitle) { entry in
                    Text(entry.hostPattern ?? "—")
                }
                TableColumn(String(localized: "Certificates")) { entry in
                    Text(entry.displayName)
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(emptyMessage, systemImage: "certificate")
                }
            }
            .frame(minHeight: 280)
        }
    }
}
