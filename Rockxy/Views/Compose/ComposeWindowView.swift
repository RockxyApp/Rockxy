import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Presents the compose window for the compose workflow.

// MARK: - ComposeWindowView

/// Standalone Compose window for editing and repeatedly sending HTTP requests.
/// Top compose bar (method + URL + Send) spans the full width. Below, an HSplitView
/// divides the request editor (left) from the response viewer (right).
struct ComposeWindowView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                composeBar
                restoreConfirmationBanner
            }
            Divider()
            HSplitView {
                ComposeRequestEditor(
                    viewModel: viewModel,
                    onLoadFromFile: { isShowingBodyImporter = true }
                )
                .frame(minWidth: 430)
                ComposeResponseViewer(viewModel: viewModel)
                    .frame(minWidth: 360)
            }
            Divider()
            footerBar
        }
        .font(.system(.body))
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            consumeDraftRequest()
            isURLFocused = true
        }
        .onChange(of: ComposeStore.shared.draftVersion) {
            consumeDraftRequest()
        }
        .task(id: viewModel.restoreConfirmationID) {
            guard viewModel.restoreConfirmationMessage != nil else {
                return
            }
            try? await Task.sleep(for: .seconds(2))
            viewModel.clearRestoreConfirmation()
        }
        .fileImporter(
            isPresented: $isShowingBodyImporter,
            allowedContentTypes: [.json, .xml, .plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            importBodyFile(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusComposeURLField)) { _ in
            isURLFocused = true
        }
    }

    // MARK: Private

    private static let httpMethods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    @State private var viewModel = ComposeViewModel()
    @State private var isShowingBodyImporter = false
    @FocusState private var isURLFocused: Bool

    private var composeBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $viewModel.method) {
                    ForEach(Self.httpMethods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.accentColor)
                .frame(width: 86)
                .onChange(of: viewModel.method) {
                    viewModel.syncUnsupportedState()
                }

                TextField(String(localized: "URL"), text: $viewModel.url)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($isURLFocused)
                    .onSubmit {
                        Task { await viewModel.send() }
                    }
                    .onChange(of: viewModel.url) {
                        viewModel.syncURLToQuery()
                    }

                Button {
                    // Future raw-message expansion hook. Kept as a native toolbar-style affordance.
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "Expand Raw Message"))
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))

            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var sendButton: some View {
        if case .loading = viewModel.responseState {
            ProgressView()
                .controlSize(.small)
                .frame(width: 60)
        } else {
            Button(String(localized: "Send")) {
                Task { await viewModel.send() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.url.isEmpty || viewModel.isUnsupportedForReplay)
        }
    }

    @ViewBuilder private var restoreConfirmationBanner: some View {
        if let message = viewModel.restoreConfirmationMessage {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color.accentColor)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .transition(.opacity)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            templateMenu
            historyMenu
            settingsMenu
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var templateMenu: some View {
        Menu {
            Button(ComposeTemplate.empty.title) {
                viewModel.applyTemplate(.empty)
            }
            Divider()
            Button(ComposeTemplate.getWithQuery.title) {
                viewModel.applyTemplate(.getWithQuery)
            }
            Divider()
            Button(ComposeTemplate.postJSON.title) {
                viewModel.applyTemplate(.postJSON)
            }
            Button(ComposeTemplate.postForm.title) {
                viewModel.applyTemplate(.postForm)
            }
            Button(ComposeTemplate.postMultipart.title) {
                viewModel.applyTemplate(.postMultipart)
            }
            Divider()
            Button(String(localized: "Import from cURL...")) {
                importCurlFromPasteboard()
            }
        } label: {
            Label(String(localized: "Template"), systemImage: "doc.badge.plus")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .keyboardShortcut("t", modifiers: .command)
    }

    private var historyMenu: some View {
        Menu {
            if viewModel.history.isEmpty {
                Text(String(localized: "No History"))
            } else {
                ForEach(viewModel.history) { entry in
                    Button(entry.menuTitle) {
                        viewModel.restoreHistoryEntry(id: entry.id)
                    }
                }
                Divider()
                Text(String(localized: "Authorization and cookie headers are not stored on disk."))
                    .font(.caption)
                Button(String(localized: "Clear All..."), role: .destructive) {
                    viewModel.clearHistory()
                }
            }
        } label: {
            Label(String(localized: "History"), systemImage: "clock.arrow.circlepath")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .keyboardShortcut("y", modifiers: .command)
    }

    private var settingsMenu: some View {
        Menu {
            Button(String(localized: "Focus URL Field")) {
                isURLFocused = true
            }
            .keyboardShortcut("l", modifiers: .command)
            Divider()
            Menu(String(localized: "Request Timeout")) {
                ForEach(ComposeRequestTimeout.allCases) { timeout in
                    Button {
                        viewModel.requestTimeout = timeout
                    } label: {
                        if viewModel.requestTimeout == timeout {
                            Label(timeout.title, systemImage: "checkmark")
                        } else {
                            Text(timeout.title)
                        }
                    }
                }
            }
            Divider()
            Toggle(
                String(localized: "Automatically Follow Redirects"),
                isOn: $viewModel.followsRedirects
            )
            Divider()
            Button(String(localized: "Reset to Fresh Request")) {
                viewModel.resetDraft()
                isURLFocused = true
            }
            .keyboardShortcut("0", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
        }
        .menuStyle(.button)
        .help(String(localized: "Request Options"))
    }

    private func consumeDraftRequest() {
        let store = ComposeStore.shared
        if let transaction = store.pendingTransaction {
            viewModel.prefill(from: transaction)
            store.pendingTransaction = nil
            store.shouldOpenBlankDraft = false
            return
        }

        guard store.shouldOpenBlankDraft else {
            return
        }
        viewModel.resetDraft()
        store.shouldOpenBlankDraft = false
    }

    private func importBodyFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            return
        }
        do {
            try viewModel.loadBodyFromFile(url: url)
        } catch {
            // The body editor exposes formatter errors; file import failures remain non-destructive.
        }
    }

    private func importCurlFromPasteboard() {
        guard let command = NSPasteboard.general.string(forType: .string) else {
            return
        }
        do {
            try viewModel.importCurlCommand(command)
        } catch {
            // The body editor exposes formatter/import errors without replacing the current draft.
        }
    }
}
