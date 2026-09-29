import AppKit
import SwiftUI

// Tools > Reverse Proxy: local ports that forward to a real server so clients without
// proxy support can be captured by changing their base URL.

// MARK: - ReverseProxyWindowScene

struct ReverseProxyWindowScene: Scene {
    var body: some Scene {
        Window(String(localized: "Reverse Proxy", bundle: RockxyLocalization.bundle), id: "reverseProxy") {
            ToolWindowDisplayMetricsProvider {
                ReverseProxyWindowView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 860, height: 420)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
    }
}

// MARK: - ReverseProxyWindowView

struct ReverseProxyWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            Text(String(
                localized: """
                Each rule listens on a local port and forwards every request to one server, so a client \
                that cannot use a proxy (cURL, scripts, embedded devices) is captured by switching its \
                base URL to the local address. Listeners run while the proxy is running and accept \
                connections from this Mac only.
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
                        String(localized: "No Reverse Proxies", bundle: RockxyLocalization.bundle),
                        systemImage: "arrow.left.arrow.right.circle"
                    )
                } description: {
                    Text(String(
                        localized: "Add a rule, then point your client at http://127.0.0.1:<local port>.",
                        bundle: RockxyLocalization.bundle
                    ))
                } actions: {
                    Button(String(localized: "Add Reverse Proxy…", bundle: RockxyLocalization.bundle)) {
                        editingRule = newRuleDraft()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ruleTable
            }

            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 320)
        .sheet(item: $editingRule) { draft in
            ReverseProxyRuleEditor(
                draft: draft,
                existingRules: store.rules,
                proxyPort: AppSettingsStorage.load().proxyPort
            ) { saved in
                store.upsert(saved)
                selection = saved.id
                editingRule = nil
            } onCancel: {
                editingRule = nil
            }
        }
    }

    // MARK: Private

    @State private var store = ReverseProxyStore.shared
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
    @State private var selection: ReverseProxyRule.ID?
    @State private var editingRule: ReverseProxyRule?

    private var selectedRule: ReverseProxyRule? {
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
            TableColumn(String(localized: "Name", bundle: RockxyLocalization.bundle)) { rule in
                Text(rule.name)
            }
            TableColumn(String(localized: "Local Address", bundle: RockxyLocalization.bundle)) { rule in
                Text(verbatim: rule.localURLString)
                    .font(toolMetrics.font(monospaced: true))
                    .textSelection(.enabled)
            }
            TableColumn(String(localized: "Forwards To", bundle: RockxyLocalization.bundle)) { rule in
                Text(verbatim: rule.remoteURLString)
                    .font(toolMetrics.font(monospaced: true))
            }
            TableColumn(String(localized: "Status", bundle: RockxyLocalization.bundle)) { rule in
                statusLabel(store.status(for: rule))
            }
        }
        .contextMenu(forSelectionType: ReverseProxyRule.ID.self) { ids in
            if let id = ids.first, let rule = store.rules.first(where: { $0.id == id }) {
                Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                    editingRule = rule
                }
                Button(String(localized: "Copy Local Address", bundle: RockxyLocalization.bundle)) {
                    copy(rule.localURLString)
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
                editingRule = newRuleDraft()
            } label: {
                Image(systemName: "plus")
            }
            .help(String(localized: "Add Reverse Proxy…", bundle: RockxyLocalization.bundle))
            .accessibilityLabel(String(localized: "Add Reverse Proxy…", bundle: RockxyLocalization.bundle))

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

            Button(String(localized: "Copy Local Address", bundle: RockxyLocalization.bundle)) {
                if let selectedRule {
                    copy(selectedRule.localURLString)
                }
            }
            .disabled(selectedRule == nil)

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

    private func statusLabel(_ status: ReverseProxyRuleStatus) -> some View {
        let (image, color): (String, Color) = switch status {
        case .listening: ("circle.fill", .green)
        case .portInUse,
             .failed: ("exclamationmark.triangle.fill", .orange)
        case .disabled,
             .proxyStopped: ("circle", .secondary)
        }
        return Label(status.title, systemImage: image)
            .foregroundStyle(color)
            .lineLimit(1)
            .help(status.title)
    }

    private func newRuleDraft() -> ReverseProxyRule {
        let usedPorts = Set(store.rules.map(\.localPort))
        let port = (10_000 ... 10_999).first { !usedPorts.contains($0) } ?? 10_000
        return ReverseProxyRule(
            name: String(localized: "Untitled", bundle: RockxyLocalization.bundle),
            localPort: port,
            remoteHost: "",
            remotePort: 443
        )
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - ReverseProxyRuleEditor

private struct ReverseProxyRuleEditor: View {
    // MARK: Lifecycle

    init(
        draft: ReverseProxyRule,
        existingRules: [ReverseProxyRule],
        proxyPort: Int,
        onSave: @escaping (ReverseProxyRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _rule = State(initialValue: draft)
        self.existingRules = existingRules
        self.proxyPort = proxyPort
        self.onSave = onSave
        self.onCancel = onCancel
    }

    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField(String(localized: "Name", bundle: RockxyLocalization.bundle), text: $rule.name)
                TextField(
                    String(localized: "Local Port", bundle: RockxyLocalization.bundle),
                    value: $rule.localPort,
                    format: .number.grouping(.never)
                )
                Picker(
                    String(localized: "Remote Scheme", bundle: RockxyLocalization.bundle),
                    selection: $rule.remoteScheme
                ) {
                    ForEach(ReverseProxyTarget.Scheme.allCases, id: \.self) { scheme in
                        Text(verbatim: scheme.rawValue.uppercased()).tag(scheme)
                    }
                }
                .onChange(of: rule.remoteScheme) { oldValue, newValue in
                    if rule.remotePort == oldValue.defaultPort {
                        rule.remotePort = newValue.defaultPort
                    }
                }
                TextField(String(localized: "Remote Host", bundle: RockxyLocalization.bundle), text: $rule.remoteHost)
                TextField(
                    String(localized: "Remote Port", bundle: RockxyLocalization.bundle),
                    value: $rule.remotePort,
                    format: .number.grouping(.never)
                )
                Toggle(
                    String(localized: "Preserve Host header", bundle: RockxyLocalization.bundle),
                    isOn: $rule.preserveHostHeader
                )
                .help(String(
                    localized: "Send the client's Host header instead of the remote host. Use only when the server expects the original host.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            .formStyle(.grouped)

            Text(String(
                localized: "Clients use \(rule.localURLString) in place of \(rule.remoteURLString).",
                bundle: RockxyLocalization.bundle
            ))
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(toolMetrics.secondaryFont())
                    .padding(.horizontal, 20)
            }

            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save", bundle: RockxyLocalization.bundle)) {
                    var saved = rule
                    saved.remoteHost = saved.remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
    }

    // MARK: Private

    @State private var rule: ReverseProxyRule
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private let existingRules: [ReverseProxyRule]
    private let proxyPort: Int
    private let onSave: (ReverseProxyRule) -> Void
    private let onCancel: () -> Void

    private var problem: String? {
        ReverseProxyRuleValidator.problem(with: rule, among: existingRules, proxyPort: proxyPort)
    }
}
