import SwiftUI

// Table rendering for the Block List window. Extracted from `BlockListWindowView.swift`
// to keep that file within the length limit; behavior and type names are unchanged.

// MARK: - BlockListTableView

/// One displayed line: a folder header or a rule (indented when it sits inside a folder).
struct BlockListDisplayRow: Identifiable {
    let row: RuleListRow
    let indented: Bool

    var id: UUID {
        row.id
    }
}

struct BlockListTableView<ContextMenuContent: View>: View {
    // MARK: Internal

    let rows: [BlockListDisplayRow]
    let folderRules: (RuleFolder) -> [ProxyRule]
    let collapsedFolderIDs: Set<UUID>
    let onToggleCollapse: (UUID) -> Void
    let onSetFolderEnabled: ([UUID], Bool) -> Void
    let onDrop: ([String], RuleListRow) -> Void
    let isSearching: Bool
    @Binding var selectedRuleID: UUID?

    let onToggle: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDelete: (UUID) -> Void
    @ViewBuilder let contextMenuItems: (UUID) -> ContextMenuContent

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            ZStack {
                zebraRows

                if rows.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: isSearching ? "magnifyingglass" : "hand.raised")
                            .font(.system(size: max(22, toolMetrics.emptyStateFontSize + 8)))
                            .foregroundStyle(.secondary)
                        Text(
                            isSearching
                                ? String(localized: "No matching rules", bundle: RockxyLocalization.bundle)
                                : String(localized: "No Block List rules", bundle: RockxyLocalization.bundle)
                        )
                        .font(toolMetrics.font(weight: .medium))
                        Text(
                            isSearching
                                ? String(
                                    localized: "Try a different name, method, or URL pattern.",
                                    bundle: RockxyLocalization.bundle
                                )
                                : String(
                                    localized: "Click \"+\" or press ⌘N to create a rule.",
                                    bundle: RockxyLocalization.bundle
                                )
                        )
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                                displayRow(entry, index: index)
                                    .contextMenu {
                                        contextMenuItems(entry.id)
                                    }
                                    .draggable(RuleFolderDrag.payload(
                                        for: entry.id,
                                        selection: selectedRuleID.map { [$0] } ?? []
                                    ))
                                    .dropDestination(for: String.self) { payloads, _ in
                                        onDrop(payloads, entry.row)
                                        return true
                                    }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minHeight: toolMetrics.tableRowHeight * 8, maxHeight: .infinity)
        .clipped()
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder
    private func displayRow(_ entry: BlockListDisplayRow, index: Int) -> some View {
        switch entry.row.kind {
        case let .rule(rule):
            BlockRuleTableRow(
                rule: rule,
                isSelected: selectedRuleID == rule.id,
                rowIndex: index,
                indented: entry.indented,
                onSelect: { selectedRuleID = rule.id },
                onToggle: { onToggle(rule.id) }
            )
            .onTapGesture(count: 2) {
                onEdit(rule.id)
            }
        case let .folder(folder):
            BlockFolderTableRow(
                folder: folder,
                rules: folderRules(folder),
                isSelected: selectedRuleID == folder.id,
                isCollapsed: collapsedFolderIDs.contains(folder.id),
                rowIndex: index,
                onSelect: { selectedRuleID = folder.id },
                onToggleCollapse: { onToggleCollapse(folder.id) },
                onSetEnabled: onSetFolderEnabled
            )
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text(String(localized: "Enabled", bundle: RockxyLocalization.bundle))
                .frame(width: 66, alignment: .leading)
            tableDivider
            Text(String(localized: "Name", bundle: RockxyLocalization.bundle))
                .frame(width: 300, alignment: .leading)
            tableDivider
            Text(String(localized: "Block Action", bundle: RockxyLocalization.bundle))
                .frame(width: 150, alignment: .leading)
            tableDivider
            Text(String(localized: "Method", bundle: RockxyLocalization.bundle))
                .frame(width: 90, alignment: .leading)
            tableDivider
            Text(String(localized: "Matching Rule", bundle: RockxyLocalization.bundle))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(toolMetrics.tableHeaderFont())
        .lineLimit(1)
        .padding(.horizontal, toolMetrics.tableCellHorizontalPadding)
        .frame(height: toolMetrics.tableRowHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var tableDivider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.22))
            .frame(width: 1, height: max(16, toolMetrics.tableRowHeight - 10))
            .padding(.trailing, 10)
    }

    private var zebraRows: some View {
        GeometryReader { proxy in
            let rowCount = max(1, Int(ceil(proxy.size.height / toolMetrics.tableRowHeight)))
            VStack(spacing: 0) {
                ForEach(0 ..< rowCount, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary
                            .opacity(0.08))
                        .frame(height: toolMetrics.tableRowHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - BlockRuleTableRow

private struct BlockRuleTableRow: View {
    // MARK: Internal

    let rule: ProxyRule
    let isSelected: Bool
    let rowIndex: Int
    var indented = false
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 66)

            Text(rule.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, indented ? 18 : 0)
                .frame(width: 300, alignment: .leading)

            actionLabel
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 150, alignment: .leading)

            Text(rule.matchCondition.method ?? "ANY")
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            Text(rule.matchCondition.sourceURLPattern ?? rule.matchCondition.urlPattern ?? "")
                .font(toolMetrics.font(monospaced: true))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(toolMetrics.font())
        .padding(.horizontal, toolMetrics.tableCellHorizontalPadding)
        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
        .frame(height: toolMetrics.tableRowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.22))
        }
        return AnyShapeStyle(rowIndex.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary
            .opacity(0.08))
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder private var actionLabel: some View {
        if case let .block(statusCode) = rule.action {
            Text(
                statusCode == 0
                    ? String(localized: "Drop Connection", bundle: RockxyLocalization.bundle)
                    : String(localized: "Return 403 Forbidden", bundle: RockxyLocalization.bundle)
            )
        }
    }
}

// MARK: - BlockFolderTableRow

private struct BlockFolderTableRow: View {
    // MARK: Internal

    let folder: RuleFolder
    let rules: [ProxyRule]
    let isSelected: Bool
    let isCollapsed: Bool
    let rowIndex: Int
    let onSelect: () -> Void
    let onToggleCollapse: () -> Void
    let onSetEnabled: ([UUID], Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            RuleFolderToggle(folder: folder, rules: rules, setEnabled: onSetEnabled)
                .frame(width: 66)

            HStack(spacing: 4) {
                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isCollapsed
                        ? String(localized: "Expand \(folder.name)", bundle: RockxyLocalization.bundle)
                        : String(localized: "Collapse \(folder.name)", bundle: RockxyLocalization.bundle)
                )
                RuleFolderNameLabel(folder: folder, ruleCount: rules.count)
            }
            .frame(width: 300, alignment: .leading)

            Spacer(minLength: 0)
        }
        .font(toolMetrics.font(weight: .medium))
        .padding(.horizontal, toolMetrics.tableCellHorizontalPadding)
        .frame(height: toolMetrics.tableRowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onToggleCollapse()
        }
        .onTapGesture {
            onSelect()
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.22))
        }
        return AnyShapeStyle(rowIndex.isMultiple(of: 2) ? Color(nsColor: .textBackgroundColor) : Color.secondary
            .opacity(0.08))
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
