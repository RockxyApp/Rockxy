import SwiftUI

/// One row in the Scripting List — either a folder (with disclosure + editable
/// name) or a script (checkbox toggle + Name / Method / Matching Rule columns).
struct ScriptListRow: View {
    // MARK: Internal

    @Bindable var viewModel: ScriptingListViewModel

    let row: ScriptListDisplayRow

    var body: some View {
        HStack(spacing: 0) {
            switch row.kind {
            case let .folder(folder):
                folderRow(folder: folder)
            case let .script(script):
                scriptRow(script: script)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Private

    // MARK: - Folder row

    private func folderRow(folder: ScriptFolder) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(row.indent) * 16)
            Button {
                viewModel.toggleFolder(id: folder.id)
            } label: {
                Image(systemName: folder.expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: allChildrenBinding(for: folder))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            if viewModel.renamingFolderID == folder.id {
                TextField(
                    "",
                    text: $viewModel.renamingFolderText,
                    onEditingChanged: { isEditing in
                        if !isEditing, viewModel.renamingFolderID == folder.id {
                            viewModel.cancelFolderRename()
                        }
                    },
                    onCommit: {
                        viewModel.commitFolderRename()
                    }
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            } else {
                Text(folder.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
    }

    // MARK: - Script row

    private func scriptRow(script: PluginInfoSnapshot) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer().frame(width: CGFloat(row.indent) * 16 + 14)
                Toggle("", isOn: Binding(
                    get: { script.isEnabled },
                    set: { _ in Task { await viewModel.toggleScript(id: script.id) } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Text(script.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(script.isEnabled ? Color.primary : Color.secondary)
                Spacer()
            }
            .frame(width: 380, alignment: .leading)

            HStack(spacing: 0) {
                Text(script.method ?? "ANY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .frame(width: 110, alignment: .leading)

            HStack(spacing: 0) {
                if let pattern = script.urlPattern, !pattern.isEmpty {
                    Text(pattern)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("<Missing URL>")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .opacity(script.isEnabled ? 1.0 : 0.6)
    }

    // MARK: - Helpers

    private func allChildrenBinding(for folder: ScriptFolder) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                let ids = Set(folder.scriptIDs)
                let matching = viewModel.plugins.filter { ids.contains($0.id) }
                return !matching.isEmpty && matching.allSatisfy(\.isEnabled)
            },
            set: { newValue in
                Task {
                    await viewModel.setScriptsEnabled(ids: folder.scriptIDs, enabled: newValue)
                }
            }
        )
    }
}
