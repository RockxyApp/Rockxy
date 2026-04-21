import SwiftUI

/// Left half of the inspector split view. Provides tabbed access to request-side data:
/// headers, query parameters, body, cookies, raw text, synopsis, and comments.
/// Also supports custom preview tabs from PreviewTabStore.
struct RequestInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var previewTabStore: PreviewTabStore

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Request"))
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
            inspectorTabBar
            Divider()
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Private

    @State private var selectedTab: RequestInspectorTab = .headers
    @State private var selectedPreviewTab: PreviewTab?

    @State private var showPreviewPopover = false

    private var inspectorTabBar: some View {
        InspectorTabStrip {
            ForEach(RequestInspectorTab.allCases, id: \.self) { tab in
                InspectorTabButton(
                    title: tab.displayName,
                    isActive: selectedPreviewTab == nil && selectedTab == tab
                ) {
                    selectedPreviewTab = nil
                    selectedTab = tab
                }
            }

            if !previewTabStore.requestTabs.isEmpty {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 4)

                ForEach(previewTabStore.requestTabs) { tab in
                    InspectorTabButton(
                        title: tab.name,
                        isActive: selectedPreviewTab == tab
                    ) {
                        selectedPreviewTab = tab
                    }
                }
            }
        } trailingContent: {
            previewTabMenuButton
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
        .padding(.leading, 2)
        .popover(isPresented: $showPreviewPopover, arrowEdge: .bottom) {
            PreviewTabPopover(panel: .request, store: previewTabStore)
        }
    }

    @ViewBuilder private var tabContent: some View {
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
            QueryInspectorView(transaction: transaction)
        case .body:
            requestBodyView
        case .cookies:
            CookiesInspectorView(transaction: transaction)
        case .raw:
            requestRawView
        case .synopsis:
            SynopsisInspectorView(transaction: transaction)
        case .comments:
            CommentsTabView(transaction: transaction)
        }
    }

    private var requestHeadersView: some View {
        ScrollView {
            if transaction.request.headers.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Headers"),
                    systemImage: "list.bullet"
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 120, maximum: 200), alignment: .topLeading),
                    GridItem(.flexible(), alignment: .topLeading),
                ], spacing: 4) {
                    ForEach(Array(transaction.request.headers.enumerated()), id: \.offset) { _, header in
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

    private var requestBodyView: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let body = transaction.request.body {
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
                } else {
                    ContentUnavailableView(
                        String(localized: "No Body"),
                        systemImage: "doc",
                        description: Text(String(localized: "This request has no body"))
                    )
                }
            }
        }
    }

    private var requestRawView: some View {
        ScrollView {
            Text(buildRequestRaw())
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding()
        }
    }

    private func buildRequestRaw() -> String {
        let request = transaction.request
        var text = "\(request.method) \(request.path) \(request.httpVersion)\n"
        text += "Host: \(request.host)\n"
        for header in request.headers {
            text += "\(header.name): \(header.value)\n"
        }
        if let body = request.body, let bodyString = String(data: body, encoding: .utf8) {
            text += "\n\(bodyString)"
        }
        return text
    }
}
