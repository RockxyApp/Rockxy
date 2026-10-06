import SwiftUI
import UniformTypeIdentifiers

// MARK: - ProtobufSchemaListWindowView

struct ProtobufSchemaListWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ProtobufLocalOnlyNotice(message: Self.capabilityNotice)
            if !schemaStore.schemas.isEmpty, schemaStore.importAvailability != .available {
                Divider()
                availabilityNotice
            }
            Divider()
            schemaTable
            Divider()
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(760, toolMetrics.bodyFontSize * 24 + 432),
            minHeight: max(520, toolMetrics.bodyFontSize * 15 + 325)
        )
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            importSchema(result)
        }
        .confirmationDialog(
            String(localized: "Delete Schema?", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: {
                    if !$0 {
                        pendingDeletion = nil
                    }
                }
            ),
            presenting: pendingDeletion
        ) { schema in
            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                performDelete(schema)
            }
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {
                pendingDeletion = nil
            }
        } message: { schema in
            Text(deletionMessage(for: schema))
        }
    }

    // MARK: Private

    private enum ImportStatus: Equatable {
        case success(String)
        case failure(String)
    }

    private static var capabilityNotice: String {
        String(
            localized:
            """
            Schemas are stored locally on this Mac. Rockxy uses them to name fields in Protobuf bodies, \
            WebSocket frames, and gRPC messages that a mapping definition, a gRPC service, or your \
            Decode As choice points at.
            """, bundle: RockxyLocalization.bundle
        )
    }

    private static var allowedContentTypes: [UTType] {
        let extensions = ["proto"] + ProtobufDescriptorSetParser.fileExtensions.sorted()
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.plainText, .data] : types
    }

    @State private var schemaStore = ProtobufSchemaStore.shared
    @State private var mappingStore = ProtobufMappingRuleStore.shared
    @State private var selectedSchemaID: UUID?
    @State private var showImporter = false
    @State private var pendingDeletion: ProtobufSchemaDescriptor?
    @State private var importStatus: ImportStatus?
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var canImport: Bool {
        schemaStore.importAvailability.allowsImport
    }

    private var footerHint: String {
        let used = schemaStore.schemasUsed
        let count = used == 1
            ? String(localized: "1 schema", bundle: RockxyLocalization.bundle)
            : String(localized: "\(used) schemas", bundle: RockxyLocalization.bundle)
        if schemaStore.schemasLimit > 0 {
            return String(
                localized: "\(count) of \(schemaStore.schemasLimit) stored",
                bundle: RockxyLocalization.bundle
            )
        }
        return count
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var availabilityIcon: String {
        switch schemaStore.importAvailability {
        case .available:
            "checkmark.circle"
        case .policyUnavailable:
            "lock"
        case .limitReached:
            "tray.full"
        case .storageUnavailable:
            "exclamationmark.triangle.fill"
        }
    }

    private var availabilityColor: Color {
        schemaStore.importAvailability == .storageUnavailable ? .orange : .secondary
    }

    private var availabilityTitle: String {
        switch schemaStore.importAvailability {
        case .available:
            String(localized: "Local Import Available", bundle: RockxyLocalization.bundle)
        case .policyUnavailable:
            String(localized: "Local Import Unavailable", bundle: RockxyLocalization.bundle)
        case .limitReached:
            String(localized: "Schema Limit Reached", bundle: RockxyLocalization.bundle)
        case .storageUnavailable:
            String(localized: "Schema Storage Unavailable", bundle: RockxyLocalization.bundle)
        }
    }

    private var availabilityMessage: String {
        switch schemaStore.importAvailability {
        case .available:
            String(
                localized: "Import a .proto source file or a .desc descriptor set.",
                bundle: RockxyLocalization.bundle
            )
        case .policyUnavailable:
            String(
                localized: "This version of Rockxy does not allow new local schema imports. Existing files can still be removed.",
                bundle: RockxyLocalization.bundle
            )
        case let .limitReached(limit):
            String(
                localized: "This build stores up to \(limit) local schemas. Remove one before importing another.",
                bundle: RockxyLocalization.bundle
            )
        case .storageUnavailable:
            String(
                localized: "The stored schema list could not be read. Retry before changing local schema files.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Local Protobuf Schemas", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))
                Text(String(
                    localized: "Import .proto sources or .desc files from protoc --descriptor_set_out --include_imports.",
                    bundle: RockxyLocalization.bundle
                ))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var schemaTable: some View {
        Table(schemaStore.schemas, selection: $selectedSchemaID) {
            TableColumn(String(localized: "Schema File Name", bundle: RockxyLocalization.bundle)) { schema in
                Text(schema.fileName)
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(schema.fileName)
            }
            .width(min: 200, ideal: 300)

            TableColumn(String(localized: "Referenced By", bundle: RockxyLocalization.bundle)) { schema in
                let count = mappingStore.referenceCount(forSchema: schema.id)
                Text(String(AttributedString(
                    localized: "^[\(count) definition](inflect: true)",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters))
                    .foregroundStyle(count == 0 ? .secondary : .primary)
            }
            .width(min: 130, ideal: 160)

            TableColumn(String(localized: "Message Types", bundle: RockxyLocalization.bundle)) { schema in
                let names = schemaStore.messageNames(for: schema)
                Text(String(AttributedString(
                    localized: "^[\(names.count) type](inflect: true)",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters))
                    .foregroundStyle(names.isEmpty ? .orange : .primary)
                    .help(names.isEmpty
                        ? String(
                            localized: "This file no longer parses. Delete it and import it again.",
                            bundle: RockxyLocalization.bundle
                        )
                        : names.joined(separator: "\n"))
            }
            .width(min: 110, ideal: 130)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            schemaContextMenu(ids: ids)
        }
        .overlay {
            if schemaStore.schemas.isEmpty {
                emptyState
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

    @ViewBuilder private var emptyState: some View {
        switch schemaStore.importAvailability {
        case .available:
            ContentUnavailableView(
                String(localized: "No Local Schemas", bundle: RockxyLocalization.bundle),
                systemImage: "doc.badge.plus",
                description: Text(String(
                    localized: "Click \"+\" or press ⌘N to import a .proto or .desc file.",
                    bundle: RockxyLocalization.bundle
                ))
            )
        case .policyUnavailable:
            ContentUnavailableView(
                String(localized: "Schema Import Unavailable", bundle: RockxyLocalization.bundle),
                systemImage: "lock",
                description: Text(String(
                    localized: "Local schema import is unavailable in this version of Rockxy.",
                    bundle: RockxyLocalization.bundle
                ))
            )
        case let .limitReached(limit):
            ContentUnavailableView(
                String(localized: "Schema Limit Reached", bundle: RockxyLocalization.bundle),
                systemImage: "tray.full",
                description: Text(String(
                    localized: "This build stores up to \(limit) local schemas.",
                    bundle: RockxyLocalization.bundle
                ))
            )
        case .storageUnavailable:
            ContentUnavailableView {
                Label(
                    String(localized: "Schema Storage Unavailable", bundle: RockxyLocalization.bundle),
                    systemImage: "exclamationmark.triangle"
                )
            } description: {
                Text(String(
                    localized: "The stored schema list could not be read. Retry before changing local files.",
                    bundle: RockxyLocalization.bundle
                ))
            } actions: {
                Button(String(localized: "Retry", bundle: RockxyLocalization.bundle)) {
                    schemaStore.reload()
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
            HStack(spacing: toolMetrics.controlSpacing) {
                addRemoveControl
                Text(footerHint)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Spacer()
                moreMenu
            }
            if let importStatus {
                statusLabel(importStatus)
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                showImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .foregroundStyle(canImport ? .primary : .tertiary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!canImport)
            .help(String(localized: "Import Protobuf Schema", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Import local Protobuf schema", bundle: RockxyLocalization.bundle))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                requestDeleteSelected()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .foregroundStyle(selectedSchemaID == nil ? .tertiary : .primary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedSchemaID == nil)
            .help(String(localized: "Delete Protobuf Schema", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(
                localized: "Delete selected local Protobuf schema",
                bundle: RockxyLocalization.bundle
            ))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Import…", bundle: RockxyLocalization.bundle)) {
                showImporter = true
            }
            .disabled(!canImport)

            Divider()

            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                requestDeleteSelected()
            }
            .disabled(selectedSchemaID == nil)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More", bundle: RockxyLocalization.bundle))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .rockxyGlassButtonStyle()
        .fixedSize()
    }

    private var availabilityNotice: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            Image(systemName: availabilityIcon)
                .foregroundStyle(availabilityColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(availabilityTitle)
                    .font(toolMetrics.font(weight: .medium))
                Text(availabilityMessage)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if schemaStore.importAvailability == .storageUnavailable {
                Button(String(localized: "Retry", bundle: RockxyLocalization.bundle)) {
                    schemaStore.reload()
                }
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    private func statusLabel(_ status: ImportStatus) -> some View {
        let isSuccess: Bool
        let message: String
        switch status {
        case let .success(text):
            isSuccess = true
            message = text
        case let .failure(text):
            isSuccess = false
            message = text
        }
        return Label(message, systemImage: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(isSuccess ? Color.green : Color.red)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help(message)
    }

    @ViewBuilder
    private func schemaContextMenu(ids: Set<UUID>) -> some View {
        Button(String(localized: "Import…", bundle: RockxyLocalization.bundle)) {
            showImporter = true
        }
        .disabled(!canImport)

        Divider()

        Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
            if let id = ids.first {
                requestDelete(id: id)
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
                let data = try ProtobufSchemaSourceValidator.loadValidatedSource(
                    at: url,
                    fileName: url.lastPathComponent
                )
                let descriptor = try schemaStore.uploadSchema(
                    data: data,
                    fileName: url.lastPathComponent,
                    hostPattern: "*"
                )
                let typeCount = descriptor.parsedMessageNames.count
                importStatus = .success(String(AttributedString(
                    localized: "Imported \(descriptor.fileName) · ^[\(typeCount) message type](inflect: true)",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters))
            } catch {
                importStatus = .failure(error.localizedDescription)
            }
        case let .failure(error):
            importStatus = .failure(error.localizedDescription)
        }
    }

    private func requestDeleteSelected() {
        guard let selectedSchemaID,
              let schema = schemaStore.schemas.first(where: { $0.id == selectedSchemaID }) else
        {
            return
        }
        pendingDeletion = schema
    }

    private func requestDelete(id: UUID) {
        guard let schema = schemaStore.schemas.first(where: { $0.id == id }) else {
            return
        }
        selectedSchemaID = id
        pendingDeletion = schema
    }

    private func deletionMessage(for schema: ProtobufSchemaDescriptor) -> String {
        let references = mappingStore.referenceCount(forSchema: schema.id)
        guard references > 0 else {
            return String(
                localized: "This removes the stored \(schema.fileName) file from this Mac.",
                bundle: RockxyLocalization.bundle
            )
        }
        let mappingCount = references == 1
            ? String(localized: "1 mapping definition", bundle: RockxyLocalization.bundle)
            : String(localized: "\(references) mapping definitions", bundle: RockxyLocalization.bundle)
        return String(
            localized: "\(mappingCount) reference this schema. Deleting it clears their schema selection.",
            bundle: RockxyLocalization.bundle
        )
    }

    private func performDelete(_ schema: ProtobufSchemaDescriptor) {
        defer { pendingDeletion = nil }
        let rulesSnapshot = mappingStore.rules
        do {
            let detached = try mappingStore.detachSchema(id: schema.id)
            do {
                try schemaStore.removeSchema(id: schema.id)
            } catch {
                do {
                    try mappingStore.restoreRules(rulesSnapshot)
                } catch let restoreError {
                    importStatus = .failure(
                        String(
                            localized:
                            """
                            The schema was not deleted, but its mapping references could not be restored: \
                            \(restoreError.localizedDescription)
                            """, bundle: RockxyLocalization.bundle
                        )
                    )
                    return
                }
                throw error
            }
            if selectedSchemaID == schema.id {
                selectedSchemaID = nil
            }
            importStatus = .success(
                detached > 0
                    ? String(
                        localized: "Deleted schema and cleared \(detached) references.",
                        bundle: RockxyLocalization.bundle
                    )
                    : String(localized: "Deleted schema.", bundle: RockxyLocalization.bundle)
            )
        } catch {
            importStatus = .failure(error.localizedDescription)
        }
    }
}
