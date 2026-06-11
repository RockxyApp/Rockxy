import SwiftUI

// Presents the breakpoint sheet for breakpoint review and editing.

// MARK: - BreakpointSheetView

/// Modal sheet presented when a breakpoint rule intercepts a request.
/// Allows editing the method, URL, headers, body, and status code before
/// choosing to execute, abort, or cancel the request.
struct BreakpointSheetView: View {
    // MARK: Internal

    @Binding var requestData: BreakpointRequestData

    let onDecision: (BreakpointDecision) -> Void

    var body: some View {
        VStack(spacing: 0) {
            alertBanner
            Divider()
            requestLine
            Divider()
            tabContent
            Divider()
            actionButtons
        }
        .font(toolMetrics.font())
        .frame(width: max(700, toolMetrics.bodyFontSize * 20 + 440), height: max(560, toolMetrics.bodyFontSize * 14 + 378))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
    }

    // MARK: Private

    private static let httpMethods = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    private static let statusCodes: [(code: Int, text: String)] = [
        (200, "OK"),
        (201, "Created"),
        (301, "Moved Permanently"),
        (400, "Bad Request"),
        (403, "Forbidden"),
        (404, "Not Found"),
        (500, "Internal Server Error"),
        (503, "Service Unavailable"),
    ]

    @State private var selectedTab: BreakpointTab = .headers
    @State private var elapsedSeconds: Int = 0
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var alertBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(String(localized: "Request paused at breakpoint"))
                .font(toolMetrics.font())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60))
                .font(toolMetrics.font(monospaced: true))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    private var requestLine: some View {
        HStack(spacing: 8) {
            Picker("", selection: $requestData.method) {
                ForEach(Self.httpMethods, id: \.self) { method in
                    Text(method).tag(method)
                }
            }
            .labelsHidden()
            .frame(width: toolMetrics.menuWidth(100))

            httpsAwareURLField

            Picker("", selection: $requestData.statusCode) {
                ForEach(Self.statusCodes, id: \.code) { status in
                    Text("\(status.code) \(status.text)").tag(status.code)
                }
            }
            .labelsHidden()
            .frame(width: toolMetrics.menuWidth(160))
        }
        .padding(12)
    }

    @ViewBuilder private var httpsAwareURLField: some View {
        if requestData.phase == .request,
           requestData.isHTTPS,
           let urlComponents = URLComponents(string: requestData.url)
        {
            HStack(spacing: 0) {
                Text("https://\(urlComponents.host ?? "")")
                    .font(toolMetrics.font(monospaced: true))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                TextField("", text: Binding(
                    get: {
                        var pathQuery = urlComponents.path
                        if let query = urlComponents.query {
                            pathQuery += "?\(query)"
                        }
                        return pathQuery
                    },
                    set: { newPathQuery in
                        var components = urlComponents
                        let parts = newPathQuery.split(separator: "?", maxSplits: 1)
                        components.path = parts.first.map { String($0) } ?? "/"
                        components.query = parts.count > 1 ? String(parts[1]) : nil
                        requestData.url = components.string ?? requestData.url
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font(monospaced: true))
                .frame(minHeight: toolMetrics.formControlHeight)
            }
        } else if requestData.phase == .request,
                  let urlComponents = URLComponents(string: requestData.url),
                  urlComponents.scheme != nil
        {
            HStack(spacing: 0) {
                Text("\(urlComponents.scheme ?? "http")://")
                    .font(toolMetrics.font(monospaced: true))
                    .foregroundStyle(.secondary)
                TextField("", text: Binding(
                    get: {
                        var hostPathQuery = urlComponents.host ?? ""
                        if let port = urlComponents.port {
                            hostPathQuery += ":\(port)"
                        }
                        hostPathQuery += urlComponents.path
                        if let query = urlComponents.query {
                            hostPathQuery += "?\(query)"
                        }
                        return hostPathQuery
                    },
                    set: { newValue in
                        let scheme = urlComponents.scheme ?? "http"
                        requestData.url = "\(scheme)://\(newValue)"
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font(monospaced: true))
                .frame(minHeight: toolMetrics.formControlHeight)
            }
        } else {
            TextField(String(localized: "URL"), text: $requestData.url)
                .textFieldStyle(.roundedBorder)
                .font(toolMetrics.font(monospaced: true))
                .frame(minHeight: toolMetrics.formControlHeight)
        }
    }

    private var tabContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(BreakpointTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Group {
                switch selectedTab {
                case .headers:
                    headersEditor
                case .body:
                    bodyEditor
                case .query:
                    queryDisplay
                case .response:
                    responseView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var headersEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Name"))
                    .font(toolMetrics.secondaryFont())
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(localized: "Value"))
                    .font(toolMetrics.secondaryFont())
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Space for delete button
                Color.clear.frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            List {
                ForEach($requestData.headers) { $header in
                    HStack(spacing: 8) {
                        TextField(String(localized: "Header name"), text: $header.name)
                            .textFieldStyle(.roundedBorder)
                            .font(toolMetrics.secondaryFont(monospaced: true))
                            .frame(minHeight: toolMetrics.formControlHeight)
                        TextField(String(localized: "Header value"), text: $header.value)
                            .textFieldStyle(.roundedBorder)
                            .font(toolMetrics.secondaryFont(monospaced: true))
                            .frame(minHeight: toolMetrics.formControlHeight)
                        Button {
                            requestData.headers.removeAll { $0.id == header.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)

            HStack {
                Button {
                    requestData.headers.append(EditableHeader(name: "", value: ""))
                } label: {
                    Label(String(localized: "Add Header"), systemImage: "plus.circle")
                        .font(toolMetrics.secondaryFont())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var responseView: some View {
        if requestData.phase == .response {
            TextEditor(text: $requestData.body)
                .font(toolMetrics.font(monospaced: true))
                .padding(8)
        } else {
            ContentUnavailableView(
                String(localized: "No Response Yet"),
                systemImage: "arrow.down.circle",
                description: Text(
                    String(localized: "Response data is available when the breakpoint phase is response.")
                )
            )
        }
    }

    private var bodyEditor: some View {
        TextEditor(text: $requestData.body)
            .font(toolMetrics.font(monospaced: true))
            .padding(8)
    }

    private var queryDisplay: some View {
        let queryItems = URLComponents(string: requestData.url)?.queryItems ?? []
        return Group {
            if queryItems.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Query Parameters"),
                    systemImage: "questionmark.circle",
                    description: Text(String(localized: "This URL has no query string parameters."))
                )
            } else {
                List(queryItems, id: \.name) { item in
                    HStack {
                        Text(item.name)
                            .font(toolMetrics.secondaryFont(monospaced: true))
                            .fontWeight(.semibold)
                        Spacer()
                        Text(item.value ?? "")
                            .font(toolMetrics.secondaryFont(monospaced: true))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button(String(localized: "Cancel")) {
                onDecision(.cancel)
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(String(localized: "Abort (503)")) {
                onDecision(.abort)
            }

            Button(String(localized: "Execute")) {
                onDecision(.execute)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - BreakpointTab

private enum BreakpointTab: String, CaseIterable, Identifiable {
    case headers
    case body
    case query
    case response

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .headers: String(localized: "Headers")
        case .body: String(localized: "Body")
        case .query: String(localized: "Query")
        case .response: String(localized: "Response")
        }
    }
}
