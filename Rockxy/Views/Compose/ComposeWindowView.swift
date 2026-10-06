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
                requestRestrictionBanner
            }
            Divider()
            HSplitView {
                ComposeRequestEditor(
                    viewModel: viewModel,
                    onLoadFromFile: { isShowingBodyImporter = true }
                )
                .frame(minWidth: 430)
                .disabled(isSending)
                ComposeResponseViewer(viewModel: viewModel)
                    .frame(minWidth: 360)
            }
            Divider()
            footerBar
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(900, toolMetrics.bodyFontSize * 32 + 484),
            idealWidth: max(1_120, toolMetrics.bodyFontSize * 38 + 626),
            minHeight: max(600, min(780, toolMetrics.bodyFontSize * 18 + 366)),
            idealHeight: max(720, toolMetrics.bodyFontSize * 24 + 508)
        )
        .onAppear {
            consumeDraftRequest()
            isURLFocused = true
        }
        .onDisappear {
            cancelSend()
            cancelBodyImport()
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
        .alert(
            String(localized: "Import Failed", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: {
                    if !$0 {
                        importErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle), role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            if let importErrorMessage {
                Text(importErrorMessage)
            }
        }
        .alert(
            String(localized: "Clear Compose History?", bundle: RockxyLocalization.bundle),
            isPresented: $isShowingClearHistoryConfirmation
        ) {
            Button(String(localized: "Cancel", bundle: RockxyLocalization.bundle), role: .cancel) {}
            Button(String(localized: "Clear History", bundle: RockxyLocalization.bundle), role: .destructive) {
                Task {
                    await viewModel.clearHistory()
                }
            }
        } message: {
            Text(String(
                localized: "This removes all locally stored Compose request and response history.",
                bundle: RockxyLocalization.bundle
            ))
        }
    }

    // MARK: Private

    private static let httpMethods = [
        "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "QUERY",
    ]

    @State private var viewModel = ComposeViewModel()
    @State private var isShowingBodyImporter = false
    @State private var isShowingClearHistoryConfirmation = false
    @State private var importErrorMessage: String?
    @State private var sendTask: Task<Void, Never>?
    @State private var sendTaskID: UUID?
    @State private var bodyImportTask: Task<Void, Never>?
    @State private var bodyImportTaskID: UUID?
    @FocusState private var isURLFocused: Bool
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var isSending: Bool {
        if case .loading = viewModel.responseState {
            return true
        }
        return false
    }

    private var methodControlWidth: CGFloat {
        max(toolMetrics.menuWidth(96), toolMetrics.bodyFontSize * 4.5 + 36)
    }

    private var sendControlWidth: CGFloat {
        max(78, toolMetrics.bodyFontSize * 2.8 + 44)
    }

    private var shouldShowRequestRestriction: Bool {
        switch viewModel.responseState {
        case .empty,
             .success,
             .error:
            true
        case .loading,
             .unsupported:
            false
        }
    }

    private var composeBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Picker(String(localized: "HTTP Method", bundle: RockxyLocalization.bundle), selection: $viewModel.method) {
                ForEach(Self.httpMethods, id: \.self) { method in
                    Text(method).tag(method)
                }
                if viewModel.method == "CONNECT" {
                    Text("CONNECT").tag("CONNECT")
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: methodControlWidth, height: toolMetrics.formControlHeight)
            .onChange(of: viewModel.method) {
                viewModel.syncUnsupportedState()
            }
            .accessibilityLabel(String(localized: "HTTP method", bundle: RockxyLocalization.bundle))
            .disabled(isSending)

            TextField(
                String(localized: "https://example.com/path", bundle: RockxyLocalization.bundle),
                text: $viewModel.url
            )
            .textFieldStyle(.roundedBorder)
            .font(toolMetrics.font(monospaced: true))
            .frame(height: toolMetrics.formControlHeight)
            .focused($isURLFocused)
            .onSubmit {
                guard !importCurlFromURLFieldIfNeeded(reportingErrors: true) else {
                    return
                }
                startSend()
            }
            .onChange(of: viewModel.url) {
                guard !importCurlFromURLFieldIfNeeded(reportingErrors: false) else {
                    return
                }
                viewModel.syncURLToQuery()
            }
            .accessibilityLabel(String(localized: "Request URL", bundle: RockxyLocalization.bundle))
            .disabled(isSending)

            sendButton
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .rockxyFunctionalBar()
    }

    @ViewBuilder private var sendButton: some View {
        if isSending {
            Button {
                cancelSend()
            } label: {
                Text(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                    .frame(width: sendControlWidth)
            }
            .rockxyGlassButtonStyle()
            .controlSize(.regular)
            .frame(height: toolMetrics.formControlHeight)
            .keyboardShortcut(".", modifiers: .command)
            .help(String(localized: "Cancel the active request", bundle: RockxyLocalization.bundle))
        } else {
            Button {
                startSend()
            } label: {
                Text(String(localized: "Send", bundle: RockxyLocalization.bundle))
                    .frame(width: sendControlWidth)
            }
            .rockxyGlassButtonStyle(prominent: true)
            .controlSize(.regular)
            .frame(height: toolMetrics.formControlHeight)
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
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.bottom, 6)
            .transition(.opacity)
        }
    }

    @ViewBuilder private var requestRestrictionBanner: some View {
        if shouldShowRequestRestriction,
           let message = viewModel.replayRestrictionMessage
        {
            HStack(spacing: toolMetrics.controlSpacing) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if viewModel.sourceHasUnsupportedBinaryBody || viewModel.sourceHasTruncatedHistoryBody {
                    Button(String(localized: "Use Empty Body", bundle: RockxyLocalization.bundle)) {
                        viewModel.replaceUnavailableBody(with: "")
                    }
                    .rockxyGlassButtonStyle()
                }
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.bottom, toolMetrics.controlSpacing)
        }
    }

    private var footerBar: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            templateMenu
            historyMenu
            settingsMenu
            Spacer()
            Text(isSending ? String(localized: "⌘. Cancel", bundle: RockxyLocalization.bundle) : String(
                localized: "⌘↩ Send",
                bundle: RockxyLocalization.bundle
            ))
            .font(toolMetrics.metadataFont())
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
        .rockxyFunctionalBar()
    }

    private var templateMenu: some View {
        Menu {
            Button(ComposeTemplate.empty.title) {
                cancelSend()
                viewModel.applyTemplate(.empty)
            }
            Divider()
            Button(ComposeTemplate.getWithQuery.title) {
                cancelSend()
                viewModel.applyTemplate(.getWithQuery)
            }
            Divider()
            Button(ComposeTemplate.postJSON.title) {
                cancelSend()
                viewModel.applyTemplate(.postJSON)
            }
            Button(ComposeTemplate.postForm.title) {
                cancelSend()
                viewModel.applyTemplate(.postForm)
            }
            Button(ComposeTemplate.postMultipart.title) {
                cancelSend()
                viewModel.applyTemplate(.postMultipart)
            }
            Divider()
            Button(String(localized: "Import from cURL...", bundle: RockxyLocalization.bundle)) {
                importCurlFromPasteboard()
            }
        } label: {
            Label(String(localized: "Template", bundle: RockxyLocalization.bundle), systemImage: "doc.badge.plus")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .keyboardShortcut("t", modifiers: .command)
    }

    private var historyMenu: some View {
        Menu {
            if viewModel.history.isEmpty {
                Text(String(localized: "No History", bundle: RockxyLocalization.bundle))
            } else {
                ForEach(viewModel.history) { entry in
                    Button(entry.menuTitle) {
                        cancelSend()
                        viewModel.restoreHistoryEntry(id: entry.id)
                    }
                }
                Divider()
                Text(
                    String(
                        localized: "History stays on this Mac. Authentication and cookie header values are redacted; URLs and bodies remain stored locally.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                .font(toolMetrics.secondaryFont())
                Button(String(localized: "Clear All...", bundle: RockxyLocalization.bundle), role: .destructive) {
                    isShowingClearHistoryConfirmation = true
                }
            }
        } label: {
            Label(
                String(localized: "History", bundle: RockxyLocalization.bundle),
                systemImage: "clock.arrow.circlepath"
            )
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .keyboardShortcut("y", modifiers: .command)
    }

    private var settingsMenu: some View {
        Menu {
            Button(String(localized: "Focus URL Field", bundle: RockxyLocalization.bundle)) {
                isURLFocused = true
            }
            .keyboardShortcut("l", modifiers: .command)
            Divider()
            Menu(String(localized: "Request Timeout", bundle: RockxyLocalization.bundle)) {
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
                String(localized: "Automatically Follow Redirects", bundle: RockxyLocalization.bundle),
                isOn: $viewModel.followsRedirects
            )
            Divider()
            Button(String(localized: "Reset to Fresh Request", bundle: RockxyLocalization.bundle)) {
                cancelSend()
                viewModel.resetDraft()
                isURLFocused = true
            }
            .keyboardShortcut("0", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
        }
        .menuStyle(.button)
        .help(String(localized: "Request Options", bundle: RockxyLocalization.bundle))
    }

    private func consumeDraftRequest() {
        let store = ComposeStore.shared
        if let transaction = store.pendingTransaction {
            sendTask?.cancel()
            sendTask = nil
            sendTaskID = nil
            viewModel.prefill(from: transaction)
            store.pendingTransaction = nil
            store.shouldOpenBlankDraft = false
            return
        }

        guard store.shouldOpenBlankDraft else {
            return
        }
        sendTask?.cancel()
        sendTask = nil
        sendTaskID = nil
        viewModel.resetDraft()
        store.shouldOpenBlankDraft = false
    }

    private func importBodyFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result {
                importErrorMessage = error.localizedDescription
            }
            return
        }
        cancelSend()
        cancelBodyImport()
        let taskID = UUID()
        bodyImportTaskID = taskID
        bodyImportTask = Task {
            do {
                try await viewModel.loadBodyFromFile(url: url)
            } catch {
                if !Task.isCancelled, bodyImportTaskID == taskID {
                    importErrorMessage = error.localizedDescription
                }
            }
            if bodyImportTaskID == taskID {
                bodyImportTask = nil
                bodyImportTaskID = nil
            }
        }
    }

    /// A cURL command pasted straight into the URL field is imported in place, matching how
    /// people move requests over from a terminal or a bug report. Returns `true` when the field
    /// holds a command so the caller does not treat it as a URL. Parse failures are only
    /// surfaced on submit; while the text is still being edited they stay silent.
    private func importCurlFromURLFieldIfNeeded(reportingErrors: Bool) -> Bool {
        do {
            guard try viewModel.importCurlCommandFromURLFieldIfNeeded() else {
                return false
            }
            sendTask?.cancel()
            sendTask = nil
            sendTaskID = nil
        } catch {
            if reportingErrors {
                importErrorMessage = error.localizedDescription
            }
        }
        return true
    }

    private func importCurlFromPasteboard() {
        guard let command = NSPasteboard.general.string(forType: .string) else {
            importErrorMessage = ComposeImportError.emptyCommand.localizedDescription
            return
        }
        do {
            try viewModel.importCurlCommand(command)
            sendTask?.cancel()
            sendTask = nil
            sendTaskID = nil
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func startSend() {
        guard sendTaskID == nil else {
            return
        }
        let taskID = UUID()
        sendTaskID = taskID
        sendTask?.cancel()
        sendTask = Task {
            await viewModel.send()
            if sendTaskID == taskID {
                sendTask = nil
                sendTaskID = nil
            }
        }
    }

    private func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        sendTaskID = nil
        viewModel.cancelActiveSend()
    }

    private func cancelBodyImport() {
        bodyImportTask?.cancel()
        bodyImportTask = nil
        bodyImportTaskID = nil
    }
}
