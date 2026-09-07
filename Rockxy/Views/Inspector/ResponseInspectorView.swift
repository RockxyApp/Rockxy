import AppKit
import SwiftUI

// Renders the response inspector interface for the request and response inspector.

// MARK: - ResponseInspectorView

/// Right half of the inspector split view. Provides tabbed access to response-side data:
/// headers, body (with format picker), Set-Cookie headers, auth, and timing breakdown.
/// Also supports optional body preview tabs from PreviewTabStore.
/// Shows protocol-specific tabs alongside ordinary response tabs so multiple inspections can
/// coexist for the same transaction.
struct ResponseInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    let coordinator: MainContentCoordinator
    var previewTabStore: PreviewTabStore
    var highlightContext: InspectorHighlightContext = .empty
    var onOpenToolWindow: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Response", bundle: RockxyLocalization.bundle))
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
        .onChange(of: previewTabStore.responseTabs.map(\.id)) { _, availableTabIDs in
            guard let selectedPreviewTab,
                  InspectorPreviewSelectionReconciler.retainedSelection(
                      selectedPreviewTab,
                      availableTabIDs: availableTabIDs
                  ) == nil else
            {
                return
            }
            self.selectedPreviewTab = nil
            protocolTab = nil
            selectionIntent = .native
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
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var httpsPromptModel: HTTPSInspectionPromptModel? {
        guard transaction.request.method == "CONNECT", transaction.response != nil else {
            return nil
        }
        let canInterceptHTTPS = coordinator.readiness.canInterceptHTTPS
        let domainRuleEnabled = coordinator.isSSLProxyingEnabled(for: transaction.request.host)
        let resolvedApplicationIdentity = transaction.clientApplicationIdentity
            ?? normalizedClientAppName.flatMap(coordinator.observedApplicationIdentity(named:))
        let hostDecryptBlockedReason = coordinator.sslProxyingHostDecryptBlockedReason(
            for: transaction.request.host,
            application: resolvedApplicationIdentity
        )
        let hasRecentTLSRejection = SSLProxyingManager.shared.isAutoPassthrough(
            transaction.request.host,
            clientIdentifier: transaction.tlsClientScopeIdentifier
                ?? resolvedApplicationIdentity?.identifier
        )
        let promptWithoutAppScope = HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: canInterceptHTTPS,
            domainRuleEnabled: domainRuleEnabled,
            hasRecentTLSRejection: hasRecentTLSRejection,
            hostDecryptBlockedReason: hostDecryptBlockedReason,
            appScope: nil
        )
        guard let promptWithoutAppScope,
              promptWithoutAppScope.certificateAction == nil,
              promptWithoutAppScope.insight?.isWarning == false,
              let appName = normalizedClientAppName else
        {
            return promptWithoutAppScope
        }

        let appScope: HTTPSInspectionAppScope = {
            let domains = coordinator.observedDomainsForApp(
                named: appName,
                fallbackDomain: transaction.request.host
            )
            return HTTPSInspectionAppScope(
                name: appName,
                knownHostCount: domains.count,
                enabledHostCount: domains.count(where: coordinator.isSSLProxyingEnabled(for:)),
                identity: resolvedApplicationIdentity,
                isApplicationDecryptReady: resolvedApplicationIdentity.map {
                    coordinator.isSSLProxyingEnabled(for: $0)
                } ?? false,
                isApplicationTunnelActive: resolvedApplicationIdentity.map { identity in
                    SSLProxyingManager.shared.applicationExcludeRules.contains {
                        $0.isEnabled && $0.applicationIdentifier == identity.identifier
                    }
                } ?? false
            )
        }()

        return HTTPSInspectionPromptModel.make(
            transaction: transaction,
            canInterceptHTTPS: canInterceptHTTPS,
            domainRuleEnabled: domainRuleEnabled,
            hasRecentTLSRejection: hasRecentTLSRejection,
            hostDecryptBlockedReason: hostDecryptBlockedReason,
            appScope: appScope
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

    private var tabDescriptors: [InspectorTabDescriptor] {
        var descriptors: [InspectorTabDescriptor] = ResponseInspectorTab
            .availableTabs()
            .map { tab in
                InspectorTabDescriptor(
                    id: "native.\(tab.rawValue)",
                    title: tab.displayName,
                    isActive: protocolTab == nil && selectedPreviewTab == nil && selectedTab == tab
                ) {
                    selectionIntent = .native
                    protocolTab = nil
                    selectedPreviewTab = nil
                    selectedTab = tab
                }
            }

        for (index, tab) in previewTabStore.responseTabs.enumerated() {
            descriptors.append(
                InspectorTabDescriptor(
                    id: "preview.\(tab.id)",
                    title: tab.name,
                    isActive: selectedPreviewTab == tab,
                    startsNewGroup: index == 0
                ) {
                    selectionIntent = .preview
                    protocolTab = nil
                    selectedPreviewTab = tab
                }
            )
        }

        for (index, tab) in ProtocolTabKind.availableTabs(for: transaction).enumerated() {
            descriptors.append(
                InspectorTabDescriptor(
                    id: "protocol.\(String(describing: tab))",
                    title: tab.displayName,
                    isActive: protocolTab == tab,
                    startsNewGroup: index == 0
                ) {
                    selectionIntent = .protocolSpecific
                    protocolTab = tab
                    selectedPreviewTab = nil
                }
            )
        }

        return descriptors
    }

    private var canPrettifyResponseBody: Bool {
        guard let body = transaction.response?.body else {
            return false
        }
        return !body.isEmpty
    }

    private var hasAIInspection: Bool {
        AITrafficDetector.isLikelyAI(transaction: transaction)
    }

    private var inspectorTabBar: some View {
        InspectorTabStrip(tabs: tabDescriptors) {
            inspectorTrailingControls
        }
    }

    private var previewTabMenuButton: some View {
        Button {
            showPreviewPopover.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: metrics.controlFontSize, weight: .medium))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .frame(width: metrics.inspectorTabHeight, height: metrics.inspectorTabHeight)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Preview Tabs", bundle: RockxyLocalization.bundle))
        .popover(isPresented: $showPreviewPopover, arrowEdge: .bottom) {
            PreviewTabPopover(panel: .response, store: previewTabStore)
        }
    }

    private var inspectorTrailingControls: some View {
        HStack(spacing: 4) {
            previewTabMenuButton

            if protocolTab == nil,
               selectedPreviewTab == nil,
               selectedTab == .body
            {
                responseBodyOptionsMenu
            }
        }
    }

    private var responseBodyOptionsMenu: some View {
        Menu {
            Button {
                bodyDisplayMode = .tree
            } label: {
                checkedMenuLabel(
                    String(localized: "Tree View", bundle: RockxyLocalization.bundle),
                    isSelected: bodyDisplayMode == .tree
                )
            }

            Button {
                bodyDisplayMode = .json
            } label: {
                checkedMenuLabel("JSON", isSelected: bodyDisplayMode == .json)
            }

            Button {
                bodyDisplayMode = .raw
            } label: {
                checkedMenuLabel(
                    String(localized: "Raw", bundle: RockxyLocalization.bundle),
                    isSelected: bodyDisplayMode == .raw
                )
            }

            Button {
                bodyDisplayMode = .hex
            } label: {
                checkedMenuLabel("Hex", isSelected: bodyDisplayMode == .hex)
            }

            Divider()

            Menu(String(localized: "Settings", bundle: RockxyLocalization.bundle)) {
                Toggle(String(localized: "Sort JSON Keys", bundle: RockxyLocalization.bundle), isOn: $sortJSONKeys)
            }

            Menu(String(localized: "Format with", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "Prettify JSON", bundle: RockxyLocalization.bundle)) {
                    sortJSONKeys = true
                    bodyDisplayMode = .json
                }
                .disabled(!canPrettifyResponseBody)
            }

            Menu(String(localized: "Open with", bundle: RockxyLocalization.bundle)) {
                Button {
                    openResponseBody(bundleIdentifier: "com.microsoft.VSCode")
                } label: {
                    Label {
                        Text(verbatim: "Code")
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
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
                    Label(
                        String(localized: "Open by System…", bundle: RockxyLocalization.bundle),
                        systemImage: "arrow.up.right.square"
                    )
                }

                Divider()
                Button {
                    showResponseBodyInFinder()
                } label: {
                    Label(
                        String(localized: "Show in Finder…", bundle: RockxyLocalization.bundle),
                        systemImage: "folder"
                    )
                }
            }

            Menu(String(localized: "Export", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "Copy Body", bundle: RockxyLocalization.bundle)) {
                    copyResponseBodyToClipboard()
                }
                Button(String(localized: "Save Body As…", bundle: RockxyLocalization.bundle)) { exportResponseBody() }
            }
        } label: {
            HStack(spacing: 4) {
                Text(bodyDisplayMode.displayName)
                    .font(.system(size: metrics.controlFontSize, weight: .medium))
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
        .help(String(localized: "Response body display options", bundle: RockxyLocalization.bundle))
    }

    private var tabContent: some View {
        Group {
            if let proto = protocolTab {
                switch proto {
                case .ai:
                    AIInspectorView(transaction: transaction)
                case .websocket:
                    WebSocketInspectorView(transaction: transaction)
                case .web3:
                    Web3RPCInspectorView(transaction: transaction)
                case .graphql:
                    GraphQLInspectorView(transaction: transaction)
                case .grpc:
                    GRPCInspectorView(
                        transaction: transaction,
                        onOpenToolWindow: onOpenToolWindow
                    )
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
            case .ai:
                if hasAIInspection {
                    AIInspectorView(transaction: transaction)
                } else {
                    InspectorEmptyStateView(
                        String(localized: "No AI Metadata", bundle: RockxyLocalization.bundle),
                        systemImage: "sparkles",
                        description: String(
                            localized: "This response does not look like captured AI model traffic.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                }
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
                String(localized: "No Response", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.down.circle",
                description: String(localized: "Waiting for response...", bundle: RockxyLocalization.bundle)
            )
        }
    }

    private func checkedMenuLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    @ViewBuilder
    private func responseHeadersView(response: HTTPResponseData) -> some View {
        if response.headers.isEmpty {
            InspectorEmptyStateView(
                String(localized: "No Headers", bundle: RockxyLocalization.bundle),
                systemImage: "list.bullet"
            )
        } else {
            ScrollView {
                HeaderKeyValueTable(
                    headers: response.headers,
                    highlightContext: highlightContext,
                    source: .response,
                    coordinator: coordinator
                )
                .padding()
            }
        }
    }

    @ViewBuilder
    private func responseBodyView(response: HTTPResponseData) -> some View {
        let snapshot = InspectorResponseSnapshot(response: response)
        if bodyDisplayMode == .raw {
            responseRawView()
        } else if let body = responseBody(for: bodyDisplayMode, snapshot: snapshot), !body.isEmpty {
            switch bodyDisplayMode {
            case .tree:
                JSONTreeView(data: body)
                    .id(transaction.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .json:
                responseCodeEditor(for: body)
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
                String(localized: "Empty Body", bundle: RockxyLocalization.bundle),
                systemImage: "doc",
                description: String(localized: "The response body is empty.", bundle: RockxyLocalization.bundle)
            )
        } else {
            InspectorEmptyStateView(
                String(localized: "No Body", bundle: RockxyLocalization.bundle),
                systemImage: "doc",
                description: String(localized: "This response has no body", bundle: RockxyLocalization.bundle)
            )
        }
    }

    @ViewBuilder
    private func responseRawView() -> some View {
        let snapshot = InspectorTransactionSnapshot(transaction: transaction)
        AsyncInspectorTextEditor(
            renderID: "\(snapshot.id.uuidString)-response-raw-\(snapshot.response?.body?.count ?? 0)-\(snapshot.response?.displayBody?.count ?? 0)",
            highlightContext: highlightContext
        ) {
            if let text = InspectorPayloadFormatter.rawResponse(snapshot.response) {
                return .text(text)
            }
            return .unavailable(
                title: String(localized: "No Response", bundle: RockxyLocalization.bundle),
                systemImage: "arrow.down.circle",
                description: String(localized: "Waiting for response...", bundle: RockxyLocalization.bundle)
            )
        }
    }

    @ViewBuilder
    private func responseCodeEditor(for body: Data) -> some View {
        let sortedKeys = sortJSONKeys
        AsyncInspectorTextEditor(
            renderID: "\(transaction.id.uuidString)-response-json-\(sortedKeys)-\(body.count)",
            highlightContext: highlightContext
        ) {
            if let text = InspectorPayloadFormatter.responseDisplayText(body: body, sortedKeys: sortedKeys) {
                return .text(text)
            }
            return .unavailable(
                title: String(localized: "Binary Body", bundle: RockxyLocalization.bundle),
                systemImage: "doc",
                description: SizeFormatter.format(bytes: body.count)
            )
        }
    }

    private func encryptedHTTPSPrompt(_ prompt: HTTPSInspectionPromptModel) -> some View {
        HTTPSInspectionPromptView(prompt: prompt, onAction: handleHTTPSPromptAction)
            .id(transaction.id)
    }

    private func responseBody(for mode: ResponseBodyDisplayMode, snapshot: InspectorResponseSnapshot) -> Data? {
        switch mode {
        case .hex:
            snapshot.body
        case .tree,
             .json,
             .raw:
            snapshot.displayBody
        }
    }

    private func handleHTTPSPromptAction(_ action: HTTPSInspectionPromptAction) {
        switch action {
        case .installCertificate:
            coordinator.installAndTrustCertificateFromInspector()
        case let .enableDomain(domain):
            coordinator.enableSSLProxyingFromInspector(for: domain)
        case let .retryDomain(domain):
            coordinator.retrySSLProxyingFromInspector(for: domain)
        case let .enableApp(appName, fallbackDomain):
            coordinator.enableSSLProxyingFromInspector(forAppNamed: appName, fallbackDomain: fallbackDomain)
        case let .setApplication(identity, listType):
            coordinator.setSSLProxyingFromInspector(
                for: identity,
                listType: listType,
                fallbackDomain: transaction.request.host
            )
        case .openSSLProxyingList:
            onOpenToolWindow("sslProxyingList")
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
               ProtocolTabKind.hasDetectedSignal(protocolTab, in: transaction)
            {
                return
            }
            protocolTab = ProtocolTabKind.defaultFor(transaction)
            if protocolTab == nil {
                selectionIntent = .native
            }
        }
    }

    private func bodyDisplayText(for response: HTTPResponseData) -> String? {
        guard let body = InspectorResponseSnapshot(response: response).displayBody else {
            return nil
        }
        if let pretty = prettyJSONString(from: body, sortedKeys: sortJSONKeys) {
            return pretty
        }
        return String(data: body, encoding: .utf8)
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
            let data = bodyDisplayText(for: response)
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
        let text = bodyDisplayText(for: response) ?? SizeFormatter.format(bytes: body.count)
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

// MARK: - ResponseBodyDisplayMode

private enum ResponseBodyDisplayMode {
    case tree
    case json
    case raw
    case hex

    // MARK: Internal

    var displayName: String {
        switch self {
        case .tree: String(localized: "Tree View", bundle: RockxyLocalization.bundle)
        case .json: "JSON"
        case .raw: String(localized: "Raw", bundle: RockxyLocalization.bundle)
        case .hex: "Hex"
        }
    }
}

// MARK: - ResponseSelectionIntent

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
    case retryDomain(String)
    case enableApp(String, fallbackDomain: String?)
    case setApplication(ClientApplicationIdentity, SSLProxyingListType)
    case openSSLProxyingList
}

// MARK: - HTTPSInspectionAppScope

struct HTTPSInspectionAppScope: Equatable {
    let name: String
    let knownHostCount: Int
    let enabledHostCount: Int
    var identity: ClientApplicationIdentity?
    var isApplicationDecryptReady: Bool
    var isApplicationTunnelActive: Bool

    init(
        name: String,
        knownHostCount: Int,
        enabledHostCount: Int,
        identity: ClientApplicationIdentity? = nil,
        isApplicationDecryptReady: Bool = false,
        isApplicationTunnelActive: Bool = false
    ) {
        self.name = name
        self.knownHostCount = knownHostCount
        self.enabledHostCount = enabledHostCount
        self.identity = identity
        self.isApplicationDecryptReady = isApplicationDecryptReady
        self.isApplicationTunnelActive = isApplicationTunnelActive
    }
}

// MARK: - HTTPSInspectionPromptModel

struct HTTPSInspectionPromptModel: Equatable {
    let host: String
    let insight: HTTPSConnectionInsight?
    let certificateAction: HTTPSInspectionPromptAction?
    let hostScope: HTTPSInspectionScopePresentation?
    let appScope: HTTPSInspectionScopePresentation?

    var requiresCertificateSetup: Bool {
        certificateAction == .installCertificate
    }

    static func make(
        transaction: HTTPTransaction,
        canInterceptHTTPS: Bool,
        domainRuleEnabled: Bool,
        hasRecentTLSRejection: Bool = false,
        hostDecryptBlockedReason: String? = nil,
        appScope: HTTPSInspectionAppScope?
    )
        -> HTTPSInspectionPromptModel?
    {
        guard transaction.request.method == "CONNECT",
              let response = transaction.response else
        {
            return nil
        }

        let host = transaction.request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return nil
        }

        let hasTLSRejectionEvidence = transaction.isTLSFailure || hasRecentTLSRejection
        guard hasTLSRejectionEvidence || (200 ... 299).contains(response.statusCode) else {
            return nil
        }

        if !canInterceptHTTPS {
            return HTTPSInspectionPromptModel(
                host: host,
                insight: nil,
                certificateAction: .installCertificate,
                hostScope: nil,
                appScope: nil
            )
        }

        return HTTPSInspectionPromptModel(
            host: host,
            insight: hasTLSRejectionEvidence ? .tlsInterceptionRejected : .tunnelEstablished(
                statusCode: response.statusCode
            ),
            certificateAction: nil,
            hostScope: appScope?.isApplicationTunnelActive == true ? nil : .host(
                value: host,
                isReady: domainRuleEnabled,
                requiresRetry: hasTLSRejectionEvidence,
                decryptBlockedReason: hostDecryptBlockedReason
            ),
            appScope: hasTLSRejectionEvidence ? nil : appScope.flatMap { scope in
                if let identity = scope.identity {
                    return .application(
                        identity: identity,
                        isDecryptReady: scope.isApplicationDecryptReady
                    )
                }
                return .appHosts(
                    name: scope.name,
                    enabledHostCount: scope.enabledHostCount,
                    knownHostCount: scope.knownHostCount,
                    currentHostEnabled: domainRuleEnabled,
                    fallbackDomain: host
                )
            }
        )
    }
}

// MARK: - HTTPSConnectionInsight

enum HTTPSConnectionInsight: Equatable {
    case tunnelEstablished(statusCode: Int)
    case tlsInterceptionRejected

    // MARK: Internal

    var title: String {
        switch self {
        case .tunnelEstablished:
            String(localized: "Content Not Inspected", bundle: RockxyLocalization.bundle)
        case .tlsInterceptionRejected:
            String(localized: "Decryption Was Declined", bundle: RockxyLocalization.bundle)
        }
    }

    var summary: String {
        switch self {
        case .tunnelEstablished:
            String(localized: "HTTPS content was not inspected.", bundle: RockxyLocalization.bundle)
        case .tlsInterceptionRejected:
            String(
                localized: "Rockxy kept the app connected by returning this host to a protected encrypted tunnel.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var evidence: String {
        switch self {
        case let .tunnelEstablished(statusCode):
            String(
                localized: "Rockxy received status \(statusCode) and has no recent TLS rejection for this host.",
                bundle: RockxyLocalization.bundle
            )
        case .tlsInterceptionRejected:
            String(
                localized: "The app rejected Rockxy’s TLS handshake for this host. Certificate pinning is possible, but a custom trust policy can produce the same signal.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var nextStep: String {
        switch self {
        case .tunnelEstablished:
            String(localized: "Enable decryption below, then repeat the request.", bundle: RockxyLocalization.bundle)
        case .tlsInterceptionRejected:
            String(
                localized: "Retry decryption and repeat the request. If the app rejects it again, leave this host tunneled.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var systemImage: String {
        switch self {
        case .tunnelEstablished:
            "checkmark.shield"
        case .tlsInterceptionRejected:
            "exclamationmark.shield"
        }
    }

    var isWarning: Bool {
        self == .tlsInterceptionRejected
    }
}

// MARK: - ProtocolTabKind

/// Protocol-specific tab selection for the response inspector.
/// Separate from ResponseInspectorTab to avoid showing protocol tabs for all transactions.
enum ProtocolTabKind: Hashable {
    case ai
    case websocket
    case web3
    case graphql
    case grpc

    // MARK: Internal

    var displayName: String {
        switch self {
        case .ai:
            "AI"
        case .websocket:
            String(localized: "WebSocket", bundle: RockxyLocalization.bundle)
        case .web3:
            String(localized: "Web3", bundle: RockxyLocalization.bundle)
        case .graphql:
            String(localized: "GraphQL", bundle: RockxyLocalization.bundle)
        case .grpc:
            "gRPC"
        }
    }

    /// Returns the protocol/smart tabs that should be visible for a transaction.
    /// AI and Web3 stay visible even without metadata so their inspectors can render empty states.
    static func availableTabs(for transaction: HTTPTransaction) -> [ProtocolTabKind] {
        var tabs: [ProtocolTabKind] = []
        if transaction.webSocketConnection != nil {
            tabs.append(.websocket)
        }
        if transaction.graphQLInfo != nil {
            tabs.append(.graphql)
        }
        tabs.append(.ai)
        tabs.append(.web3)
        tabs.append(.grpc)
        return tabs
    }

    /// Returns the default protocol tab for a transaction, or nil for plain HTTP.
    static func defaultFor(_ transaction: HTTPTransaction) -> ProtocolTabKind? {
        if AITrafficDetector.isLikelyAI(transaction: transaction) {
            return .ai
        }
        if transaction.webSocketConnection != nil {
            return .websocket
        }
        if transaction.web3RPCInfo != nil {
            return .web3
        }
        if transaction.graphQLInfo != nil {
            return .graphql
        }
        if GRPCDetector.isGRPC(transaction: transaction) {
            return .grpc
        }
        return nil
    }

    static func isSupported(_ tab: ProtocolTabKind, by transaction: HTTPTransaction) -> Bool {
        switch tab {
        case .ai:
            true
        case .websocket:
            transaction.webSocketConnection != nil
        case .web3:
            true
        case .graphql:
            transaction.graphQLInfo != nil
        case .grpc:
            true
        }
    }

    static func hasDetectedSignal(_ tab: ProtocolTabKind, in transaction: HTTPTransaction) -> Bool {
        switch tab {
        case .ai:
            AITrafficDetector.isLikelyAI(transaction: transaction)
        case .websocket:
            transaction.webSocketConnection != nil
        case .web3:
            transaction.web3RPCInfo != nil
        case .graphql:
            transaction.graphQLInfo != nil
        case .grpc:
            GRPCDetector.isGRPC(transaction: transaction)
        }
    }
}
