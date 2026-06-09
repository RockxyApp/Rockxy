import AppKit
import SwiftUI

// Renders the response inspector interface for the request and response inspector.

// MARK: - ResponseInspectorView

/// Right half of the inspector split view. Provides tabbed access to response-side data:
/// headers, body (with format picker), Set-Cookie headers, auth, and timing breakdown.
/// Also supports optional body preview tabs from PreviewTabStore.
/// Conditionally shows protocol-specific tabs (WebSocket, GraphQL) when the selected
/// transaction has protocol-specific data.
struct ResponseInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    let coordinator: MainContentCoordinator
    var previewTabStore: PreviewTabStore
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Response"))
                .font(.system(size: metrics.fontSize, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
            inspectorTabBar
            Divider()
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear.opacity(Double(coordinator.sslProxyingRefreshToken) * 0))
        .task(id: transaction.id) {
            syncInspectorStateForTransaction()
        }
    }

    // MARK: Private

    @State private var selectedTab: ResponseInspectorTab = .headers
    @State private var selectedPreviewTab: PreviewTab?
    @State private var protocolTab: ProtocolTabKind?
    @State private var selectionIntent: ResponseSelectionIntent = .automatic
    @State private var bodyDisplayMode: ResponseBodyDisplayMode = .json
    @State private var sortJSONKeys = true

    @State private var showPreviewPopover = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var hasProtocolTab: Bool {
        transaction.webSocketConnection != nil || transaction.graphQLInfo != nil
    }

    private var httpsPromptModel: HTTPSInspectionPromptModel? {
        HTTPSInspectionPromptModel.make(
            transaction: transaction,
            sslProxyingEnabled: SSLProxyingManager.shared.isEnabled,
            canInterceptHTTPS: coordinator.readiness.canInterceptHTTPS,
            domainRuleEnabled: coordinator.isSSLProxyingEnabled(for: transaction.request.host),
            appName: normalizedClientAppName,
            appRuleEnabled: normalizedClientAppName.map {
                coordinator.isSSLProxyingFullyEnabled(forAppNamed: $0, fallbackDomain: transaction.request.host)
            } ?? false
        )
    }

    private var normalizedClientAppName: String? {
        guard let clientApp = transaction.clientApp?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientApp.isEmpty else
        {
            return nil
        }
        return clientApp
    }

    private var inspectorTabBar: some View {
        InspectorTabStrip {
            ForEach(ResponseInspectorTab.allCases, id: \.self) { tab in
                InspectorTabButton(
                    title: tab.displayName,
                    isActive: protocolTab == nil && selectedPreviewTab == nil && selectedTab == tab
                ) {
                    selectionIntent = .native
                    protocolTab = nil
                    selectedPreviewTab = nil
                    selectedTab = tab
                }
            }

            if hasProtocolTab {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 4)

                if transaction.webSocketConnection != nil {
                    InspectorTabButton(
                        title: String(localized: "WebSocket"),
                        isActive: protocolTab == .websocket
                    ) {
                        selectionIntent = .protocolSpecific
                        protocolTab = .websocket
                        selectedPreviewTab = nil
                    }
                }

                if transaction.graphQLInfo != nil {
                    InspectorTabButton(
                        title: String(localized: "GraphQL"),
                        isActive: protocolTab == .graphql
                    ) {
                        selectionIntent = .protocolSpecific
                        protocolTab = .graphql
                        selectedPreviewTab = nil
                    }
                }
            }

            if !previewTabStore.responseTabs.isEmpty {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 4)

                ForEach(previewTabStore.responseTabs) { tab in
                    InspectorTabButton(
                        title: tab.name,
                        isActive: selectedPreviewTab == tab
                    ) {
                        selectionIntent = .preview
                        protocolTab = nil
                        selectedPreviewTab = tab
                    }
                }
            }

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            previewTabMenuButton
        } trailingContent: {
            inspectorTrailingControls
        }
    }

    private var previewTabMenuButton: some View {
        Button {
            showPreviewPopover.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Preview Tabs"))
        .popover(isPresented: $showPreviewPopover, arrowEdge: .bottom) {
            PreviewTabPopover(panel: .response, store: previewTabStore)
        }
    }

    @ViewBuilder private var inspectorTrailingControls: some View {
        if protocolTab == nil,
           selectedPreviewTab == nil,
           selectedTab == .body
        {
            responseBodyOptionsMenu
        } else {
            EmptyView()
        }
    }

    private var responseBodyOptionsMenu: some View {
        Menu {
            Button {
                bodyDisplayMode = .tree
            } label: {
                checkedMenuLabel(String(localized: "Tree View"), isSelected: bodyDisplayMode == .tree)
            }

            Button {
                bodyDisplayMode = .json
            } label: {
                checkedMenuLabel("JSON", isSelected: bodyDisplayMode == .json)
            }

            Button {
                bodyDisplayMode = .raw
            } label: {
                checkedMenuLabel(String(localized: "Raw"), isSelected: bodyDisplayMode == .raw)
            }

            Button {
                bodyDisplayMode = .hex
            } label: {
                checkedMenuLabel("Hex", isSelected: bodyDisplayMode == .hex)
            }

            Divider()

            Menu(String(localized: "Settings")) {
                Toggle(String(localized: "Sort JSON Keys"), isOn: $sortJSONKeys)
            }

            Menu(String(localized: "Format with")) {
                Button(String(localized: "Prettify JSON")) {
                    sortJSONKeys = true
                    bodyDisplayMode = .json
                }
                .disabled(!canPrettifyResponseBody)
            }

            Menu(String(localized: "Open with")) {
                Button {
                    openResponseBody(bundleIdentifier: "com.microsoft.VSCode")
                } label: {
                    Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    openResponseBody(bundleIdentifier: "com.todesktop.230313mzl4w4u92")
                } label: {
                    Label("Cursor", systemImage: "cursorarrow")
                }

                Button {
                    openResponseBody(bundleIdentifier: "com.apple.TextEdit")
                } label: {
                    Label("TextEdit", systemImage: "doc.text")
                }

                Button {
                    openResponseBody(bundleIdentifier: "com.apple.dt.Xcode")
                } label: {
                    Label("Xcode", systemImage: "hammer")
                }

                Divider()
                Button {
                    openResponseBody(bundleIdentifier: nil)
                } label: {
                    Label(String(localized: "Open by System…"), systemImage: "arrow.up.right.square")
                }

                Divider()
                Button {
                    showResponseBodyInFinder()
                } label: {
                    Label(String(localized: "Show in Finder…"), systemImage: "folder")
                }
            }

            Menu(String(localized: "Export")) {
                Button(String(localized: "Copy Body")) { copyResponseBodyToClipboard() }
                Button(String(localized: "Save Body As…")) { exportResponseBody() }
            }
        } label: {
            HStack(spacing: 4) {
                Text(bodyDisplayMode.displayName)
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: metrics.badgeFontSize, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Response body display options"))
    }

    private func checkedMenuLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    @ViewBuilder private var tabContent: some View {
        Group {
            if let proto = protocolTab {
                switch proto {
                case .websocket:
                    WebSocketInspectorView(transaction: transaction)
                case .graphql:
                    GraphQLInspectorView(transaction: transaction)
                }
            } else if let previewTab = selectedPreviewTab,
                      previewTabStore.responseTabs.contains(where: { $0.id == previewTab.id })
            {
                PreviewTabContentView(
                    tab: previewTab,
                    transaction: transaction,
                    beautify: previewTabStore.autoBeautify
                )
            } else {
                nativeTabContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var nativeTabContent: some View {
        if let prompt = httpsPromptModel, selectedTab != .timeline {
            encryptedHTTPSPrompt(prompt)
        } else if let response = transaction.response {
            switch selectedTab {
            case .headers:
                responseHeadersView(response: response)
            case .body:
                responseBodyView(response: response)
            case .setCookie:
                SetCookieInspectorView(transaction: transaction, highlightContext: highlightContext)
            case .auth:
                AuthInspectorView(transaction: transaction, highlightContext: highlightContext)
            case .timeline:
                TimingInspectorView(transaction: transaction)
            }
        } else {
            InspectorEmptyStateView(
                String(localized: "No Response"),
                systemImage: "arrow.down.circle",
                description: String(localized: "Waiting for response...")
            )
        }
    }

    @ViewBuilder
    private func responseHeadersView(response: HTTPResponseData) -> some View {
        if response.headers.isEmpty {
            InspectorEmptyStateView(
                String(localized: "No Headers"),
                systemImage: "list.bullet"
            )
        } else {
            ScrollView {
                HeaderKeyValueTable(headers: response.headers, highlightContext: highlightContext)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func responseBodyView(response: HTTPResponseData) -> some View {
        if bodyDisplayMode == .raw {
            responseRawView()
        } else if let body = response.body, !body.isEmpty {
            switch bodyDisplayMode {
            case .tree:
                JSONTreeView(data: body)
                    .id(transaction.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .json:
                responseCodeEditor(for: body, response: response)
            case .raw:
                responseRawView()
            case .hex:
                AsyncHexDumpView(
                    data: body,
                    renderID: "\(transaction.id.uuidString)-response-hex-\(body.count)"
                )
            }
        } else if response.body != nil {
            InspectorEmptyStateView(
                String(localized: "Empty Body"),
                systemImage: "doc",
                description: String(localized: "The response body is empty.")
            )
        } else {
            InspectorEmptyStateView(
                String(localized: "No Body"),
                systemImage: "doc",
                description: String(localized: "This response has no body")
            )
        }
    }

    @ViewBuilder
    private func responseRawView() -> some View {
        let snapshot = InspectorTransactionSnapshot(transaction: transaction)
        AsyncInspectorTextEditor(
            renderID: "\(snapshot.id.uuidString)-response-raw-\(snapshot.response?.body?.count ?? 0)",
            highlightContext: highlightContext
        ) {
            if let text = InspectorPayloadFormatter.rawResponse(snapshot.response) {
                return .text(text)
            }
            return .unavailable(
                title: String(localized: "No Response"),
                systemImage: "arrow.down.circle",
                description: String(localized: "Waiting for response...")
            )
        }
    }

    @ViewBuilder
    private func responseCodeEditor(for body: Data, response _: HTTPResponseData) -> some View {
        let sortedKeys = sortJSONKeys
        AsyncInspectorTextEditor(
            renderID: "\(transaction.id.uuidString)-response-json-\(sortedKeys)-\(body.count)",
            highlightContext: highlightContext
        ) {
            if let text = InspectorPayloadFormatter.responseDisplayText(body: body, sortedKeys: sortedKeys) {
                return .text(text)
            }
            return .unavailable(
                title: String(localized: "Binary Body"),
                systemImage: "doc",
                description: SizeFormatter.format(bytes: body.count)
            )
        }
    }

    private func encryptedHTTPSPrompt(_ prompt: HTTPSInspectionPromptModel) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                    Text(prompt.title)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }

                Text(prompt.message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                Button {
                    handleHTTPSPromptAction(prompt.primaryAction)
                } label: {
                    Text(prompt.primaryTitle)
                        .frame(minWidth: 220)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if let secondaryTitle = prompt.secondaryTitle,
                   let secondaryAction = prompt.secondaryAction
                {
                    Text(String(localized: "or"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                    Button {
                        handleHTTPSPromptAction(secondaryAction)
                    } label: {
                        Text(secondaryTitle)
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func handleHTTPSPromptAction(_ action: HTTPSInspectionPromptAction) {
        switch action {
        case .installCertificate:
            coordinator.installAndTrustCertificateFromInspector()
        case let .enableDomain(domain):
            coordinator.enableSSLProxyingFromInspector(for: domain)
        case let .disableDomain(domain):
            coordinator.disableSSLProxyingFromInspector(for: domain)
        case let .enableApp(appName, fallbackDomain):
            coordinator.enableSSLProxyingFromInspector(forAppNamed: appName, fallbackDomain: fallbackDomain)
        case let .disableApp(appName, fallbackDomain):
            coordinator.disableSSLProxyingFromInspector(forAppNamed: appName, fallbackDomain: fallbackDomain)
        case .openSSLProxyingList:
            openWindow(id: "sslProxyingList")
        }
    }

    private func syncInspectorStateForTransaction() {
        if let selectedPreviewTab,
           !previewTabStore.responseTabs.contains(where: { $0.id == selectedPreviewTab.id })
        {
            self.selectedPreviewTab = nil
            selectionIntent = .automatic
        }

        switch selectionIntent {
        case .automatic:
            protocolTab = ProtocolTabKind.defaultFor(transaction)
        case .native,
             .preview:
            protocolTab = nil
        case .protocolSpecific:
            if let protocolTab,
               ProtocolTabKind.isSupported(protocolTab, by: transaction)
            {
                return
            }
            protocolTab = ProtocolTabKind.defaultFor(transaction)
            if protocolTab == nil {
                selectionIntent = .native
            }
        }
    }

    private func bodyDisplayText(for body: Data, response _: HTTPResponseData) -> String? {
        if let pretty = prettyJSONString(from: body, sortedKeys: sortJSONKeys)
        {
            return pretty
        }
        return String(data: body, encoding: .utf8)
    }

    private var canPrettifyResponseBody: Bool {
        guard let body = transaction.response?.body else {
            return false
        }
        return !body.isEmpty
    }

    private func prettyJSONString(from data: Data, sortedKeys: Bool) -> String? {
        InspectorPayloadFormatter.responseDisplayText(body: data, sortedKeys: sortedKeys)
    }

    private func responseBodyTemporaryURL() -> URL? {
        guard let response = transaction.response,
              let body = response.body else
        {
            return nil
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyInspector", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory
                .appendingPathComponent(transaction.id.uuidString)
                .appendingPathExtension(responseBodyFileExtension())
            let data = bodyDisplayText(for: body, response: response)
                .map { Data($0.utf8) } ?? body
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func responseBodyFileExtension() -> String {
        switch transaction.response?.contentType {
        case .json: "json"
        case .xml: "xml"
        case .html: "html"
        case .text: "txt"
        default: "bin"
        }
    }

    private func openResponseBody(bundleIdentifier: String?) {
        guard let url = responseBodyTemporaryURL() else {
            return
        }
        if let bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func showResponseBodyInFinder() {
        guard let url = responseBodyTemporaryURL() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyResponseBodyToClipboard() {
        guard let response = transaction.response,
              let body = response.body else
        {
            return
        }
        let text = bodyDisplayText(for: body, response: response) ?? SizeFormatter.format(bytes: body.count)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportResponseBody() {
        guard let body = transaction.response?.body else {
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "response-body.\(responseBodyFileExtension())"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        try? body.write(to: url)
    }
}

private enum ResponseBodyDisplayMode {
    case tree
    case json
    case raw
    case hex

    var displayName: String {
        switch self {
        case .tree: String(localized: "Tree View")
        case .json: "JSON"
        case .raw: String(localized: "Raw")
        case .hex: "Hex"
        }
    }
}

private enum ResponseSelectionIntent {
    case automatic
    case native
    case protocolSpecific
    case preview
}

// MARK: - HTTPSInspectionPromptAction

enum HTTPSInspectionPromptAction: Equatable {
    case installCertificate
    case enableDomain(String)
    case disableDomain(String)
    case enableApp(String, fallbackDomain: String?)
    case disableApp(String, fallbackDomain: String?)
    case openSSLProxyingList
}

// MARK: - HTTPSInspectionPromptModel

struct HTTPSInspectionPromptModel: Equatable {
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: HTTPSInspectionPromptAction
    let secondaryTitle: String?
    let secondaryAction: HTTPSInspectionPromptAction?

    static func make(
        transaction: HTTPTransaction,
        sslProxyingEnabled: Bool,
        canInterceptHTTPS: Bool,
        domainRuleEnabled: Bool,
        appName: String?,
        appRuleEnabled: Bool
    )
        -> HTTPSInspectionPromptModel?
    {
        guard transaction.request.method == "CONNECT",
              let response = transaction.response,
              response.statusCode == 200,
              !transaction.isTLSFailure else
        {
            return nil
        }

        let host = transaction.request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return nil
        }

        if !canInterceptHTTPS {
            return HTTPSInspectionPromptModel(
                title: String(localized: "HTTPS Response"),
                message: String(
                    localized: "This HTTPS response is encrypted. Install and trust the certificate to see the content."
                ),
                primaryTitle: String(localized: "Install & Trust Certificate"),
                primaryAction: .installCertificate,
                secondaryTitle: nil,
                secondaryAction: nil
            )
        }

        let domainTitle = domainRuleEnabled ?
            String(localized: "Disable only this domain") :
            String(localized: "Enable only this domain")
        let domainAction: HTTPSInspectionPromptAction = domainRuleEnabled ?
            .disableDomain(host) :
            .enableDomain(host)

        let message: String
        if domainRuleEnabled || appRuleEnabled {
            message = String(
                localized: "SSL Proxying is enabled for this HTTPS target. You can adjust the scope below."
            )
        } else if sslProxyingEnabled {
            message = String(localized: "This HTTPS response is encrypted. Enable SSL Proxying to see the content.")
        } else {
            message = String(localized: "SSL Proxying is off. Enable it to see the encrypted content.")
        }

        let appAction: (String?, HTTPSInspectionPromptAction?) = if let appName {
            (
                appRuleEnabled ?
                    String(localized: "Disable all domains from \"\(appName)\"") :
                    String(localized: "Enable all domains from \"\(appName)\""),
                appRuleEnabled ?
                    .disableApp(appName, fallbackDomain: host) :
                    .enableApp(appName, fallbackDomain: host)
            )
        } else {
            (nil, nil)
        }

        return HTTPSInspectionPromptModel(
            title: String(localized: "HTTPS Response"),
            message: message,
            primaryTitle: domainTitle,
            primaryAction: domainAction,
            secondaryTitle: appAction.0,
            secondaryAction: appAction.1
        )
    }
}

// MARK: - ProtocolTabKind

/// Protocol-specific tab selection for the response inspector.
/// Separate from ResponseInspectorTab to avoid showing protocol tabs for all transactions.
enum ProtocolTabKind {
    case websocket
    case graphql

    // MARK: Internal

    /// Returns the default protocol tab for a transaction, or nil for plain HTTP.
    static func defaultFor(_ transaction: HTTPTransaction) -> ProtocolTabKind? {
        if transaction.webSocketConnection != nil {
            return .websocket
        }
        if transaction.graphQLInfo != nil {
            return .graphql
        }
        return nil
    }

    static func isSupported(_ tab: ProtocolTabKind, by transaction: HTTPTransaction) -> Bool {
        switch tab {
        case .websocket:
            transaction.webSocketConnection != nil
        case .graphql:
            transaction.graphQLInfo != nil
        }
    }
}
