import SwiftUI
import UniformTypeIdentifiers

// Renders the bypass proxy list for the settings experience.

// MARK: - BypassProxyListView

/// Window for managing domains that bypass Rockxy's proxy.
/// Traffic to these hosts goes directly to the network without interception.
/// Mirrors the layout and interaction patterns of `SSLProxyingListView`.
struct BypassProxyListView: View {
    // MARK: Internal

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            tableSection
            Divider()
            inputSection
            Divider()
            footerSection
        }
        .font(toolMetrics.font())
        .frame(width: toolMetrics.fieldWidth(520), height: 480)
        .onAppear {
            manager = BypassProxyManager.shared
        }
    }

    // MARK: Private

    @State private var manager: BypassProxyManager?
    @State private var newDomain: String = ""
    @State private var selectedDomainIDs: Set<UUID> = []
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportData: Data?
    @State private var validationError: String?
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Bypass Proxy List"))
                .font(toolMetrics.font(weight: .semibold))
            Text(
                String(
                    localized: "These domains never go through Rockxy. Use this for noisy traffic, localhost exclusions, or SSL-pinned services."
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tableSection: some View {
        Group {
            if let manager {
                if manager.domains.isEmpty {
                    ContentUnavailableView {
                        Label(
                            String(localized: "No Bypass Domains"),
                            systemImage: "arrow.uturn.right"
                        )
                    } description: {
                        Text(
                            String(
                                localized: "Add domains below or use presets to get started.\nExamples: localhost, *.local, 127.0.0.1"
                            )
                        )
                    }
                } else {
                    Table(manager.domains, selection: $selectedDomainIDs) {
                        TableColumn(String(localized: "Domain")) { domain in
                            Text(domain.domain)
                                .font(toolMetrics.font(monospaced: true))
                        }
                        .width(min: 200)
                        TableColumn(String(localized: "Enabled")) { domain in
                            Toggle(isOn: Binding(
                                get: { domain.isEnabled },
                                set: { _ in manager.toggleDomain(id: domain.id) }
                            )) {
                                EmptyView()
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .width(60)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(
                    String(localized: "Domain (e.g. localhost, *.local)"),
                    text: $newDomain
                )
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .frame(minHeight: toolMetrics.formControlHeight)
                .onSubmit { addDomain() }
                .onChange(of: newDomain) {
                    validationError = nil
                }

                Button(String(localized: "Add")) {
                    addDomain()
                }
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                Button(role: .destructive) {
                    manager?.removeDomains(ids: selectedDomainIDs)
                    selectedDomainIDs.removeAll()
                } label: {
                    Label(String(localized: "Remove"), systemImage: "minus")
                }
                .disabled(selectedDomainIDs.isEmpty)
            }

            if let validationError {
                Text(validationError)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var footerSection: some View {
        HStack(spacing: 8) {
            Menu(String(localized: "Presets")) {
                Button(String(localized: "Add Default Bypass Domains")) {
                    manager?.addPresets()
                }
            }

            Button(String(localized: "Import…")) {
                showingImporter = true
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }

            Button(String(localized: "Export…")) {
                exportData = manager?.exportDomains()
                showingExporter = true
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: BypassJSONFileDocument(data: exportData ?? Data()),
                contentType: .json,
                defaultFilename: "bypass-proxy-domains.json"
            ) { _ in }

            Spacer()

            if let manager {
                let activeCount = manager.domains.filter(\.isEnabled).count
                if activeCount > 0 {
                    Text(String(localized: "\(activeCount) domain(s) active"))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                }
            }

            Button(String(localized: "Done")) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func addDomain() {
        let trimmed = newDomain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }

        if let manager, manager.domains.contains(where: { $0.domain.lowercased() == trimmed.lowercased() }) {
            validationError = String(localized: "This domain is already in the bypass list.")
            return
        }

        manager?.addDomain(trimmed)
        newDomain = ""
        validationError = nil
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            return
        }
        try? manager?.importDomains(from: data)
    }
}

// MARK: - BypassJSONFileDocument

/// Minimal FileDocument for JSON export via fileExporter.
private struct BypassJSONFileDocument: FileDocument {
    // MARK: Lifecycle

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    // MARK: Internal

    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
