import SwiftUI
import UniformTypeIdentifiers

// MARK: - ProtobufSchemaListWindowView

struct ProtobufSchemaListWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            schemaTable
            consoleSection
            footer
        }
        .font(toolMetrics.font())
        .frame(width: 1_000, height: 860)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            importSchema(result)
        }
        .onDeleteCommand {
            removeSelectedSchema()
        }
    }

    // MARK: Private

    @State private var schemaStore = ProtobufSchemaStore.shared
    @State private var selectedSchemaID: UUID?
    @State private var showImporter = false
    @State private var consoleLines: [String] = []
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Protobuf File Descriptor List"))
                .font(.system(size: max(17, toolMetrics.bodyFontSize + 4), weight: .medium))

            Text(String(localized: "List of *.proto files used to define the structure of protocol buffer data."))
                .font(.system(size: max(15, toolMetrics.bodyFontSize + 2)))
                .foregroundStyle(.secondary)

            Text(
                String(
                    localized: "Schema files are required for named, human-readable fields. Heuristic decoding does not require schema files."
                )
            )
            .font(.system(size: max(15, toolMetrics.bodyFontSize + 2)))
            .foregroundStyle(.secondary)

            if !schemaStore.canUploadSchema {
                PolicyLockNotice(
                    title: String(localized: "Schema upload unavailable"),
                    message: String(
                        localized: "The current app policy rejects schema uploads. Existing schema list controls remain visible for the future implementation path."
                    )
                )
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 26)
        .padding(.bottom, 18)
    }

    private var schemaTable: some View {
        ZStack {
            Table(schemaStore.schemas, selection: $selectedSchemaID) {
                TableColumn(String(localized: "Schema File Name")) { schema in
                    Text(schema.fileName)
                        .lineLimit(1)
                }
                TableColumn(String(localized: "Message Types")) { schema in
                    Text(schema.parsedMessageNames.isEmpty
                        ? String(localized: "Not parsed")
                        : schema.parsedMessageNames.joined(separator: ", "))
                        .foregroundStyle(schema.parsedMessageNames.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                }
                TableColumn(String(localized: "Default Mapping")) { schema in
                    Text(schema.defaultMessageType ?? schema.hostPattern)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                schemaContextMenu(ids: ids)
            }

            if schemaStore.schemas.isEmpty {
                Text(String(localized: "Click \"+\" or ⌘N to import Protobuf Schema (*.proto)"))
                    .font(.system(size: toolMetrics.emptyStateFontSize))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 350)
        .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .padding(.horizontal, 26)
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Protobuf Console Log"))
                .font(.system(size: max(17, toolMetrics.bodyFontSize + 4), weight: .medium))

            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    if consoleLines.isEmpty {
                        Text(String(localized: "Empty Console Log"))
                            .font(.system(size: toolMetrics.emptyStateFontSize))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 154)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(consoleLines, id: \.self) { line in
                                Text(line)
                                    .font(toolMetrics.font(monospaced: true))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(10)
                    }
                }
                .frame(height: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))

                Button {
                    consoleLines.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(8)
                .disabled(consoleLines.isEmpty)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            addRemoveControl

            Spacer()

            Button(String(localized: "How to get *.proto file?")) {
                appendConsole(
                    String(
                        localized: "Generate .proto files from your service definition or export descriptors from your build pipeline."
                    )
                )
            }

            Menu {
                Button(String(localized: "New…")) {
                    showImporter = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!schemaStore.canUploadSchema)

                Divider()

                Button(String(localized: "Delete"), role: .destructive) {
                    removeSelectedSchema()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selectedSchemaID == nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis.circle")
                    Image(systemName: "chevron.down")
                        .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
                }
            }
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                showImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize, height: toolMetrics.compactButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!schemaStore.canUploadSchema)
            .help(String(localized: "Import Protobuf Schema"))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 21)

            Button {
                removeSelectedSchema()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .foregroundStyle(selectedSchemaID == nil ? .tertiary : .primary)
                    .frame(width: toolMetrics.compactButtonSize, height: toolMetrics.compactButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(selectedSchemaID == nil)
            .help(String(localized: "Delete Protobuf Schema"))
        }
        .frame(height: toolMetrics.footerControlHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder
    private func schemaContextMenu(ids: Set<UUID>) -> some View {
        Button(String(localized: "New…")) {
            showImporter = true
        }
        .disabled(!schemaStore.canUploadSchema)

        Divider()

        Button(String(localized: "Delete"), role: .destructive) {
            if let id = ids.first {
                removeSchema(id: id)
            }
        }
        .disabled(ids.isEmpty)
    }

    private func importSchema(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                _ = try schemaStore.uploadSchema(
                    data: data,
                    fileName: url.lastPathComponent,
                    hostPattern: "*"
                )
                appendConsole(String(localized: "Imported \(url.lastPathComponent)."))
            } catch {
                appendConsole(error.localizedDescription)
            }
        case let .failure(error):
            appendConsole(error.localizedDescription)
        }
    }

    private func removeSelectedSchema() {
        guard let selectedSchemaID else {
            return
        }
        removeSchema(id: selectedSchemaID)
    }

    private func removeSchema(id: UUID) {
        do {
            try schemaStore.removeSchema(id: id)
            if selectedSchemaID == id {
                selectedSchemaID = nil
            }
            appendConsole(String(localized: "Removed Protobuf schema."))
        } catch {
            appendConsole(error.localizedDescription)
        }
    }

    private func appendConsole(_ line: String) {
        consoleLines.append(line)
    }
}
