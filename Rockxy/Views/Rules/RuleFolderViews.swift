import SwiftUI

// Folder controls shared by the Map Local and Breakpoint rule windows.

// MARK: - RuleFolderToggle

/// A folder's checkbox: mixed while only some of its rules are on; clicking turns them all on
/// or off through `setEnabled`, which applies the active-rule limit.
struct RuleFolderToggle: View {
    let folder: RuleFolder
    let rules: [ProxyRule]
    let setEnabled: ([UUID], Bool) -> Void

    var body: some View {
        let states = rules.map { rule in
            Binding(
                get: { rule.isEnabled },
                set: { setEnabled([rule.id], $0) }
            )
        }
        Toggle(sources: states, isOn: \.self) {
            Text(folder.name)
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .disabled(rules.isEmpty)
        .accessibilityLabel(String(localized: "Enable rules in \(folder.name)", bundle: RockxyLocalization.bundle))
    }
}

// MARK: - RuleFolderNameLabel

struct RuleFolderNameLabel: View {
    let folder: RuleFolder
    let ruleCount: Int

    var body: some View {
        Label {
            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: "folder")
        }
        .help(String(AttributedString(
            localized: "\(folder.name) · ^[\(ruleCount) rule](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters))
    }
}

// MARK: - RuleFolderMenuItems

/// "New Folder with Selection" and "Move to Folder" for the selected rules.
struct RuleFolderMenuItems: View {
    let store: RuleFolderStore
    let ruleIDs: [UUID]
    var onCreated: (UUID) -> Void = { _ in }

    var body: some View {
        Button(String(localized: "New Folder with Selection", bundle: RockxyLocalization.bundle)) {
            if let id = store.createFolder(
                named: String(localized: "New Folder", bundle: RockxyLocalization.bundle),
                containing: ruleIDs
            ) {
                onCreated(id)
            }
        }
        .disabled(ruleIDs.isEmpty)
        if !store.folders.isEmpty {
            Menu(String(localized: "Move to Folder", bundle: RockxyLocalization.bundle)) {
                ForEach(store.folders) { folder in
                    Button(folder.name) {
                        store.move(ruleIDs: Set(ruleIDs), toFolder: folder.id)
                    }
                }
                Divider()
                Button(String(localized: "Top Level", bundle: RockxyLocalization.bundle)) {
                    store.move(ruleIDs: Set(ruleIDs), toFolder: nil)
                }
            }
            .disabled(ruleIDs.isEmpty)
        }
    }
}

// MARK: - RuleFolderContextItems

/// Context menu for a folder row.
struct RuleFolderContextItems: View {
    let store: RuleFolderStore
    let folder: RuleFolder
    let onRename: (RuleFolder) -> Void

    var body: some View {
        Button(String(localized: "Rename Folder…", bundle: RockxyLocalization.bundle)) {
            onRename(folder)
        }
        Button(String(localized: "Delete Folder", bundle: RockxyLocalization.bundle)) {
            store.deleteFolder(id: folder.id)
        }
        .help(String(localized: "The folder's rules move back to the top level.", bundle: RockxyLocalization.bundle))
    }
}

// MARK: - RuleFolderRenameModifier

struct RuleFolderRenameModifier: ViewModifier {
    // MARK: Internal

    let store: RuleFolderStore

    @Binding var folder: RuleFolder?

    func body(content: Content) -> some View {
        content.alert(
            String(localized: "Rename Folder", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { folder != nil },
                set: {
                    if !$0 {
                        folder = nil
                    }
                }
            )
        ) {
            TextField(String(localized: "Folder name", bundle: RockxyLocalization.bundle), text: $draft)
            Button(String(localized: "Rename", bundle: RockxyLocalization.bundle)) {
                if let folder {
                    store.rename(folderID: folder.id, to: draft)
                }
                folder = nil
            }
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {
                folder = nil
            }
        }
        .onChange(of: folder?.id) {
            draft = folder?.name ?? ""
        }
        .alert(
            String(localized: "Folder Limit Reached", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { store.limitMessage != nil },
                set: {
                    if !$0 {
                        store.limitMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) {
                store.limitMessage = nil
            }
        } message: {
            Text(store.limitMessage ?? "")
        }
    }

    // MARK: Private

    @State private var draft = ""
}

extension View {
    func ruleFolderRenameAlert(store: RuleFolderStore, folder: Binding<RuleFolder?>) -> some View {
        modifier(RuleFolderRenameModifier(store: store, folder: folder))
    }
}
