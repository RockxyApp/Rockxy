import SwiftUI

// Renders the json tree interface for shared app surfaces.

// MARK: - JSONTreeView

/// Collapsible JSON tree with JSONPath/key/value filtering. Parsing and query evaluation
/// happen off-main and are keyed to the current body/query so stale results are ignored.
struct JSONTreeView: View {
    // MARK: Internal

    let data: Data

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollViewReader { reader in
                    ScrollView([.horizontal, .vertical]) {
                        content
                            .padding(Self.contentPadding)
                            .frame(
                                minWidth: max(0, proxy.size.width - Self.contentPadding * 2),
                                minHeight: max(0, proxy.size.height - Self.contentPadding * 2),
                                alignment: .topLeading
                            )
                    }
                    .onChange(of: selectedMatchPath) { _, path in
                        guard let path else {
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            reader.scrollTo(path, anchor: .center)
                        }
                    }
                }
            }
            Divider()
            filterBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: data) {
            await parseCurrentData()
        }
        .task(id: queryTaskID) {
            await evaluateCurrentQuery()
        }
    }

    // MARK: Private

    private static let contentPadding: CGFloat = 12

    @State private var state: JSONTreeLoadState = .loading
    @State private var filterMode: JSONTreeFilterMode = .jsonPath
    @State private var query = ""
    @State private var queryResult: JSONPathQueryResult = .empty
    @State private var queryError: String?
    @State private var selectedMatchPath: String?

    @FocusState private var isSearchFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var queryTaskID: String {
        switch state {
        case let .parsed(document):
            "\(document.root.path)-\(data.count)-\(filterMode.rawValue)-\(query)"
        default:
            "no-document-\(data.count)-\(filterMode.rawValue)-\(query)"
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Parsing JSON..."))
                    .font(metrics.swiftUIFont())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .parsed(document):
            JSONTreeNodeView(
                node: document.root,
                depth: 0,
                isLast: true,
                filter: activeFilter
            )

        case let .text(text):
            Text(text)
                .font(.system(size: metrics.fontSize, design: .monospaced))
                .textSelection(.enabled)

        case .unavailable:
            Text(String(localized: "Unable to display content"))
                .foregroundStyle(.secondary)
        }
    }

    private var activeFilter: JSONTreeRenderFilter? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, queryError == nil else {
            return nil
        }
        return JSONTreeRenderFilter(
            includedPaths: queryResult.includedPaths,
            matchedPaths: Set(queryResult.matches.map(\.path)),
            selectedPath: selectedMatchPath
        )
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $filterMode) {
                ForEach(JSONTreeFilterMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 118)

            Image(systemName: "magnifyingglass")
                .font(.system(size: metrics.fontSize))
                .foregroundStyle(.secondary)

            TextField(filterMode.placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: metrics.fontSize, design: .monospaced))
                .focused($isSearchFocused)
                .onSubmit {
                    advanceSelection()
                }

            if !query.isEmpty {
                Button {
                    clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "Clear"))
            }

            Divider()
                .frame(height: 14)

            Text(statusText)
                .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                .foregroundStyle(queryError == nil ? Color.secondary : Color.red)
                .frame(minWidth: 86, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .background(keyboardShortcuts)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("") {
                advanceSelection(previous: true)
            }
            .keyboardShortcut(.return, modifiers: .shift)

            Button("") {
                clearQuery()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var statusText: String {
        if let queryError {
            return queryError
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        let suffix = queryResult.isTruncated ? "+" : ""
        return "\(queryResult.matches.count)\(suffix) selected"
    }

    @MainActor
    private func parseCurrentData() async {
        state = .loading
        queryResult = .empty
        queryError = nil
        selectedMatchPath = nil

        let result = try? await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = Self.parse(data)
            try Task.checkCancellation()
            return result
        }.value

        guard let result, !Task.isCancelled else {
            return
        }
        state = result
    }

    @MainActor
    private func evaluateCurrentQuery() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case let .parsed(document) = state, !trimmed.isEmpty else {
            queryResult = .empty
            queryError = nil
            return
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else {
            return
        }

        let mode = filterMode
        let result = await Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                let evaluator = JSONPathEvaluator(document: document)
                let result = try evaluator.search(trimmed, mode: mode)
                try Task.checkCancellation()
                return Result<JSONPathQueryResult, Error>.success(result)
            } catch {
                return .failure(error)
            }
        }.value

        guard !Task.isCancelled else {
            return
        }
        switch result {
        case let .success(value):
            queryResult = value
            queryError = nil
            if let selectedMatchPath,
               value.matches.contains(where: { $0.path == selectedMatchPath })
            {
                self.selectedMatchPath = selectedMatchPath
            } else {
                selectedMatchPath = value.matches.first?.path
            }
        case let .failure(error):
            queryResult = .empty
            queryError = error.localizedDescription
            selectedMatchPath = nil
        }
    }

    private func advanceSelection(previous: Bool = false) {
        guard !queryResult.matches.isEmpty else {
            isSearchFocused = true
            return
        }

        let paths = queryResult.matches.map(\.path)
        let current = selectedMatchPath.flatMap { paths.firstIndex(of: $0) } ?? (previous ? 0 : paths.count - 1)
        let next = previous
            ? (current - 1 + paths.count) % paths.count
            : (current + 1) % paths.count
        selectedMatchPath = paths[next]
        isSearchFocused = true
    }

    private func clearQuery() {
        query = ""
        queryError = nil
        queryResult = .empty
        selectedMatchPath = nil
        isSearchFocused = true
    }

    nonisolated private static func parse(_ data: Data) -> JSONTreeLoadState {
        do {
            return .parsed(try JSONPathDocument(data: data))
        } catch {
            if let text = String(data: data, encoding: .utf8) {
                return .text(text)
            }
            return .unavailable
        }
    }
}

// MARK: - JSONTreeLoadState

private enum JSONTreeLoadState: Sendable {
    case loading
    case parsed(JSONPathDocument)
    case text(String)
    case unavailable
}

// MARK: - JSONTreeRenderFilter

private struct JSONTreeRenderFilter {
    let includedPaths: Set<String>
    let matchedPaths: Set<String>
    let selectedPath: String?

    func includes(_ node: JSONPathNode) -> Bool {
        includedPaths.contains(node.path)
    }

    func isMatch(_ node: JSONPathNode) -> Bool {
        matchedPaths.contains(node.path)
    }

    func isSelected(_ node: JSONPathNode) -> Bool {
        selectedPath == node.path
    }
}

// MARK: - JSONTreeNodeView

private struct JSONTreeNodeView: View {
    // MARK: Internal

    let node: JSONPathNode
    let depth: Int
    let isLast: Bool
    let filter: JSONTreeRenderFilter?

    var body: some View {
        if filter?.includes(node) ?? true {
            switch node.value {
            case let .object(pairs):
                containerView(openBracket: "{", closeBracket: "}", count: pairs.count) {
                    let visible = visibleObjectPairs(pairs)
                    ForEach(Array(visible.enumerated()), id: \.element.value.path) { index, pair in
                        JSONTreeNodeView(
                            node: pair.value,
                            depth: depth + 1,
                            isLast: index == visible.count - 1,
                            filter: filter
                        )
                    }
                }

            case let .array(items):
                containerView(openBracket: "[", closeBracket: "]", count: items.count) {
                    let visible = visibleArrayItems(items)
                    ForEach(Array(visible.enumerated()), id: \.element.path) { index, item in
                        JSONTreeNodeView(
                            node: item,
                            depth: depth + 1,
                            isLast: index == visible.count - 1,
                            filter: filter
                        )
                    }
                }

            case let .string(str):
                leafView {
                    Text("\"\(str)\"")
                        .foregroundStyle(Theme.JSON.string)
                }

            case let .number(num):
                leafView {
                    Text(num)
                        .foregroundStyle(Theme.JSON.number)
                }

            case let .bool(val):
                leafView {
                    Text(val ? "true" : "false")
                        .foregroundStyle(Theme.JSON.bool)
                }

            case .null:
                leafView {
                    Text("null")
                        .foregroundStyle(Theme.JSON.null)
                }
            }
        }
    }

    // MARK: Private

    private static let indentWidth: CGFloat = 16

    @State private var isExpanded = true
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var effectiveExpanded: Bool {
        filter == nil ? isExpanded : true
    }

    private var comma: String {
        isLast ? "" : ","
    }

    @ViewBuilder private var keyLabel: some View {
        if let key = node.key {
            Text("\"\(key)\"")
                .font(.system(size: metrics.fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.JSON.key)
            Text(": ")
                .font(.system(size: metrics.fontSize, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: effectiveExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: metrics.badgeFontSize))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
    }

    private func visibleObjectPairs(_ pairs: [(key: String, value: JSONPathNode)]) -> [(key: String, value: JSONPathNode)] {
        guard let filter else {
            return pairs
        }
        return pairs.filter { filter.includes($0.value) }
    }

    private func visibleArrayItems(_ items: [JSONPathNode]) -> [JSONPathNode] {
        guard let filter else {
            return items
        }
        return items.filter(filter.includes)
    }

    private func containerView(
        openBracket: String,
        closeBracket: String,
        count: Int,
        @ViewBuilder children: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                disclosureButton
                keyLabel
                Text(effectiveExpanded ? openBracket : "\(openBracket)...\(closeBracket)\(comma)")
                    .font(.system(size: metrics.fontSize, design: .monospaced))
                    .foregroundStyle(Theme.JSON.bracket)
                if !effectiveExpanded {
                    Text(" // \(count) items")
                        .font(.system(size: metrics.secondaryFontSize))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, CGFloat(depth) * Self.indentWidth)
            .background(matchBackground)
            .id(node.path)

            if effectiveExpanded {
                children()

                HStack(spacing: 0) {
                    Text("\(closeBracket)\(comma)")
                        .font(.system(size: metrics.fontSize, design: .monospaced))
                        .foregroundStyle(Theme.JSON.bracket)
                }
                .padding(.leading, CGFloat(depth) * Self.indentWidth)
            }
        }
    }

    private func leafView(
        @ViewBuilder valueContent: () -> some View
    )
        -> some View
    {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 16)
            keyLabel
            valueContent()
                .font(.system(size: metrics.fontSize, design: .monospaced))
                .textSelection(.enabled)
            Text(comma)
                .font(.system(size: metrics.fontSize, design: .monospaced))
                .foregroundStyle(Theme.JSON.bracket)
        }
        .padding(.leading, CGFloat(depth) * Self.indentWidth)
        .background(matchBackground)
        .id(node.path)
    }

    @ViewBuilder private var matchBackground: some View {
        if filter?.isSelected(node) == true {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor.opacity(0.32))
        } else if filter?.isMatch(node) == true {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor.opacity(0.18))
        }
    }
}
