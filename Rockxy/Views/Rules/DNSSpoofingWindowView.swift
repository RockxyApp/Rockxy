import SwiftUI

// Tools > DNS Spoofing: connect to another address for a host while the request keeps its
// URL, Host header, and TLS server name.

// MARK: - DNSSpoofingWindowScene

struct DNSSpoofingWindowScene: Scene {
    var body: some Scene {
        Window(String(localized: "DNS Spoofing", bundle: RockxyLocalization.bundle), id: "dnsSpoofing") {
            ToolWindowDisplayMetricsProvider {
                DNSSpoofingWindowView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 720, height: 460)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
    }
}

// MARK: - DNSSpoofingWindowView

struct DNSSpoofingWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            Text(String(
                localized: """
                Each rule sends connections for a host to another address, like an /etc/hosts entry \
                that applies only to traffic through Rockxy. Unlike Map Remote, the URL, the Host \
                header, and the certificate check keep the original host, so a staging server that \
                serves the production name can be tested as is.
                """,
                bundle: RockxyLocalization.bundle
            ))
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()

            if store.rules.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: "No DNS Spoofing Rules", bundle: RockxyLocalization.bundle),
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                } description: {
                    Text(String(
                        localized: "Add a rule to connect to another address for a host.",
                        bundle: RockxyLocalization.bundle
                    ))
                } actions: {
                    Button(String(localized: "Add Rule…", bundle: RockxyLocalization.bundle)) {
                        editingRule = DNSSpoofingRule(host: "", address: "")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ruleTable
            }

            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 360)
        .sheet(item: $editingRule) { draft in
            DNSSpoofingRuleEditor(draft: draft, existingRules: store.rules) { saved in
                store.upsert(saved)
                selection = saved.id
                editingRule = nil
            } onCancel: {
                editingRule = nil
            }
        }
    }

    // MARK: Private

    @State private var store = DNSSpoofingStore.shared
    @State private var selection: DNSSpoofingRule.ID?
    @State private var editingRule: DNSSpoofingRule?
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var selectedRule: DNSSpoofingRule? {
        store.rules.first { $0.id == selection }
    }

    private var ruleTable: some View {
        Table(store.rules, selection: $selection) {
            TableColumn("") { rule in
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { store.setEnabled($0, id: rule.id) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(String(localized: "Enabled", bundle: RockxyLocalization.bundle))
            }
            .width(28)
            TableColumn(String(localized: "Host", bundle: RockxyLocalization.bundle)) { rule in
                Text(verbatim: rule.host)
                    .font(toolMetrics.font(monospaced: true))
            }
            TableColumn(String(localized: "Connects To", bundle: RockxyLocalization.bundle)) { rule in
                Text(verbatim: rule.address)
                    .font(toolMetrics.font(monospaced: true))
                    .textSelection(.enabled)
            }
        }
        .contextMenu(forSelectionType: DNSSpoofingRule.ID.self) { ids in
            if let id = ids.first, let rule = store.rules.first(where: { $0.id == id }) {
                Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                    editingRule = rule
                }
                Divider()
                Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                    store.remove(ids: ids)
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let rule = store.rules.first(where: { $0.id == id }) {
                editingRule = rule
            }
        }
        .onDeleteCommand {
            if let selection {
                store.remove(ids: [selection])
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                editingRule = DNSSpoofingRule(host: "", address: "")
            } label: {
                Image(systemName: "plus")
            }
            .help(String(localized: "Add Rule…", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Add Rule…", bundle: RockxyLocalization.bundle))

            Button {
                if let selection {
                    store.remove(ids: [selection])
                }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selection == nil)
            .help(String(localized: "Delete", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Delete", bundle: RockxyLocalization.bundle))

            Spacer()

            Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                editingRule = selectedRule
            }
            .disabled(selectedRule == nil)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - DNSSpoofingRuleEditor

private struct DNSSpoofingRuleEditor: View {
    // MARK: Lifecycle

    init(
        draft: DNSSpoofingRule,
        existingRules: [DNSSpoofingRule],
        onSave: @escaping (DNSSpoofingRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _rule = State(initialValue: draft)
        self.existingRules = existingRules
        self.onSave = onSave
        self.onCancel = onCancel
    }

    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField(String(localized: "Host", bundle: RockxyLocalization.bundle), text: $rule.host)
                    .help(String(
                        localized: "An exact host name, or *.example.com for every subdomain.",
                        bundle: RockxyLocalization.bundle
                    ))
                TextField(String(localized: "Connect To", bundle: RockxyLocalization.bundle), text: $rule.address)
                    .help(String(
                        localized: "The IP address or host name Rockxy connects to instead. The port stays the same.",
                        bundle: RockxyLocalization.bundle
                    ))
            }
            .formStyle(.grouped)

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(toolMetrics.secondaryFont())
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save", bundle: RockxyLocalization.bundle)) {
                    var saved = rule
                    saved.host = saved.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    saved.address = saved.address.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
    }

    // MARK: Private

    @State private var rule: DNSSpoofingRule
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private let existingRules: [DNSSpoofingRule]
    private let onSave: (DNSSpoofingRule) -> Void
    private let onCancel: () -> Void

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var problem: String? {
        DNSSpoofingRuleValidator.problem(with: rule, among: existingRules)
    }
}
