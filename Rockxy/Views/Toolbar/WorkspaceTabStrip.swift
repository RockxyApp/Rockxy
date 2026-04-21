import SwiftUI

// Renders the workspace tab strip interface for toolbar controls and filtering.

// MARK: - WorkspaceTabStrip

struct WorkspaceTabStrip: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        HStack(spacing: 8) {
            tabsRow
            addButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 32)
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
            HStack(spacing: 6) {
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
            .padding(.trailing, 4)
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
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
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
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            if isEditing {
                TextField("", text: $editingTitle, onCommit: {
                    if !editingTitle.isEmpty {
                        onRename(editingTitle)
                    }
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(minWidth: 60)
            } else {
                Text(workspace.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
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
                .opacity(isActive || isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tabBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tabBorder, lineWidth: isActive ? 1 : 0.5)
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
        .onHover { isHovering = $0 }
    }

    // MARK: Private

    @State private var isEditing = false
    @State private var editingTitle = ""
    @State private var isHovering = false

    private var tabBackground: Color {
        if isActive {
            return Color(nsColor: .controlBackgroundColor)
        }
        if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.45)
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    private var tabBorder: Color {
        if isActive {
            return Color(nsColor: .separatorColor).opacity(0.8)
        }
        if isHovering {
            return Color(nsColor: .separatorColor).opacity(0.35)
        }
        return Color.clear
    }
}
