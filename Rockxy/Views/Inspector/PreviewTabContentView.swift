import SwiftUI
import WebKit

// Renders the preview tab content interface for the request and response inspector.

struct PreviewTabContentView: View {
    let tab: PreviewTab
    let transaction: HTTPTransaction
    var beautify: Bool = false

    var body: some View {
        let snapshot = InspectorTransactionSnapshot(transaction: transaction)

        if tab.renderMode == .jsonTree {
            jsonTreePreview(snapshot: snapshot)
        } else {
            AsyncPreviewTabRenderView(
                renderID: renderID(snapshot: snapshot),
                mode: tab.renderMode,
                baseURL: transaction.request.url
            ) {
                Self.renderPreview(tab: tab, snapshot: snapshot, beautify: beautify)
            }
        }
    }

    @ViewBuilder
    private func jsonTreePreview(snapshot: InspectorTransactionSnapshot) -> some View {
        if let data = tab.panel == .request ? snapshot.request.body : snapshot.response?.body {
            JSONTreeView(data: data)
                .id("\(snapshot.id.uuidString)-\(tab.id.uuidString)")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Preview"), systemImage: "doc.text")
            } description: {
                Text(String(localized: "No body data"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func renderID(snapshot: InspectorTransactionSnapshot) -> String {
        let bodyCount = tab.panel == .request
            ? snapshot.request.body?.count ?? 0
            : snapshot.response?.body?.count ?? 0
        return "\(snapshot.id.uuidString)-\(tab.id.uuidString)-\(tab.renderMode.rawValue)-\(beautify)-\(bodyCount)"
    }

    nonisolated private static func renderPreview(
        tab: PreviewTab,
        snapshot: InspectorTransactionSnapshot,
        beautify: Bool
    )
        -> AsyncPreviewResult
    {
        if tab.renderMode == .raw {
            switch tab.panel {
            case .request:
                return .text(InspectorPayloadFormatter.rawRequest(snapshot.request))
            case .response:
                if let rawResponse = InspectorPayloadFormatter.rawResponse(snapshot.response) {
                    return .text(rawResponse)
                }
                return .empty(reason: String(localized: "No response data"))
            }
        }

        let bodyData = tab.panel == .request ? snapshot.request.body : snapshot.response?.body
        switch PreviewRenderer.render(body: bodyData, mode: tab.renderMode, beautify: beautify) {
        case let .text(text):
            return .text(text)
        case let .hex(text):
            return .hex(text)
        case .json:
            return .empty(reason: String(localized: "Body is not valid JSON"))
        case let .imageData(data, _, _):
            return .imageData(data)
        case let .empty(reason):
            return .empty(reason: reason)
        }
    }
}

// MARK: - AsyncPreviewTabRenderView

private struct AsyncPreviewTabRenderView: View {
    let renderID: String
    let mode: PreviewRenderMode
    let baseURL: URL
    let render: @Sendable () -> AsyncPreviewResult

    var body: some View {
        Group {
            switch state {
            case .loading:
                InspectorLoadingStateView(title: String(localized: "Rendering Preview..."))
            case let .loaded(result):
                loadedContent(result)
            }
        }
        .task(id: renderID) {
            await renderCurrentPreview()
        }
    }

    @State private var state: AsyncPreviewLoadState = .loading
    @Environment(\.appUIDisplayMetrics) private var metrics

    @ViewBuilder
    private func loadedContent(_ result: AsyncPreviewResult) -> some View {
        switch result {
        case let .text(text):
            if mode == .htmlPreview {
                HTMLPreviewView(html: text, baseURL: baseURL)
            } else {
                let editorSettings = metrics.inspectorTextEditorSettings
                HStack(spacing: 0) {
                    InspectorBodyTextEditor(
                        text: text,
                        editorID: renderID,
                        editorSettings: editorSettings
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    if editorSettings.showMinimap {
                        InspectorTextMinimapView(text: text, editorID: renderID)
                            .frame(width: 48)
                    }
                }
            }
        case let .hex(text):
            HexDumpView(hexText: text)
        case let .imageData(data):
            ImagePreviewView(data: data)
        case let .empty(reason):
            ContentUnavailableView {
                Label(String(localized: "No Preview"), systemImage: "doc.text")
            } description: {
                Text(reason)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @MainActor
    private func renderCurrentPreview() async {
        state = .loading
        let result = await Task.detached(priority: .userInitiated) {
            render()
        }.value
        guard !Task.isCancelled else {
            return
        }
        state = .loaded(result)
    }
}

// MARK: - AsyncPreviewLoadState

private enum AsyncPreviewLoadState: Sendable {
    case loading
    case loaded(AsyncPreviewResult)
}

// MARK: - AsyncPreviewResult

private enum AsyncPreviewResult: Sendable {
    case text(String)
    case hex(String)
    case imageData(Data)
    case empty(reason: String)
}
