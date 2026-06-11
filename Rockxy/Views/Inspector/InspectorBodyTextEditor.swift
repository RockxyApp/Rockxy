import AppKit
import SwiftUI

/// NSTextView-backed body editor used by the inspector.
/// Shows JSON/text payloads with code-like selection, cursor placement, line numbers,
/// horizontal scrolling, and lightweight syntax coloring.
struct InspectorBodyTextEditor: NSViewRepresentable {
    let text: String
    var editorID: String = UUID().uuidString
    var editorSettings = InspectorTextEditorSettings()
    var highlightContext: InspectorHighlightContext = .empty

    init(
        text: String,
        editorID: String = UUID().uuidString,
        editorSettings: InspectorTextEditorSettings = InspectorTextEditorSettings(),
        highlightContext: InspectorHighlightContext = .empty
    ) {
        self.text = text
        self.editorID = editorID
        self.editorSettings = editorSettings
        self.highlightContext = highlightContext
    }

    init(text: String, fontSize: CGFloat, highlightContext: InspectorHighlightContext = .empty) {
        self.init(
            text: text,
            editorSettings: InspectorTextEditorSettings(fontSize: Int(fontSize)),
            highlightContext: highlightContext
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = makeScrollView(context: context)
        context.coordinator.editorID = editorID
        context.coordinator.scrollView = scrollView
        configure(scrollView)
        apply(text, to: scrollView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        applyUpdate(to: nsView, coordinator: context.coordinator)
    }

    // MARK: Internal

    func applyUpdate(to nsView: NSScrollView, coordinator: Coordinator) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        coordinator.editorID = editorID
        coordinator.scrollView = nsView

        let textChanged = textView.string != text
        let settingsChanged = coordinator.lastEditorSettings != editorSettings
        let highlightChanged = coordinator.lastHighlightIdentity != highlightContext.identity

        if textChanged {
            let selectedRange = textView.selectedRange()
            let visibleOrigin = nsView.contentView.bounds.origin
            apply(text, to: nsView, coordinator: coordinator)
            textView.setSelectedRange(clamped(range: selectedRange, length: (text as NSString).length))
            restoreVisibleOrigin(visibleOrigin, in: nsView)
        } else if settingsChanged {
            let selectedRange = textView.selectedRange()
            let visibleOrigin = nsView.contentView.bounds.origin
            applyEditorSettings(to: nsView)
            coordinator.lastEditorSettings = editorSettings
            textView.setSelectedRange(clamped(range: selectedRange, length: (text as NSString).length))
            restoreVisibleOrigin(visibleOrigin, in: nsView)
        } else if highlightChanged {
            coordinator.scheduleHighlight(
                text: text,
                editorSettings: editorSettings,
                highlightContext: highlightContext,
                in: nsView
            )
        }
    }

    final class Coordinator {
        var highlightTask: Task<Void, Never>?
        var lastHighlightIdentity = ""
        var lastEditorSettings = InspectorTextEditorSettings()
        var editorID = ""
        weak var scrollView: NSScrollView?
        private var scrollObserver: NSObjectProtocol?
        private var previewPopover: NSPopover?

        init() {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: .inspectorTextMinimapScrollRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleMinimapScroll(notification)
                }
            }
        }

        deinit {
            highlightTask?.cancel()
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        @MainActor
        func showPreview(action: QuickPreviewAction, selection: String, relativeTo view: NSView) {
            let result = QuickPreviewDetector.preview(selection: selection, action: action)
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 520, height: 360)
            popover.contentViewController = NSHostingController(rootView: QuickPreviewPopoverView(result: result))
            previewPopover = popover
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }

        @MainActor
        func scheduleHighlight(
            text: String,
            editorSettings: InspectorTextEditorSettings,
            highlightContext: InspectorHighlightContext,
            in scrollView: NSScrollView
        ) {
            highlightTask?.cancel()
            lastHighlightIdentity = highlightContext.identity
            lastEditorSettings = editorSettings

            highlightTask = Task { [weak scrollView] in
                let spans = await Task.detached(priority: .utility) {
                    Self.highlightSpans(for: text)
                }.value
                let matchRanges = highlightContext.matchRanges(in: text, limit: 500)

                guard !Task.isCancelled,
                      let scrollView,
                      let textView = scrollView.documentView as? NSTextView,
                      textView.string == text else
                {
                    return
                }

                let selectedRange = textView.selectedRange()
                let attributed = Self.baseAttributedString(text, editorSettings: editorSettings)
                for span in spans where NSMaxRange(span.range) <= attributed.length {
                    attributed.addAttribute(.foregroundColor, value: span.role.color, range: span.range)
                }
                for range in matchRanges where NSMaxRange(range) <= attributed.length {
                    attributed.addAttribute(.backgroundColor, value: Theme.Inspector.matchHighlightNS, range: range)
                    attributed.addAttribute(.foregroundColor, value: Theme.Inspector.matchHighlightTextNS, range: range)
                }
                textView.textStorage?.setAttributedString(attributed)
                textView.setSelectedRange(clamped(range: selectedRange, length: attributed.length))
                (scrollView.verticalRulerView as? ScriptCodeEditorRulerView)?.invalidateLineNumbers()
            }
        }

        private static func baseAttributedString(
            _ text: String,
            editorSettings: InspectorTextEditorSettings
        )
            -> NSMutableAttributedString
        {
            NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: editorSettings.appKitFont,
                    .foregroundColor: NSColor.textColor,
                    .backgroundColor: NSColor.textBackgroundColor,
                    .paragraphStyle: paragraphStyle(for: editorSettings),
                ]
            )
        }

        private static func paragraphStyle(for editorSettings: InspectorTextEditorSettings) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.defaultTabInterval = editorSettings.tabInterval
            return style
        }

        @MainActor
        private func handleMinimapScroll(_ notification: Notification) {
            guard let requestedID = notification.userInfo?["editorID"] as? String,
                  requestedID == editorID,
                  let fraction = notification.userInfo?["fraction"] as? CGFloat,
                  let scrollView,
                  let documentView = scrollView.documentView else
            {
                return
            }
            let visibleHeight = scrollView.contentView.bounds.height
            let maxY = max(0, documentView.bounds.height - visibleHeight + scrollView.contentInsets.bottom)
            let y = min(max(0, fraction), 1) * maxY
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        nonisolated private static func highlightSpans(for text: String) -> [HighlightSpan] {
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            var spans: [HighlightSpan] = []
            appendSpans(#""(?:\\.|[^"\\])*""#, role: .string, text: text, range: fullRange, spans: &spans)
            appendSpans(#""(?:\\.|[^"\\])*"(?=\s*:)"#, role: .key, text: text, range: fullRange, spans: &spans)
            appendSpans(
                #"(?<![\w.])-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#,
                role: .number,
                text: text,
                range: fullRange,
                spans: &spans
            )
            appendSpans(#"\b(?:true|false)\b"#, role: .bool, text: text, range: fullRange, spans: &spans)
            appendSpans(#"\bnull\b"#, role: .null, text: text, range: fullRange, spans: &spans)
            appendSpans(#"[\{\}\[\],:]"#, role: .bracket, text: text, range: fullRange, spans: &spans)
            appendSpans(#"(?m)^HTTP/\d(?:\.\d)?"#, role: .status, text: text, range: fullRange, spans: &spans)
            appendSpans(
                #"(?m)^[A-Za-z0-9!#$%&'*+.^_`|~-]+:"#,
                role: .header,
                text: text,
                range: fullRange,
                spans: &spans
            )
            return spans
        }

        nonisolated private static func appendSpans(
            _ pattern: String,
            role: HighlightRole,
            text: String,
            range: NSRange,
            spans: inout [HighlightSpan]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return
            }
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else {
                    return
                }
                spans.append(HighlightSpan(range: match.range, role: role))
            }
        }

        private func clamped(range: NSRange, length: Int) -> NSRange {
            guard range.location != NSNotFound else {
                return NSRange(location: 0, length: 0)
            }
            let location = min(range.location, length)
            let upperBound = min(range.location + range.length, length)
            return NSRange(location: location, length: max(0, upperBound - location))
        }
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.clipsToBounds = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let ruler = ScriptCodeEditorRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        applyEditorSettings(to: scrollView)
    }

    private func makeScrollView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.clipsToBounds = true
        scrollView.contentView.clipsToBounds = true
        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = false
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = InspectorSelectableTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.previewHandler = { [weak coordinator = context.coordinator] action, selection, view in
            Task { @MainActor in
                coordinator?.showPreview(action: action, selection: selection, relativeTo: view)
            }
        }
        scrollView.documentView = textView
        return scrollView
    }

    private func apply(_ text: String, to scrollView: NSScrollView, coordinator: Coordinator?) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        textView.string = text
        applyEditorSettings(to: scrollView)
        textView.font = editorSettings.appKitFont
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.typingAttributes = [
            .font: editorSettings.appKitFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.textBackgroundColor,
            .paragraphStyle: paragraphStyle(for: editorSettings),
        ]

        if let coordinator {
            coordinator.scheduleHighlight(
                text: text,
                editorSettings: editorSettings,
                highlightContext: highlightContext,
                in: scrollView
            )
        }
        (scrollView.verticalRulerView as? ScriptCodeEditorRulerView)?.invalidateLineNumbers()
    }

    private func applyEditorSettings(to scrollView: NSScrollView) {
        Self.applyEditorSettings(editorSettings, to: scrollView)
    }

    static func applyEditorSettings(_ editorSettings: InspectorTextEditorSettings, to scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        scrollView.clipsToBounds = true
        scrollView.contentView.clipsToBounds = true
        textView.clipsToBounds = true
        scrollView.hasHorizontalScroller = !editorSettings.wordWrap
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: editorSettings.scrollBeyondLastLine ? 160 : 0,
            right: 0
        )

        textView.font = editorSettings.appKitFont
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = !editorSettings.wordWrap
        textView.autoresizingMask = editorSettings.wordWrap ? [.width] : []
        textView.layoutManager?.showsInvisibleCharacters = editorSettings.showInvisibles
        textView.layoutManager?.showsControlCharacters = editorSettings.showInvisibles

        if editorSettings.wordWrap {
            textView.frame.size.width = max(scrollView.contentView.bounds.width, 1)
            textView.textContainer?.containerSize = NSSize(
                width: max(scrollView.contentView.bounds.width, 0),
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = true
        } else {
            textView.frame.size.width = max(textView.frame.width, scrollView.contentView.bounds.width)
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = false
        }
        scrollView.tile()
        scrollView.verticalRulerView?.needsDisplay = true
        applyTextStorageSettings(editorSettings, to: textView)
        textView.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textView.string.utf16.count), actualCharacterRange: nil)
        textView.needsDisplay = true
    }

    private static func applyTextStorageSettings(_ editorSettings: InspectorTextEditorSettings, to textView: NSTextView) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.defaultTabInterval = editorSettings.tabInterval
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.typingAttributes = [
            .font: editorSettings.appKitFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.textBackgroundColor,
            .paragraphStyle: paragraphStyle,
        ]
        guard fullRange.length > 0, let textStorage = textView.textStorage else {
            return
        }
        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: editorSettings.appKitFont,
            .paragraphStyle: paragraphStyle,
        ], range: fullRange)
        textStorage.endEditing()
    }

    private func paragraphStyle(for editorSettings: InspectorTextEditorSettings) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.defaultTabInterval = editorSettings.tabInterval
        return style
    }

    private func restoreVisibleOrigin(_ origin: NSPoint, in scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        let documentHeight = scrollView.documentView?.bounds.height ?? clipView.bounds.height
        let maxY = max(0, documentHeight - clipView.bounds.height + scrollView.contentInsets.bottom)
        let restoredOrigin = NSPoint(
            x: max(0, origin.x),
            y: min(max(0, origin.y), maxY)
        )
        clipView.scroll(to: restoredOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private struct HighlightSpan: Sendable {
        let range: NSRange
        let role: HighlightRole
    }

    private enum HighlightRole: Sendable {
        case string
        case key
        case number
        case bool
        case null
        case bracket
        case status
        case header

        @MainActor var color: NSColor {
            switch self {
            case .string: Theme.JSON.stringNS
            case .key: Theme.JSON.keyNS
            case .number: Theme.JSON.numberNS
            case .bool: Theme.JSON.boolNS
            case .null: Theme.JSON.nullNS
            case .bracket: Theme.JSON.bracketNS
            case .status: Theme.JSON.statusNS
            case .header: Theme.JSON.headerNS
            }
        }
    }

    private func clamped(range: NSRange, length: Int) -> NSRange {
        guard range.location != NSNotFound else {
            return NSRange(location: 0, length: 0)
        }
        let location = min(range.location, length)
        let upperBound = min(range.location + range.length, length)
        return NSRange(location: location, length: max(0, upperBound - location))
    }
}

// MARK: - InspectorSelectableTextView

final class InspectorSelectableTextView: NSTextView {
    var previewHandler: ((QuickPreviewAction, String, NSView) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let selected = selectedText
        let actions = QuickPreviewDetector.availableActions(for: selected)
        guard !actions.isEmpty else {
            return menu
        }

        if menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }

        let submenu = NSMenu()
        for action in actions {
            let item = NSMenuItem(title: action.displayName, action: #selector(handleQuickPreview(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            submenu.addItem(item)
        }

        let parent = NSMenuItem(
            title: String(localized: "Text Selection: View as"),
            action: nil,
            keyEquivalent: ""
        )
        parent.submenu = submenu
        menu.addItem(parent)
        return menu
    }

    private var selectedText: String {
        let range = selectedRange()
        guard range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= (string as NSString).length else
        {
            return ""
        }
        return (string as NSString).substring(with: range)
    }

    @objc private func handleQuickPreview(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = QuickPreviewAction(rawValue: rawValue) else
        {
            return
        }
        previewHandler?(action, selectedText, self)
    }
}

// MARK: - AsyncInspectorTextEditor

struct AsyncInspectorTextEditor: View {
    let renderID: String
    var highlightContext: InspectorHighlightContext = .empty
    let render: @Sendable () -> InspectorTextRenderResult

    var body: some View {
        Group {
            switch state {
            case .loading:
                InspectorLoadingStateView(title: String(localized: "Rendering Body..."))
            case let .loaded(result):
                loadedContent(result)
            }
        }
        .task(id: renderID) {
            await renderCurrentText()
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var state: InspectorTextLoadState = .loading

    @ViewBuilder
    private func loadedContent(_ result: InspectorTextRenderResult) -> some View {
        switch result {
        case let .text(text):
            let editorSettings = metrics.inspectorTextEditorSettings
            HStack(spacing: 0) {
                InspectorBodyTextEditor(
                    text: text,
                    editorID: renderID,
                    editorSettings: editorSettings,
                    highlightContext: highlightContext
                )
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if editorSettings.showMinimap {
                    InspectorTextMinimapView(text: text, editorID: renderID)
                        .frame(width: 48)
                        .transition(.opacity)
                }
            }
        case let .unavailable(title, systemImage, description):
            InspectorEmptyStateView(title, systemImage: systemImage, description: description)
        }
    }

    @MainActor
    private func renderCurrentText() async {
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

// MARK: - InspectorTextMinimapView

struct InspectorTextMinimapView: View {
    let text: String
    let editorID: String

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let lines = sampledLines
                guard !lines.isEmpty else {
                    return
                }
                let rowHeight = max(1, size.height / CGFloat(lines.count))
                for (index, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let ratio = min(1, CGFloat(trimmed.count) / 120)
                    let width = max(6, ratio * (size.width - 10))
                    let rect = CGRect(
                        x: 5,
                        y: CGFloat(index) * rowHeight,
                        width: width,
                        height: max(1, rowHeight * 0.55)
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.secondary.opacity(0.36)))
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.48))
            .overlay(alignment: .leading) {
                Divider()
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.y / max(proxy.size.height, 1), 0), 1)
                        NotificationCenter.default.post(
                            name: .inspectorTextMinimapScrollRequested,
                            object: nil,
                            userInfo: ["editorID": editorID, "fraction": fraction]
                        )
                    }
            )
            .help(String(localized: "Click or drag to scroll body text"))
        }
    }

    private var sampledLines: [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > Self.maxLines else {
            return lines
        }
        let step = max(1, lines.count / Self.maxLines)
        return stride(from: 0, to: lines.count, by: step).map { lines[$0] }
    }

    private static let maxLines = 900
}

private extension Notification.Name {
    static let inspectorTextMinimapScrollRequested = Notification.Name("InspectorTextMinimapScrollRequested")
}

// MARK: - AsyncHexDumpView

struct AsyncHexDumpView: View {
    let data: Data
    let renderID: String

    var body: some View {
        Group {
            switch state {
            case .loading:
                InspectorLoadingStateView(title: String(localized: "Rendering Hex..."))
            case let .loaded(text):
                HexDumpView(hexText: text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task(id: renderID) {
            await renderCurrentHex()
        }
    }

    @State private var state: AsyncHexDumpState = .loading

    @MainActor
    private func renderCurrentHex() async {
        state = .loading
        let text = await Task.detached(priority: .userInitiated) {
            PreviewRenderer.formatHexDump(data)
        }.value
        guard !Task.isCancelled else {
            return
        }
        state = .loaded(text)
    }
}

// MARK: - InspectorLoadingStateView

struct InspectorLoadingStateView: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.system(size: metrics.controlFontSize))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}

// MARK: - InspectorTextRenderResult

enum InspectorTextRenderResult: Sendable {
    case text(String)
    case unavailable(title: String, systemImage: String, description: String?)
}

// MARK: - InspectorTextLoadState

private enum InspectorTextLoadState: Sendable {
    case loading
    case loaded(InspectorTextRenderResult)
}

// MARK: - AsyncHexDumpState

private enum AsyncHexDumpState: Sendable {
    case loading
    case loaded(String)
}

// MARK: - InspectorTransactionSnapshot

struct InspectorTransactionSnapshot: Sendable {
    let id: UUID
    let request: InspectorRequestSnapshot
    let response: InspectorResponseSnapshot?

    init(transaction: HTTPTransaction) {
        id = transaction.id
        request = InspectorRequestSnapshot(request: transaction.request)
        response = transaction.response.map(InspectorResponseSnapshot.init(response:))
    }
}

// MARK: - InspectorRequestSnapshot

struct InspectorRequestSnapshot: Sendable {
    let method: String
    let path: String
    let host: String
    let httpVersion: String
    let headers: [InspectorHeaderSnapshot]
    let body: Data?

    init(request: HTTPRequestData) {
        method = request.method
        path = request.path
        host = request.host
        httpVersion = request.httpVersion
        headers = request.headers.map(InspectorHeaderSnapshot.init(header:))
        body = request.body
    }
}

// MARK: - InspectorResponseSnapshot

struct InspectorResponseSnapshot: Sendable {
    let statusCode: Int
    let statusMessage: String
    let headers: [InspectorHeaderSnapshot]
    let body: Data?
    let contentType: ContentType?

    init(response: HTTPResponseData) {
        statusCode = response.statusCode
        statusMessage = response.statusMessage
        headers = response.headers.map(InspectorHeaderSnapshot.init(header:))
        body = response.body
        contentType = response.contentType
    }
}

// MARK: - InspectorHeaderSnapshot

struct InspectorHeaderSnapshot: Sendable {
    let name: String
    let value: String

    init(header: HTTPHeader) {
        name = header.name
        value = header.value
    }
}

// MARK: - InspectorPayloadFormatter

enum InspectorPayloadFormatter {
    static func rawRequest(_ request: InspectorRequestSnapshot) -> String {
        var raw = "\(request.method) \(request.path) \(request.httpVersion)\r\n"
        raw += "Host: \(request.host)\r\n"
        for header in request.headers {
            raw += "\(header.name): \(header.value)\r\n"
        }
        raw += "\r\n"
        if let body = request.body, let bodyString = String(data: body, encoding: .utf8) {
            raw += bodyString
        }
        return raw
    }

    static func rawResponse(_ response: InspectorResponseSnapshot?) -> String? {
        guard let response else {
            return nil
        }
        var raw = "HTTP/1.1 \(response.statusCode) \(response.statusMessage)\r\n"
        for header in response.headers {
            raw += "\(header.name): \(header.value)\r\n"
        }
        raw += "\r\n"
        if let body = response.body, let bodyString = String(data: body, encoding: .utf8) {
            raw += bodyString
        }
        return raw
    }

    static func responseDisplayText(body: Data, sortedKeys: Bool) -> String? {
        if let pretty = prettyJSONString(from: body, sortedKeys: sortedKeys) {
            return pretty
        }
        return String(data: body, encoding: .utf8)
    }

    static func requestBodyText(_ body: Data) -> InspectorTextRenderResult {
        if let text = String(data: body, encoding: .utf8) {
            return .text(text)
        }
        return .unavailable(
            title: String(localized: "Binary Body"),
            systemImage: "doc",
            description: SizeFormatter.format(bytes: body.count)
        )
    }

    private static func prettyJSONString(from data: Data, sortedKeys: Bool) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return String(data: data, encoding: .utf8)
        }
        var options: JSONSerialization.WritingOptions = [.prettyPrinted]
        if sortedKeys {
            options.insert(.sortedKeys)
        }
        guard let prettyData = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return String(data: data, encoding: .utf8)
        }
        return String(data: prettyData, encoding: .utf8)
    }
}
