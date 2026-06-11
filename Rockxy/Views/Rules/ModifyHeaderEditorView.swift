import SwiftUI

// Renders the modify header editor interface for rule editing and management.

// MARK: - EditableHeaderOperation

/// Mutable model for editing a single header operation in the editor view.
@Observable
final class EditableHeaderOperation: Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        phase: HeaderModifyPhase = .request,
        type: HeaderOperationType = .replace,
        headerName: String = "",
        headerValue: String = ""
    ) {
        self.id = id
        self.phase = phase
        self.type = type
        self.headerName = headerName
        self.headerValue = headerValue
    }

    convenience init(from operation: HeaderOperation) {
        self.init(
            phase: operation.phase,
            type: operation.type,
            headerName: operation.headerName,
            headerValue: operation.headerValue ?? ""
        )
    }

    // MARK: Internal

    let id: UUID
    var phase: HeaderModifyPhase
    var type: HeaderOperationType
    var headerName: String
    var headerValue: String

    var isValid: Bool {
        validationMessage == nil
    }

    var validationMessage: String? {
        guard !headerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "Header Name is required")
        }
        if type != .remove, headerValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Header Value is required for \(type.editorLabel)")
        }
        return nil
    }

    func toHeaderOperation() -> HeaderOperation {
        HeaderOperation(
            type: type,
            headerName: headerName.trimmingCharacters(in: .whitespacesAndNewlines),
            headerValue: type == .remove ? nil : headerValue.trimmingCharacters(in: .whitespacesAndNewlines),
            phase: phase
        )
    }
}

// MARK: - ModifyHeaderEditorView

/// Shared editor component for managing a list of header operations.
/// Used by both `RuleEditSheet` (inline quick-add) and `ModifyHeaderEditSheet`
/// (dedicated window editor). Supports add/remove rows, inline validation,
/// and phase selection per operation.
struct ModifyHeaderEditorView: View {
    // MARK: Internal

    @Binding var operations: [EditableHeaderOperation]

    var allValid: Bool {
        !operations.isEmpty && operations.allSatisfy { $0.validationMessage == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
            helperText

            if operations.isEmpty {
                emptyState
            } else {
                operationsTable
            }

            addButton

            validationMessages
        }
    }

    // MARK: Private

    private static let phaseWidth: CGFloat = 92
    private static let operationWidth: CGFloat = 104
    private static let minFieldWidth: CGFloat = 150
    private static let removeWidth: CGFloat = 24
    private static let rowSpacing: CGFloat = 8

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var helperText: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
            Text(String(localized: "Operations are applied in order. Later rows can overwrite earlier rows."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(nsColor: .labelColor).opacity(0.72))
            Spacer()
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text(String(localized: "No operations. Add at least one header operation."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var operationsTable: some View {
        VStack(spacing: 0) {
            headerRow

            VStack(spacing: 6) {
                ForEach(operations) { operation in
                    operationRow(operation)
                }
            }
            .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var headerRow: some View {
        HStack(spacing: Self.rowSpacing) {
            Text(String(localized: "Phase"))
                .frame(width: Self.phaseWidth, alignment: .leading)
            Text(String(localized: "Operation"))
                .frame(width: Self.operationWidth, alignment: .leading)
            Text(String(localized: "Header Name"))
                .frame(minWidth: Self.minFieldWidth, maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "Header Value"))
                .frame(minWidth: Self.minFieldWidth, maxWidth: .infinity, alignment: .leading)
            Spacer()
                .frame(width: Self.removeWidth)
        }
        .font(toolMetrics.tableHeaderFont())
        .fontWeight(.semibold)
        .foregroundStyle(Color(nsColor: .labelColor))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var addButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                operations.append(EditableHeaderOperation())
            }
        } label: {
            Label(String(localized: "Add Operation"), systemImage: "plus")
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 2)
    }

    @ViewBuilder private var validationMessages: some View {
        let invalidOps = operations.enumerated().compactMap { index, op -> (Int, String)? in
            guard let message = op.validationMessage else {
                return nil
            }
            return (index, message)
        }
        if !invalidOps.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(invalidOps, id: \.0) { index, message in
                    Text(String(localized: "Row \(index + 1): \(message)"))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func operationRow(_ operation: EditableHeaderOperation) -> some View {
        HStack(spacing: Self.rowSpacing) {
            Picker("", selection: Binding(
                get: { operation.phase },
                set: { operation.phase = $0 }
            )) {
                Text(String(localized: "Request")).tag(HeaderModifyPhase.request)
                Text(String(localized: "Response")).tag(HeaderModifyPhase.response)
                Text(String(localized: "Both")).tag(HeaderModifyPhase.both)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: Self.phaseWidth)
            .controlSize(.small)

            Picker("", selection: Binding(
                get: { operation.type },
                set: { operation.type = $0 }
            )) {
                Text(HeaderOperationType.replace.editorLabel).tag(HeaderOperationType.replace)
                Text(HeaderOperationType.add.editorLabel).tag(HeaderOperationType.add)
                Text(HeaderOperationType.remove.editorLabel).tag(HeaderOperationType.remove)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: Self.operationWidth)
            .controlSize(.small)

            TextField(
                String(localized: "Header name"),
                text: Binding(
                    get: { operation.headerName },
                    set: { operation.headerName = $0 }
                )
            )
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(minWidth: Self.minFieldWidth)

            headerValueField(for: operation)

            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    operations.removeAll { $0.id == operation.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(toolMetrics.secondaryFont())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "Remove operation"))
            .frame(width: Self.removeWidth)
        }
    }

    @ViewBuilder private func headerValueField(for operation: EditableHeaderOperation) -> some View {
        if operation.type == .remove {
            Text(String(localized: "Not used"))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: Self.minFieldWidth, minHeight: toolMetrics.formControlHeight, alignment: .leading)
                .padding(.horizontal, 7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            TextField(
                String(localized: "Header value"),
                text: Binding(
                    get: { operation.headerValue },
                    set: { operation.headerValue = $0 }
                )
            )
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(minWidth: Self.minFieldWidth)
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - Helper: Build Operations from Editable Models

extension [EditableHeaderOperation] {
    func toHeaderOperations() -> [HeaderOperation] {
        map { $0.toHeaderOperation() }
    }

    static func from(_ operations: [HeaderOperation]) -> [EditableHeaderOperation] {
        if operations.isEmpty {
            return [EditableHeaderOperation()]
        }
        return operations.map { EditableHeaderOperation(from: $0) }
    }
}

// MARK: - Helper: Phase Summary

extension [HeaderOperation] {
    /// Computes the phase summary label for display in rule lists.
    var phaseSummaryLabel: String {
        guard !isEmpty else {
            return ""
        }
        let phases = Set(map(\.phase))
        if phases == [.request] {
            return "Req"
        }
        if phases == [.response] {
            return "Resp"
        }
        if phases == [.both] {
            return "Both"
        }
        return "Mixed"
    }

    /// Generates shorthand summary: +HeaderA, -HeaderB, ~HeaderC
    var operationSummary: String {
        map { op in
            let prefix = switch op.type {
            case .add: "+"
            case .remove: "-"
            case .replace: "~"
            }
            return "\(prefix)\(op.headerName)"
        }
        .joined(separator: ", ")
    }
}

// MARK: - HeaderOperationType + Editor Labels

extension HeaderOperationType {
    var editorLabel: String {
        switch self {
        case .add:
            String(localized: "Add")
        case .remove:
            String(localized: "Remove")
        case .replace:
            String(localized: "Set")
        }
    }
}
