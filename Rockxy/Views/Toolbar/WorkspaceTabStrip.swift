import SwiftUI

// Renders the workspace tab strip interface for toolbar controls and filtering.

// MARK: - WorkspaceTabStrip

struct WorkspaceTabStrip: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        HStack(spacing: 0) {
            tabsRow
            addButton
        }
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: Private

    private var store: WorkspaceStore {
        coordinator.workspaceStore
    }

    private var tabsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(store.workspaces) { workspace in
                    WorkspaceTabItem(
                        workspace: workspace,
                        isActive: workspace.id == store.activeWorkspaceID,
                        onSelect: { store.selectWorkspace(id: workspace.id) },
                        onClose: { store.closeWorkspace(id: workspace.id) },
                        onDuplicate: { store.duplicateWorkspace(id: workspace.id) },
                        onCloseOthers: { store.closeOtherWorkspaces(except: workspace.id) },
                        onRename: { newTitle in store.renameWorkspace(id: workspace.id, to: newTitle) }
                    )
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            let ws = store.createWorkspace()
            coordinator.recomputeFilteredTransactions(for: ws)
            coordinator.rebuildSidebarIndexes(for: ws)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(store.workspaces.count >= store.maxWorkspaces)
        .help(String(localized: "New Tab"))
    }
}

// MARK: - WorkspaceTabItem

private struct WorkspaceTabItem: View {
    // MARK: Internal

    let workspace: WorkspaceState
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onCloseOthers: () -> Void
    let onRename: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if !workspace.filterCriteria.isEmpty {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor)
            }

            if isEditing {
                TextField("", text: $editingTitle, onCommit: {
                    if !editingTitle.isEmpty {
                        onRename(editingTitle)
                    }
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(minWidth: 60)
            } else {
                Text(workspace.title)
                    .font(.system(size: 11, weight: isActive ? .medium : .regular))
                    .lineLimit(1)
            }

            if workspace.isClosable {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            isActive
                ? Color(nsColor: .controlBackgroundColor)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Divider()
                .frame(height: 14)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) {
            guard workspace.isClosable else {
                return
            }
            editingTitle = workspace.title
            isEditing = true
        }
        .contextMenu {
            if workspace.isClosable {
                Button(String(localized: "Close Tab")) { onClose() }
            }
            Button(String(localized: "Close Other Tabs")) { onCloseOthers() }
            Divider()
            Button(String(localized: "Duplicate Tab")) { onDuplicate() }
            if workspace.isClosable {
                Button(String(localized: "Rename Tab")) {
                    editingTitle = workspace.title
                    isEditing = true
                }
            }
        }
    }

    // MARK: Private

    @State private var isEditing = false
    @State private var editingTitle = ""
}
