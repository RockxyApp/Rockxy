import SwiftUI

// MARK: - HeaderColumnRowState

/// Distinguishes the three lifecycle states a header row can be in.
enum HeaderColumnRowState: Equatable {
    /// A saved column that is currently shown in the traffic table.
    case savedEnabled
    /// A saved column that exists but is hidden from the traffic table.
    case savedDisabled
    /// A name seen in captured traffic that has no saved column yet.
    case discovered
}

// MARK: - HeaderColumnRow

/// Source-aware, stable presentation row for the Custom Header Columns table.
///
/// The identity is keyed by source plus the lowercased header name so a row keeps
/// the same identity as it moves between discovered and saved states, and so the
/// same header name stays independent across Request and Response.
struct HeaderColumnRow: Identifiable {
    let source: HeaderColumnSource
    /// Lowercased header name — the stable key component.
    let normalizedName: String
    /// Saved spelling wins; discovered-only rows use the captured spelling.
    let displayName: String
    /// Present only when a saved column backs this row.
    let savedColumnID: UUID?
    let isEnabled: Bool
    /// True when this name is also present in captured traffic.
    let isAlsoDiscovered: Bool
    let state: HeaderColumnRowState

    var id: String {
        "\(source.rawValue):\(normalizedName)"
    }

    var isRemovable: Bool {
        savedColumnID != nil
    }
}

// MARK: - CustomHeaderColumnsAddOutcome

/// Result of a manual Add attempt, surfaced to the sheet for inline feedback.
enum CustomHeaderColumnsAddOutcome: Equatable {
    /// A brand-new saved column was created (row id to select).
    case added(String)
    /// An existing disabled saved column was enabled (row id to select).
    case enabledExisting(String)
    /// The header already exists and is already enabled.
    case alreadyEnabled
    /// The token failed validation; carries a user-facing message.
    case invalid(String)
}

// MARK: - CustomHeaderColumnsViewModel

/// Testable presentation state for the Custom Header Columns tool window.
///
/// Holds the injected `HeaderColumnStore` (never instantiates or reloads it), the
/// search text, the visible Request/Response source, and the visible selection.
/// All merge/order/validation logic lives here so the view stays declarative.
@MainActor @Observable
final class CustomHeaderColumnsViewModel {
    // MARK: Lifecycle

    init(store: HeaderColumnStore, source: HeaderColumnSource = .request) {
        self.store = store
        self.source = source
    }

    // MARK: Internal

    static let maxHeaderNameLength = 256
    static let maxExpressionLength = 512

    let store: HeaderColumnStore

    var searchText = ""
    /// Row ids (source + lowercased name) currently selected in the visible table.
    var selection: Set<String> = []

    var source: HeaderColumnSource {
        didSet {
            if oldValue != source {
                reconcileSelection()
            }
        }
    }

    /// All rows for the current source: saved (store order) first, then
    /// discovered-only suggestions alphabetically.
    var allRowsForSource: [HeaderColumnRow] {
        rows(for: source)
    }

    /// Rows for the current source filtered by the search text.
    var visibleRows: [HeaderColumnRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return allRowsForSource
        }
        return allRowsForSource.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var savedCount: Int {
        allRowsForSource.count { $0.savedColumnID != nil }
    }

    var enabledCount: Int {
        allRowsForSource.count { $0.state == .savedEnabled }
    }

    var discoveredOnlyCount: Int {
        allRowsForSource.count { $0.state == .discovered }
    }

    var hasRemovableSelection: Bool {
        visibleRows.contains { selection.contains($0.id) && $0.isRemovable }
    }

    static func rowID(source: HeaderColumnSource, normalizedName: String) -> String {
        "\(source.rawValue):\(normalizedName)"
    }

    /// Live inline validation message for the Add field (nil when the token is valid).
    static func validationMessage(for value: String) -> String? {
        if value.isEmpty {
            return String(localized: "Enter a header name.", bundle: RockxyLocalization.bundle)
        }
        if value.count > maxHeaderNameLength {
            return String(
                localized: "Header names are limited to \(maxHeaderNameLength) characters.",
                bundle: RockxyLocalization.bundle
            )
        }
        for character in value where !isTokenCharacter(character) {
            return String(
                localized: "Use letters, digits, or ! # $ % & ' * + - . ^ _ ` | ~ — no spaces or colons.",
                bundle: RockxyLocalization.bundle
            )
        }
        return nil
    }

    /// Validation for a name typed for `source`: a header token, a query parameter name, or a
    /// JSONPath/jq expression for a body column.
    static func validationMessage(for value: String, source: HeaderColumnSource) -> String? {
        switch source {
        case .request,
             .response:
            return validationMessage(for: value)
        case .query:
            if value.isEmpty {
                return String(localized: "Enter a parameter name.", bundle: RockxyLocalization.bundle)
            }
            if value.count > maxHeaderNameLength {
                return String(
                    localized: "Parameter names are limited to \(maxHeaderNameLength) characters.",
                    bundle: RockxyLocalization.bundle
                )
            }
            if value.contains(where: { "&=#?".contains($0) || $0.isWhitespace }) {
                return String(
                    localized: "Enter only the parameter name, without spaces, =, &, ?, or #.",
                    bundle: RockxyLocalization.bundle
                )
            }
            return nil
        case .requestBody,
             .responseBody:
            if value.isEmpty {
                return String(
                    localized: "Enter JSONPath, such as $.data.id, or a jq filter, such as .data.id.",
                    bundle: RockxyLocalization.bundle
                )
            }
            if value.count > maxExpressionLength {
                return String(
                    localized: "Expressions are limited to \(maxExpressionLength) characters.",
                    bundle: RockxyLocalization.bundle
                )
            }
            do {
                if value.hasPrefix("$") {
                    var parser = try JSONPathParser(source: value)
                    _ = try parser.parse()
                } else {
                    _ = try JQFilter(value)
                }
            } catch {
                return error.localizedDescription
            }
            return nil
        }
    }

    /// Removes any selected ids that are no longer visible (hidden by search,
    /// source switch, or store mutation).
    func reconcileSelection() {
        let visibleIDs = Set(visibleRows.map(\.id))
        selection.formIntersection(visibleIDs)
    }

    /// Toggling a discovered row creates one enabled saved column; toggling a
    /// saved row flips its enabled state. Selection is preserved because the row
    /// identity does not change.
    func toggle(rowID: String) {
        guard let row = allRowsForSource.first(where: { $0.id == rowID }) else {
            return
        }
        switch row.state {
        case .discovered:
            store.addColumn(headerName: row.displayName, source: row.source)
        case .savedEnabled,
             .savedDisabled:
            if let id = row.savedColumnID {
                store.toggleColumn(id: id)
            }
        }
    }

    /// Removes saved configuration for the current selection only. Rows whose name
    /// is still discovered survive as discovered-only suggestions; otherwise the
    /// selection collapses to a safe adjacent visible row or clears.
    func removeSelected() {
        let rowsBefore = visibleRows
        let orderedIDs = rowsBefore.map(\.id)
        let removable = rowsBefore.filter { selection.contains($0.id) && $0.isRemovable }
        guard !removable.isEmpty else {
            return
        }

        let anchorIndex = removable
            .compactMap { orderedIDs.firstIndex(of: $0.id) }
            .min() ?? 0

        for row in removable {
            if let id = row.savedColumnID {
                store.removeColumn(id: id)
            }
        }

        let rowsAfter = visibleRows
        selection.formIntersection(Set(rowsAfter.map(\.id)))
        guard selection.isEmpty, !rowsAfter.isEmpty else {
            return
        }
        let index = min(anchorIndex, rowsAfter.count - 1)
        selection = [rowsAfter[index].id]
    }

    /// Manual Add: validate a bounded ASCII HTTP field-name token, then create,
    /// enable, or report a duplicate. Never mutates on validation failure.
    @discardableResult
    func addHeader(_ raw: String) -> CustomHeaderColumnsAddOutcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = Self.validationMessage(for: trimmed, source: source) {
            return .invalid(message)
        }

        let normalized = source.normalizedName(trimmed)
        let rowID = Self.rowID(source: source, normalizedName: normalized)

        if let existing = savedColumn(named: trimmed, source: source) {
            if existing.isEnabled {
                return .alreadyEnabled
            }
            store.toggleColumn(id: existing.id)
            selection = [rowID]
            return .enabledExisting(rowID)
        }

        store.addColumn(headerName: trimmed, source: source)
        selection = [rowID]
        return .added(rowID)
    }

    // MARK: Private

    private static let tokenPunctuation: Set<Character> = [
        "!", "#", "$", "%", "&", "'", "*", "+", "-", ".", "^", "_", "`", "|", "~",
    ]

    private static func isTokenCharacter(_ character: Character) -> Bool {
        guard character.isASCII else {
            return false
        }
        if character.isLetter || character.isNumber {
            return true
        }
        return tokenPunctuation.contains(character)
    }

    private func savedColumn(named name: String, source: HeaderColumnSource) -> HeaderColumn? {
        store.columns.first { (column: HeaderColumn) -> Bool in
            column.source == source && source.namesMatch(column.headerName, name)
        }
    }

    private func discoveredNames(for source: HeaderColumnSource) -> [String] {
        switch source {
        case .request: store.discoveredRequestHeaders
        case .response: store.discoveredResponseHeaders
        case .query,
             .requestBody,
             .responseBody: []
        }
    }

    /// Merges stored and discovered names case-insensitively without mutating the
    /// store: saved spelling wins, discovered-only rows keep captured spelling.
    private func rows(for source: HeaderColumnSource) -> [HeaderColumnRow] {
        let discovered = discoveredNames(for: source)
        let discoveredSet = Set(discovered.map { source.normalizedName($0) })

        var savedByNormalized: [String: Bool] = [:]
        var savedRows: [HeaderColumnRow] = []
        for column in store.columns where column.source == source {
            let normalized = source.normalizedName(column.headerName)
            guard savedByNormalized[normalized] == nil else {
                continue
            }
            savedByNormalized[normalized] = true
            savedRows.append(
                HeaderColumnRow(
                    source: source,
                    normalizedName: normalized,
                    displayName: column.headerName,
                    savedColumnID: column.id,
                    isEnabled: column.isEnabled,
                    isAlsoDiscovered: discoveredSet.contains(normalized),
                    state: column.isEnabled ? .savedEnabled : .savedDisabled
                )
            )
        }

        var discoveredRows: [HeaderColumnRow] = []
        var seen: Set<String> = []
        for name in discovered {
            let normalized = source.normalizedName(name)
            guard savedByNormalized[normalized] == nil, seen.insert(normalized).inserted else {
                continue
            }
            discoveredRows.append(
                HeaderColumnRow(
                    source: source,
                    normalizedName: normalized,
                    displayName: name,
                    savedColumnID: nil,
                    isEnabled: false,
                    isAlsoDiscovered: true,
                    state: .discovered
                )
            )
        }
        discoveredRows.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return savedRows + discoveredRows
    }
}

// MARK: - CustomHeaderColumnsView

/// Dense native macOS tool window for managing request/response header columns.
///
/// The AppKit traffic table owns column order and width; this window only decides
/// which header columns exist and whether each is shown. Changes go straight to the
/// injected `HeaderColumnStore` and are picked up live by the table bridge.
struct CustomHeaderColumnsView: View {
    // MARK: Lifecycle

    init(store: HeaderColumnStore) {
        _model = State(initialValue: CustomHeaderColumnsViewModel(store: store))
    }

    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            infoBanner
            sourcePicker
            tableContent
            footer
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(760, toolMetrics.bodyFontSize * 24 + 448),
            idealWidth: max(860, toolMetrics.bodyFontSize * 24 + 548),
            maxWidth: .infinity,
            minHeight: max(520, toolMetrics.bodyFontSize * 14 + 324),
            idealHeight: max(580, toolMetrics.bodyFontSize * 14 + 384),
            maxHeight: .infinity
        )
        .sheet(isPresented: $showingAdd) {
            AddHeaderColumnSheet(
                source: model.source,
                validate: { [source = model.source] in
                    CustomHeaderColumnsViewModel.validationMessage(for: $0, source: source)
                },
                commit: commitAdd
            )
        }
        .onDeleteCommand {
            if model.hasRemovableSelection {
                model.removeSelected()
            }
        }
        .onChange(of: model.store.columns) { _, _ in
            model.reconcileSelection()
        }
        .onChange(of: model.store.discoveredRequestHeaders) { _, _ in
            model.reconcileSelection()
        }
        .onChange(of: model.store.discoveredResponseHeaders) { _, _ in
            model.reconcileSelection()
        }
        .onChange(of: model.searchText) { _, _ in
            model.reconcileSelection()
        }
    }

    // MARK: Private

    @State private var model: CustomHeaderColumnsViewModel
    @State private var showingAdd = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var infoBannerText: String {
        let discovered = String(
            localized: "Discovered names are cached suggestions from captured traffic.",
            bundle: RockxyLocalization.bundle
        )
        let removal = String(
            localized:
            "Removing a saved column only removes its table configuration — it never deletes captured traffic or history.",
            bundle: RockxyLocalization.bundle
        )
        return "\(discovered) \(removal)"
    }

    private var countsText: String {
        let saved = String(localized: "\(model.savedCount) saved", bundle: RockxyLocalization.bundle)
        let shown = String(localized: "\(model.enabledCount) shown", bundle: RockxyLocalization.bundle)
        let suggested = String(localized: "\(model.discoveredOnlyCount) suggested", bundle: RockxyLocalization.bundle)
        return "\(saved) · \(shown) · \(suggested)"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: toolMetrics.headerSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Custom Header Columns", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.font(weight: .medium))

                Text(
                    String(
                        localized: "Show a header, a query parameter, or a value from a JSON body as a column. Changes appear in the traffic table right away.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            TextField(
                String(localized: "Search header names", bundle: RockxyLocalization.bundle),
                text: $model.searchText
            )
            .textFieldStyle(.roundedBorder)
            .font(toolMetrics.font())
            .frame(width: toolMetrics.fieldWidth(230), height: toolMetrics.formControlHeight)
            .focused($isSearchFocused)
            .accessibilityLabel(String(localized: "Search header names", bundle: RockxyLocalization.bundle))
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.headerTopPadding)
        .padding(.bottom, toolMetrics.headerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(.secondary)

            Text(infoBannerText)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var sourcePicker: some View {
        Picker("", selection: $model.source) {
            Text(String(localized: "Request Headers", bundle: RockxyLocalization.bundle))
                .tag(HeaderColumnSource.request)
            Text(String(localized: "Response Headers", bundle: RockxyLocalization.bundle))
                .tag(HeaderColumnSource.response)
            Text(String(localized: "Query", bundle: RockxyLocalization.bundle))
                .tag(HeaderColumnSource.query)
            Text(String(localized: "Request Body", bundle: RockxyLocalization.bundle))
                .tag(HeaderColumnSource.requestBody)
            Text(String(localized: "Response Body", bundle: RockxyLocalization.bundle))
                .tag(HeaderColumnSource.responseBody)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.controlSpacing)
        .padding(.bottom, toolMetrics.controlSpacing)
        .accessibilityLabel(String(localized: "Header source", bundle: RockxyLocalization.bundle))
    }

    private var tableContent: some View {
        Table(model.visibleRows, selection: $model.selection) {
            TableColumn(String(localized: "Shown", bundle: RockxyLocalization.bundle)) { row in
                Toggle("", isOn: Binding(
                    get: { row.isEnabled },
                    set: { _ in model.toggle(rowID: row.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(
                    row.isEnabled
                        ? String(localized: "Hide \(row.displayName) column", bundle: RockxyLocalization.bundle)
                        : String(localized: "Show \(row.displayName) column", bundle: RockxyLocalization.bundle)
                )
            }
            .width(60)

            TableColumn(String(localized: "Header Name", bundle: RockxyLocalization.bundle)) { row in
                Text(row.displayName)
                    .font(toolMetrics.font(monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.displayName)
                    .foregroundStyle(row.state == .discovered ? .secondary : .primary)
                    .opacity(row.state == .savedDisabled ? 0.55 : 1)
            }
            .width(min: 220, ideal: 440)

            TableColumn(String(localized: "State", bundle: RockxyLocalization.bundle)) { row in
                stateLabel(for: row)
            }
            .width(min: 120, ideal: 150)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(for: ids)
        }
        .overlay {
            tableOverlay
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
    }

    @ViewBuilder private var tableOverlay: some View {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.visibleRows.isEmpty {
            if query.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Header Columns", bundle: RockxyLocalization.bundle),
                    systemImage: "tablecells.badge.ellipsis",
                    description: Text(
                        String(
                            localized: "Add a header name, or capture some traffic to see suggested headers here.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                )
            } else {
                ContentUnavailableView(
                    String(localized: "No Matching Headers", bundle: RockxyLocalization.bundle),
                    systemImage: "magnifyingglass",
                    description: Text(String(
                        localized: "Try a different header name.",
                        bundle: RockxyLocalization.bundle
                    ))
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            addRemoveControl

            Text(countsText)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)

            Spacer()

            Text(String(
                localized: "Drag column headers in the traffic table to reorder or resize.",
                bundle: RockxyLocalization.bundle
            ))
            .font(toolMetrics.metadataFont())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.tail)

            moreMenu
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.top, toolMetrics.footerTopPadding)
        .padding(.bottom, toolMetrics.footerBottomPadding)
        .rockxyFunctionalBar()
    }

    private var addRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(String(localized: "Add Header Column", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Add Header Column", bundle: RockxyLocalization.bundle))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1, height: 18)

            Button {
                model.removeSelected()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.compactIconFontSize))
                    .foregroundStyle(model.hasRemovableSelection ? .primary : .tertiary)
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.hasRemovableSelection)
            .help(String(localized: "Remove Selected Columns", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Remove Selected Columns", bundle: RockxyLocalization.bundle))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Find…", bundle: RockxyLocalization.bundle)) {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Add Header Column…", bundle: RockxyLocalization.bundle)) {
                showingAdd = true
            }

            Divider()

            Button(String(localized: "Toggle Shown", bundle: RockxyLocalization.bundle)) {
                toggleSelection()
            }
            .disabled(model.selection.count != 1)

            Button(String(localized: "Remove Selected", bundle: RockxyLocalization.bundle), role: .destructive) {
                model.removeSelected()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!model.hasRemovableSelection)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More", bundle: RockxyLocalization.bundle))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func stateLabel(for row: HeaderColumnRow) -> some View {
        let text: String
        let color: Color
        switch row.state {
        case .savedEnabled,
             .savedDisabled:
            text = row.isAlsoDiscovered
                ? String(localized: "Saved · Captured", bundle: RockxyLocalization.bundle)
                : String(localized: "Saved", bundle: RockxyLocalization.bundle)
            color = .secondary
        case .discovered:
            text = String(localized: "Discovered", bundle: RockxyLocalization.bundle)
            color = Color(nsColor: .tertiaryLabelColor)
        }
        return Text(text)
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(color)
            .lineLimit(1)
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        let selectedRows = model.visibleRows.filter { ids.contains($0.id) }

        if selectedRows.count == 1, let row = selectedRows.first {
            Button(toggleLabel(for: row)) {
                model.toggle(rowID: row.id)
            }
            Divider()
        }

        Button(String(localized: "Remove", bundle: RockxyLocalization.bundle), role: .destructive) {
            model.selection = ids
            model.removeSelected()
        }
        .disabled(!selectedRows.contains { $0.isRemovable })
    }

    private func toggleLabel(for row: HeaderColumnRow) -> String {
        switch row.state {
        case .savedEnabled:
            String(localized: "Hide From Table", bundle: RockxyLocalization.bundle)
        case .savedDisabled:
            String(localized: "Show In Table", bundle: RockxyLocalization.bundle)
        case .discovered:
            String(localized: "Add As Column", bundle: RockxyLocalization.bundle)
        }
    }

    private func toggleSelection() {
        for id in model.selection {
            model.toggle(rowID: id)
        }
    }

    private func commitAdd(_ raw: String) -> CustomHeaderColumnsAddCommitResult {
        switch model.addHeader(raw) {
        case .added,
             .enabledExisting:
            .success
        case .alreadyEnabled:
            .failure(String(
                localized: "This header column is already added and shown.",
                bundle: RockxyLocalization.bundle
            ))
        case let .invalid(message):
            .failure(message)
        }
    }
}

// MARK: - CustomHeaderColumnsAddCommitResult

/// Outcome of an Add-sheet submission: dismiss on success, keep the sheet open with
/// inline feedback on failure so the field never silently dismisses.
enum CustomHeaderColumnsAddCommitResult: Equatable {
    case success
    case failure(String)
}

// MARK: - AddHeaderColumnSheet

private struct AddHeaderColumnSheet: View {
    // MARK: Internal

    let source: HeaderColumnSource
    let validate: (String) -> String?
    let commit: (String) -> CustomHeaderColumnsAddCommitResult

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Add Header Column", bundle: RockxyLocalization.bundle))
                        .font(toolMetrics.font(weight: .semibold))
                    Text(sourceExplanation)
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                fieldRow(String(localized: "Source", bundle: RockxyLocalization.bundle)) {
                    Text(sourceLabel)
                        .font(toolMetrics.font())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                fieldRow(nameLabel) {
                    TextField("", text: $name, prompt: Text(verbatim: namePrompt))
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font(monospaced: true))
                        .frame(height: toolMetrics.formControlHeight)
                        .focused($isNameFocused)
                        .onChange(of: name) { _, _ in
                            feedback = nil
                        }
                        .onSubmit(attemptCommit)
                        .accessibilityLabel(nameLabel)
                }

                if let message = inlineMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(footnote)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: toolMetrics.controlSpacing) {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    attemptCommit()
                } label: {
                    footerButtonLabel(String(localized: "Add", bundle: RockxyLocalization.bundle))
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(!isSubmittable)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .frame(width: max(420, toolMetrics.fieldWidth(420)))
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { isNameFocused = true }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var feedback: String?
    @FocusState private var isNameFocused: Bool

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var liveValidationMessage: String? {
        trimmedName.isEmpty ? nil : validate(trimmedName)
    }

    private var inlineMessage: String? {
        feedback ?? liveValidationMessage
    }

    private var isSubmittable: Bool {
        !trimmedName.isEmpty && liveValidationMessage == nil
    }

    private var sourceLabel: String {
        switch source {
        case .request: String(localized: "Request Headers", bundle: RockxyLocalization.bundle)
        case .response: String(localized: "Response Headers", bundle: RockxyLocalization.bundle)
        case .query: String(localized: "Query", bundle: RockxyLocalization.bundle)
        case .requestBody: String(localized: "Request Body", bundle: RockxyLocalization.bundle)
        case .responseBody: String(localized: "Response Body", bundle: RockxyLocalization.bundle)
        }
    }

    private var sourceExplanation: String {
        switch source {
        case .request:
            String(
                localized: "Show this request header's value as a column in the traffic table.",
                bundle: RockxyLocalization.bundle
            )
        case .response:
            String(
                localized: "Show this response header's value as a column in the traffic table.",
                bundle: RockxyLocalization.bundle
            )
        case .query:
            String(
                localized: "Show this query parameter's value as a column in the traffic table.",
                bundle: RockxyLocalization.bundle
            )
        case .requestBody,
             .responseBody:
            String(
                localized: "Show a value from the JSON body as a column. Use JSONPath, starting with $, or a jq filter.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private var nameLabel: String {
        switch source {
        case .request,
             .response: String(localized: "Header Name", bundle: RockxyLocalization.bundle)
        case .query: String(localized: "Parameter", bundle: RockxyLocalization.bundle)
        case .requestBody,
             .responseBody: String(localized: "Expression", bundle: RockxyLocalization.bundle)
        }
    }

    private var namePrompt: String {
        switch source {
        case .request,
             .response: "X-Request-Id"
        case .query: "page"
        case .requestBody,
             .responseBody: "$.data.user.name"
        }
    }

    private var footnote: String {
        switch source {
        case .request,
             .response:
            String(
                localized: "Matching is case-insensitive. Request and Response are kept separate.",
                bundle: RockxyLocalization.bundle
            )
        case .query:
            String(
                localized: "Shows the first value when the parameter repeats.",
                bundle: RockxyLocalization.bundle
            )
        case .requestBody,
             .responseBody:
            String(
                localized: "Several results are joined with commas. Bodies that are not JSON show an empty cell.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private func fieldRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .frame(width: toolMetrics.formCompactLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(width: max(80, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 2))
    }

    private func attemptCommit() {
        guard isSubmittable else {
            feedback = validate(trimmedName)
            return
        }
        switch commit(trimmedName) {
        case .success:
            dismiss()
        case let .failure(message):
            feedback = message
        }
    }
}
