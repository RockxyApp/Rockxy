import SwiftUI

// MARK: - BreakpointTemplateWindowView

struct BreakpointTemplateWindowView: View {
    // MARK: Internal

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            editor
        }
        .frame(width: 802, height: 631)
    }

    // MARK: Private

    @State private var store = BreakpointTemplateStore.shared

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Breakpoint Templates"))
                .font(.system(size: 13))
                .padding(.top, 20)
                .padding(.horizontal, 20)

            List(selection: $store.selectedTemplateID) {
                templateSection(kind: .request)
                templateSection(kind: .response)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 6)

            bottomControls
        }
        .frame(width: 238)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func templateSection(kind: BreakpointTemplateKind) -> some View {
        Section {
            ForEach(store.templates(for: kind)) { template in
                Text(template.name.isEmpty ? String(localized: "Untitled") : template.name)
                    .font(.system(size: 13))
                    .tag(template.id)
            }
        } header: {
            Label(kind.groupTitle, systemImage: "folder")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button {
                    store.addTemplate()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                Divider()
                    .frame(height: 18)

                Button {
                    store.removeSelectedTemplate()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selectedTemplate == nil || store.templates.count <= 1)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .frame(width: 42, height: 22)

            Button {
                NSSound.beep()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Templates can be applied from the Breakpoint Queue Raw tab."))

            Spacer()

            Menu {
                Button(String(localized: "New Request Template")) {
                    store.addTemplate(kind: .request)
                }
                .keyboardShortcut(
                    store.selectedKind == .request ? "n" : "n",
                    modifiers: store.selectedKind == .request ? .command : [.command, .shift]
                )
                Button(String(localized: "New Response Template")) {
                    store.addTemplate(kind: .response)
                }
                .keyboardShortcut(
                    store.selectedKind == .response ? "n" : "n",
                    modifiers: store.selectedKind == .response ? .command : [.command, .shift]
                )
                Button(String(localized: "Duplicate")) {
                    store.duplicateSelectedTemplate()
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store.selectedTemplate == nil)
                Button(String(localized: "Reset Raw Message")) {
                    store.resetSelectedTemplate()
                }
                .disabled(store.selectedTemplate == nil)
                Divider()
                Button(String(localized: "Delete"), role: .destructive) {
                    store.removeSelectedTemplate()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selectedTemplate == nil || store.templates.count <= 1)
            } label: {
                HStack(spacing: 6) {
                    Text(String(localized: "More"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.bordered)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    @ViewBuilder private var editor: some View {
        if let template = store.selectedTemplate {
            VStack(alignment: .leading, spacing: 12) {
                Text(template.kind == .request
                    ? String(localized: "Request Template")
                    : String(localized: "Response Template"))
                    .font(.system(size: 13))
                    .padding(.top, 20)

                HStack(spacing: 8) {
                    Text(String(localized: "Name:"))
                        .frame(width: 58, alignment: .trailing)
                    TextField(String(localized: "Untitled"), text: Binding(
                        get: { template.name },
                        set: { store.updateSelected(name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(template.kind == .request
                    ? String(localized: "Request Raw Message")
                    : String(localized: "Response Raw Message"))
                    .font(.system(size: 13))
                    .padding(.top, 2)

                rawEditor(template: template)

                Text(
                    String(
                        localized:
                        "To apply Breakpoint Template: In the Breakpoint Window -> Select Raw Tab -> Template"
                    )
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        } else {
            ContentUnavailableView(
                String(localized: "No Template Selected"),
                systemImage: "doc.text",
                description: Text(String(localized: "Create a request or response template to continue."))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rawEditor(template: BreakpointTemplate) -> some View {
        let validation = BreakpointRawMessage.validation(for: template.rawMessage, kind: template.kind)
        return VStack(alignment: .leading, spacing: 8) {
            Label(validation.message, systemImage: "circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(validation.isValid ? Color.green : Color.red)
                .labelStyle(.titleAndIcon)

            MapLocalHTTPMessageEditor(text: Binding(
                get: { template.rawMessage },
                set: { store.updateSelected(rawMessage: $0) }
            ))
            .frame(minHeight: 382)
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor).opacity(0.45)))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
