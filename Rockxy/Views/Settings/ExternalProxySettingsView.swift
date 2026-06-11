import SwiftUI

// MARK: - ExternalProxySettingsView

struct ExternalProxySettingsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(String(localized: "Enable External Proxy Tool"), isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .font(toolMetrics.font(weight: .medium))

            HStack(alignment: .top, spacing: 28) {
                protocolList
                configurationPanel
            }

            bypassSection

            if let statusMessage {
                StatusDisclosure(message: statusMessage, isError: statusIsError)
            }

            HStack {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: max(22, toolMetrics.bodyFontSize + 9)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Upstream Proxy Help"))

                Spacer()

                Button(String(localized: "Test Connection")) {
                    testConnection()
                }
                .disabled(isTesting || !isEnabled)

                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Done")) {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(toolMetrics.font())
        .padding(28)
        .frame(width: toolMetrics.fieldWidth(900))
        .onAppear(perform: loadDraft)
        .alert(String(localized: "Upstream Proxy"), isPresented: $showHelp) {
            Button(String(localized: "OK")) {}
        } message: {
            Text(
                String(
                    localized: "Automatic, HTTP, and HTTPS upstream proxy are available. SOCKS5, authentication, and bypass entry count follow Rockxy feature limits."
                )
            )
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var store = UpstreamProxyStore.shared
    @State private var selectedProtocol: ExternalProxyProtocolSelection = .http
    @State private var isEnabled = false
    @State private var host = ""
    @State private var port = "8080"
    @State private var pacURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var usesAuthentication = false
    @State private var bypassText = ""
    @State private var bypassLocalhost = true
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false
    @State private var showHelp = false

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var httpServerLabel: String {
        switch selectedProtocol {
        case .https:
            String(localized: "HTTPS Proxy Server:")
        case .automatic,
             .http,
             .socks5:
            String(localized: "HTTP Proxy Server:")
        }
    }

    private var httpServerPlaceholder: String {
        switch selectedProtocol {
        case .https:
            String(localized: "HTTPS Proxy Server:")
        case .automatic,
             .http,
             .socks5:
            String(localized: "HTTP Proxy Server:")
        }
    }

    private var protocolList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Select a protocol to configure:"))
                .font(toolMetrics.font())

            VStack(spacing: 0) {
                ForEach(ExternalProxyProtocolSelection.allCases) { row in
                    Button {
                        select(row)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: checkboxSymbol(for: row))
                                .font(toolMetrics.font(weight: .medium))
                                .foregroundStyle(
                                    selectedProtocol == row ? Color.white : Color(nsColor: .tertiaryLabelColor)
                                )
                                .frame(width: 18)

                            Text(row.displayName)
                                .font(toolMetrics.font(weight: selectedProtocol == row ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)

                            if row == .socks5, !store.canSelectSOCKS5 {
                                Image(systemName: "lock.fill")
                                    .font(toolMetrics.metadataFont())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .foregroundStyle(rowForeground(row))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(selectedProtocol == row ? Color.accentColor : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: toolMetrics.fieldWidth(350), height: 230, alignment: .top)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }

    @ViewBuilder private var configurationPanel: some View {
        switch selectedProtocol {
        case .automatic:
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Proxy Configuration URL:"))
                    .font(toolMetrics.font())
                TextField(String(localized: "http://my-server.com/proxy.pac"), text: $pacURL)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font())
                    .frame(maxWidth: toolMetrics.fieldWidth(470), minHeight: toolMetrics.formControlHeight)
                Text(
                    String(
                        localized: "If your network administrator provided you with the address of an automatic proxy configuration (.pac) file, enter it above."
                    )
                )
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .http,
             .https:
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    labeledTextField(httpServerLabel, placeholder: httpServerPlaceholder, text: $host)
                    labeledTextField(String(localized: "Port:"), placeholder: "8080", text: $port, width: 96)
                }

                Toggle(String(localized: "Proxy server requires password"), isOn: $usesAuthentication)
                    .toggleStyle(.checkbox)
                    .disabled(!store.canEnableAuthentication)

                if !store.canEnableAuthentication {
                    PolicyLockNotice(
                        title: String(localized: "Authentication unavailable"),
                        message: String(
                            localized: "Authentication is available in the Rockxy Pro. Credentials are not saved."
                        )
                    )
                } else if usesAuthentication {
                    HStack(spacing: 12) {
                        labeledTextField(String(localized: "Username:"), text: $username)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Password:"))
                                .font(toolMetrics.font())
                            SecureField(String(localized: "Password"), text: $password)
                                .textFieldStyle(.roundedBorder)
                                .font(toolMetrics.font())
                                .frame(minHeight: toolMetrics.formControlHeight)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .socks5:
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "SOCKS Proxy Server"))
                        .font(toolMetrics.font())
                    HStack(spacing: 8) {
                        TextField(String(localized: "127.0.0.1"), text: $host)
                            .textFieldStyle(.roundedBorder)
                            .font(toolMetrics.font())
                            .frame(maxWidth: toolMetrics.fieldWidth(390), minHeight: toolMetrics.formControlHeight)
                            .disabled(!store.canSelectSOCKS5)
                        Text(":")
                            .font(toolMetrics.font(weight: .semibold))
                        TextField(String(localized: "8080"), text: $port)
                            .textFieldStyle(.roundedBorder)
                            .font(toolMetrics.font(monospaced: true))
                            .frame(width: toolMetrics.fieldWidth(86))
                            .frame(minHeight: toolMetrics.formControlHeight)
                            .disabled(!store.canSelectSOCKS5)
                    }
                }

                Toggle(String(localized: "Proxy Server requires password"), isOn: $usesAuthentication)
                    .toggleStyle(.checkbox)
                    .disabled(true)

                HStack(spacing: 12) {
                    Text(String(localized: "Username:"))
                        .foregroundStyle(.secondary)
                        .frame(width: toolMetrics.formCompactLabelWidth, alignment: .leading)
                    TextField("", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)
                        .disabled(true)
                }

                HStack(spacing: 12) {
                    Text(String(localized: "Password:"))
                        .foregroundStyle(.secondary)
                        .frame(width: toolMetrics.formCompactLabelWidth, alignment: .leading)
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .frame(minHeight: toolMetrics.formControlHeight)
                        .disabled(true)
                }

                Text(String(localized: "SOCKS Proxy has not supported Authentication yet."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !store.canSelectSOCKS5 {
                    PolicyLockNotice(
                        title: String(localized: "SOCKS5 unavailable"),
                        message: String(localized: "SOCKS5 upstream proxy is unavailable in this build.")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var bypassSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Bypass List for External Proxies:"))
                    .font(toolMetrics.font())
                Spacer()
                Text(String(localized: "\(store.bypassEntriesUsed) of \(store.bypassEntriesLimit) used"))
                    .font(toolMetrics.metadataFont(weight: .medium))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $bypassText)
                .font(toolMetrics.font(monospaced: true))
                .frame(height: 88)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))

            Text(
                String(
                    localized: "Support wildcard (* and ?). Separate by comma. Community baseline allows 3 bypass entries."
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Toggle(String(localized: "Always bypass external proxies for localhost"), isOn: $bypassLocalhost)
                .toggleStyle(.checkbox)
        }
    }

    private func labeledTextField(
        _ title: String,
        placeholder: String? = nil,
        text: Binding<String>,
        width: CGFloat? = nil
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(toolMetrics.font())
            TextField(placeholder ?? title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font())
                .frame(width: width.map { toolMetrics.fieldWidth($0) })
                .frame(minHeight: toolMetrics.formControlHeight)
        }
    }

    private func select(_ row: ExternalProxyProtocolSelection) {
        selectedProtocol = row
        if row == .socks5, host.isEmpty {
            host = "127.0.0.1"
        }
        if port.isEmpty {
            port = "8080"
        }
        statusMessage = nil
        statusIsError = false
    }

    private func rowForeground(_ row: ExternalProxyProtocolSelection) -> Color {
        if selectedProtocol == row {
            return .white
        }
        return .primary
    }

    private func checkboxSymbol(for row: ExternalProxyProtocolSelection) -> String {
        selectedProtocol == row ? "checkmark.square.fill" : "square.fill"
    }

    private func loadDraft() {
        let configuration = store.configuration
        selectedProtocol = ExternalProxyProtocolSelection(configuration.type)
        isEnabled = configuration.isEnabled
        host = configuration.host
        port = "\(configuration.port)"
        username = configuration.username ?? ""
        pacURL = configuration.pacURL ?? ""
        usesAuthentication = configuration.hasCredentials
        bypassText = configuration.bypassHostPatterns.joined(separator: ", ")
        bypassLocalhost = configuration.bypassLocalhost
    }

    private func makeDraft() -> ExternalProxySettingsDraft {
        ExternalProxySettingsDraft(
            isEnabled: isEnabled,
            selectedProtocol: selectedProtocol,
            host: host,
            portText: port,
            pacURL: pacURL,
            usesAuthentication: usesAuthentication,
            username: username,
            password: password,
            bypassText: bypassText,
            bypassLocalhost: bypassLocalhost
        )
    }

    private func saveAndDismiss() {
        do {
            try saveDraft()
            dismiss()
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func saveDraft() throws {
        let draft = makeDraft()
        let configuration = try draft.configuration()
        let credentials = draft.credentials()
        try store.saveConfiguration(configuration, credentials: credentials)
        statusMessage = String(localized: "External Proxy settings saved.")
        statusIsError = false
    }

    private func testConnection() {
        Task {
            isTesting = true
            defer { isTesting = false }
            do {
                try saveDraft()
                let result = await store.testConnection()
                switch result {
                case let .success(testResult):
                    statusMessage = testResult.displayMessage
                    statusIsError = false
                case let .failure(error):
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }
}

// MARK: - StatusDisclosure

private struct StatusDisclosure: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(message)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(isError ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - PolicyLockNotice

struct PolicyLockNotice: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(toolMetrics.metadataFont(weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(toolMetrics.secondaryFont(weight: .semibold))
                Text(message)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

private extension UpstreamProxyTestResult {
    var displayMessage: String {
        let milliseconds = duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000
        let typeName = resolvedPACRoute?.displayName ?? negotiatedType?.displayName ?? String(localized: "Direct")
        return String(localized: "Connected to \(targetHost):\(targetPort) through \(typeName) in \(milliseconds) ms.")
    }
}
