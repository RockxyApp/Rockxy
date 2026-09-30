import SwiftUI

/// Left half of the inspector split view. Provides tabbed access to request-side data:
/// headers, query parameters, body, cookies, raw text, synopsis, and comments.
/// Also supports optional body preview tabs from PreviewTabStore.
struct RequestInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    let coordinator: MainContentCoordinator
    var previewTabStore: PreviewTabStore
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Request", bundle: RockxyLocalization.bundle))
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
        .onChange(of: transaction.id) {
            if selectedTab == .multipart, !MultipartInspectorView.isApplicable(to: transaction) {
                selectedTab = .body
            }
            if selectedTab == .protobuf, !ProtobufBodyInspection.isApplicable(to: transaction, direction: .request) {
                selectedTab = .body
            }
        }
        .onChange(of: previewTabStore.requestTabs.map(\.id)) { _, availableTabIDs in
            selectedPreviewTab = InspectorPreviewSelectionReconciler.retainedSelection(
                selectedPreviewTab,
                availableTabIDs: availableTabIDs
            )
        }
    }

    // MARK: Private

    @State private var selectedTab: RequestInspectorTab = .headers
    @State private var selectedPreviewTab: PreviewTab?

    @State private var showPreviewPopover = false
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var tabDescriptors: [InspectorTabDescriptor] {
        var descriptors: [InspectorTabDescriptor] = visibleNativeTabs.map { tab in
            InspectorTabDescriptor(
                id: "native.\(tab.rawValue)",
                title: tab.displayName,
                isActive: selectedPreviewTab == nil && selectedTab == tab
            ) {
                selectedPreviewTab = nil
                selectedTab = tab
            }
        }

        for (index, tab) in previewTabStore.requestTabs.enumerated() {
            descriptors.append(
                InspectorTabDescriptor(
                    id: "preview.\(tab.id)",
                    title: tab.name,
                    isActive: selectedPreviewTab == tab,
                    startsNewGroup: index == 0
                ) {
                    selectedPreviewTab = tab
                }
            )
        }

        return descriptors
    }

    /// The Multipart and Protobuf tabs appear only for bodies they can decode.
    private var visibleNativeTabs: [RequestInspectorTab] {
        let showsMultipart = MultipartInspectorView.isApplicable(to: transaction)
        let showsProtobuf = ProtobufBodyInspection.isApplicable(to: transaction, direction: .request)
        return RequestInspectorTab.allCases.filter {
            ($0 != .multipart || showsMultipart) && ($0 != .protobuf || showsProtobuf)
        }
    }

    private var inspectorTabBar: some View {
        InspectorTabStrip(tabs: tabDescriptors) {
            previewTabMenuButton
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
            PreviewTabPopover(panel: .request, store: previewTabStore)
        }
    }

    private var tabContent: some View {
        Group {
            if let previewTab = selectedPreviewTab,
               previewTabStore.requestTabs.contains(where: { $0.id == previewTab.id })
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
        switch selectedTab {
        case .headers:
            requestHeadersView
        case .query:
            QueryInspectorView(transaction: transaction, highlightContext: highlightContext)
        case .body:
            requestBodyView
        case .multipart:
            if MultipartInspectorView.isApplicable(to: transaction) {
                MultipartInspectorView(transaction: transaction)
            } else {
                requestBodyView
            }
        case .protobuf:
            if ProtobufBodyInspection.isApplicable(to: transaction, direction: .request) {
                ProtobufPayloadInspectorView(
                    payload: ProtobufBodyInspection.payload(of: transaction, direction: .request),
                    context: ProtobufBodyInspection.context(of: transaction, direction: .request),
                    payloadID: "\(transaction.id.uuidString)-request"
                )
            } else {
                requestBodyView
            }
        case .cookies:
            CookiesInspectorView(transaction: transaction, highlightContext: highlightContext)
        case .raw:
            requestRawView
        case .synopsis:
            SynopsisInspectorView(transaction: transaction)
        case .connectionLog:
            ConnectionLogInspectorView(transaction: transaction)
        case .comments:
            CommentsTabView(coordinator: coordinator, transaction: transaction)
        }
    }

    @ViewBuilder private var requestHeadersView: some View {
        if transaction.request.headers.isEmpty {
            InspectorEmptyStateView(
                String(localized: "No Headers", bundle: RockxyLocalization.bundle),
                systemImage: "list.bullet"
            )
        } else {
            ScrollView {
                HeaderKeyValueTable(
                    headers: transaction.request.headers,
                    highlightContext: highlightContext,
                    source: .request,
                    coordinator: coordinator
                )
                .padding()
            }
        }
    }

    @ViewBuilder private var requestBodyView: some View {
        if let body = transaction.request.body {
            VStack(spacing: 0) {
                AsyncInspectorTextEditor(
                    renderID: "\(transaction.id.uuidString)-request-body-\(body.count)",
                    highlightContext: highlightContext
                ) {
                    InspectorPayloadFormatter.requestBodyText(body)
                }
                Divider()
                PayloadActionsBar(
                    payload: body,
                    fileStem: "\(transaction.id.uuidString)-request",
                    fileExtension: PayloadActionsBar.fileExtension(for: transaction.request.contentType),
                    suggestedName: "request-body"
                )
            }
        } else {
            InspectorEmptyStateView(
                String(localized: "No Body", bundle: RockxyLocalization.bundle),
                systemImage: "doc",
                description: String(localized: "This request has no body", bundle: RockxyLocalization.bundle)
            )
        }
    }

    private var requestRawView: some View {
        let snapshot = InspectorTransactionSnapshot(transaction: transaction)
        return AsyncInspectorTextEditor(
            renderID: "\(snapshot.id.uuidString)-request-raw-\(snapshot.request.body?.count ?? 0)",
            highlightContext: highlightContext
        ) {
            .text(InspectorPayloadFormatter.rawRequest(snapshot.request))
        }
    }
}
