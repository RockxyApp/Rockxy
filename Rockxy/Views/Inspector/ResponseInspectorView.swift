import SwiftUI

// Renders the response inspector interface for the request and response inspector.

// MARK: - ResponseInspectorView

/// Right half of the inspector split view. Provides tabbed access to response-side data:
/// headers, body (with format picker), Set-Cookie headers, auth, and timing breakdown.
/// Also supports custom preview tabs from PreviewTabStore.
/// Conditionally shows protocol-specific tabs (WebSocket, GraphQL) when the selected
/// transaction has protocol-specific data.
struct ResponseInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    let coordinator: MainContentCoordinator
    var previewTabStore: PreviewTabStore

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Response"))
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
            inspectorTabBar
            Divider()
            tabContent
        }
        .task(id: transaction.id) {
            autoSelectProtocolTab()
        }
    }

    // MARK: Private

    @State private var selectedTab: ResponseInspectorTab = .headers
    @State private var selectedPreviewTab: PreviewTab?
    @State private var protocolTab: ProtocolTabKind?

    @State private var showPreviewPopover = false
    @Environment(\.openWindow) private var openWindow

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
            appDomains: normalizedClientAppName.map { coordinator.observedDomainsForApp(named: $0) } ?? []
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
        HStack(spacing: 0) {
            ForEach(ResponseInspectorTab.allCases, id: \.self) { tab in
                InspectorTabButton(
                    title: tab.displayName,
                    isActive: protocolTab == nil && selectedPreviewTab == nil && selectedTab == tab
                ) {
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
                        protocolTab = .websocket
                        selectedPreviewTab = nil
                    }
                }

                if transaction.graphQLInfo != nil {
                    InspectorTabButton(
                        title: String(localized: "GraphQL"),
                        isActive: protocolTab == .graphql
                    ) {
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
                        protocolTab = nil
                        selectedPreviewTab = tab
                    }
                }
            }

            previewTabMenuButton

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
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
        .padding(.leading, 2)
        .popover(isPresented: $showPreviewPopover, arrowEdge: .bottom) {
            PreviewTabPopover(panel: .response, store: previewTabStore)
        }
    }

    @ViewBuilder private var tabContent: some View {
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
                SetCookieInspectorView(transaction: transaction)
            case .auth:
                AuthInspectorView(transaction: transaction)
            case .timeline:
                TimingInspectorView(transaction: transaction)
            }
        } else {
            ContentUnavailableView(
                String(localized: "No Response"),
                systemImage: "arrow.down.circle",
                description: Text(String(localized: "Waiting for response..."))
            )
        }
    }

    private func responseHeadersView(response: HTTPResponseData) -> some View {
        ScrollView {
            if response.headers.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Headers"),
                    systemImage: "list.bullet"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 120, maximum: 200), alignment: .topLeading),
                    GridItem(.flexible(), alignment: .topLeading),
                ], spacing: 4) {
                    ForEach(Array(response.headers.enumerated()), id: \.offset) { _, header in
                        Text(header.name)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(header.value)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func responseBodyView(response: HTTPResponseData) -> some View {
        if response.contentType == .json, response.body != nil {
            JSONInspectorView(transaction: transaction)
        } else if let body = response.body {
            ScrollView {
                if let text = String(data: body, encoding: .utf8) {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                } else {
                    Text("\(body.count) bytes (binary)")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        } else {
            ContentUnavailableView(
                String(localized: "No Body"),
                systemImage: "doc",
                description: Text(String(localized: "This response has no body"))
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
        case let .enableApp(appName):
            coordinator.enableSSLProxyingFromInspector(forAppNamed: appName)
        case .openSSLProxyingList:
            openWindow(id: "sslProxyingList")
        }
    }

    private func autoSelectProtocolTab() {
        protocolTab = ProtocolTabKind.defaultFor(transaction)
        if protocolTab != nil {
            selectedPreviewTab = nil
        }
    }
}

// MARK: - HTTPSInspectionPromptAction

enum HTTPSInspectionPromptAction: Equatable {
    case installCertificate
    case enableDomain(String)
    case enableApp(String)
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
        appDomains: [String]
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

        let sanitizedAppDomains = Array(Set(appDomains.filter { !$0.isEmpty })).sorted()

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

        if domainRuleEnabled {
            return HTTPSInspectionPromptModel(
                title: String(localized: "HTTPS Response"),
                message: String(
                    localized: "SSL Proxying is already enabled for this target. Make the request again to see the content."
                ),
                primaryTitle: String(localized: "Open SSL Proxying List"),
                primaryAction: .openSSLProxyingList,
                secondaryTitle: nil,
                secondaryAction: nil
            )
        }

        let message = sslProxyingEnabled ?
            String(localized: "This HTTPS response is encrypted. Enable SSL Proxying to see the content.") :
            String(localized: "SSL Proxying is off. Enable it to see the encrypted content.")

        let appAction: (String?, HTTPSInspectionPromptAction?) = if let appName, !sanitizedAppDomains.isEmpty {
            (
                String(localized: "Enable all domains from \"\(appName)\""),
                .enableApp(appName)
            )
        } else {
            (nil, nil)
        }

        return HTTPSInspectionPromptModel(
            title: String(localized: "HTTPS Response"),
            message: message,
            primaryTitle: String(localized: "Enable only this domain"),
            primaryAction: .enableDomain(host),
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
}
