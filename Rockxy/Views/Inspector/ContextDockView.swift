import SwiftUI

// MARK: - ContextDockView

/// Native two-tab shell for request diagnostics and the conversational AI workflow.
struct ContextDockView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Inspector"), selection: selectedTab) {
                Text(String(localized: "Details")).tag(ContextDockTab.details)
                Text(String(localized: "AI Assistant")).tag(ContextDockTab.aiAssistant)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(10)

            Divider()

            switch coordinator.activeWorkspace.contextDockTab {
            case .details:
                ContextDetailsView(coordinator: coordinator)
            case .aiAssistant:
                AIAssistantDockView(coordinator: coordinator)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Inspector"))
    }

    // MARK: Private

    private var selectedTab: Binding<ContextDockTab> {
        Binding(
            get: { coordinator.activeWorkspace.contextDockTab },
            set: { coordinator.activeWorkspace.contextDockTab = $0 }
        )
    }
}

// MARK: - AIAssistantDockView

/// A selection-aware conversation with Rockxy's debugging assistant.
/// Captured traffic is attached as context; provider configuration remains secondary plumbing.
private struct AIAssistantDockView: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            assistantHeader
            Divider()
            attachedContextHeader
            Divider()
            conversationTranscript
            Divider()
            promptComposer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Rockxy AI Assistant"))
        .sheet(item: reviewPackBinding) { pack in
            DebugAssistantReviewDataSheet(
                pack: pack,
                configuration: coordinator.activeWorkspace.debugAssistantReviewConfiguration,
                trafficScope: coordinator.activeWorkspace.debugAssistantReviewTrafficScope
                    ?? AssistantTrustPolicy.defaultTrafficScope,
                modelAccessEnabled: coordinator.activeWorkspace.debugAssistantReviewModelAccessEnabled,
                onSend: coordinator.sendDebugAssistantReview,
                onDismiss: coordinator.dismissDebugAssistantReview
            )
        }
        .alert(
            String(localized: "Rename Conversation"),
            isPresented: renameConversationBinding
        ) {
            TextField(String(localized: "Conversation name"), text: $conversationRenameDraft)
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Rename")) {
                guard let conversationBeingRenamed else {
                    return
                }
                coordinator.renameDebugAssistantConversation(
                    conversationBeingRenamed.id,
                    title: conversationRenameDraft
                )
            }
        }
        .confirmationDialog(
            String(localized: "Delete this conversation?"),
            isPresented: deleteConversationBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Conversation"), role: .destructive) {
                guard let conversationPendingDeletion else {
                    return
                }
                coordinator.deleteDebugAssistantConversation(conversationPendingDeletion.id)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This removes the conversation from this workspace history."))
        }
        .confirmationDialog(
            String(localized: "Prepare this request for replay?"),
            isPresented: prepareReplayBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Open in Compose")) {
                guard let resultPendingReplay else {
                    return
                }
                coordinator.performUserInitiatedDebugAssistantHandoff(.prepareReplay, result: resultPendingReplay)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Rockxy will create an editable draft. Nothing is sent until you press Send in Compose."))
        }
    }

    // MARK: Private

    private static let activeTurnID = "debug-assistant-active-turn"
    private static let transcriptBottomID = "debug-assistant-transcript-bottom"

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isComposerFocused: Bool
    @State private var isConversationSwitcherPresented = false
    @State private var conversationSearch = ""
    @State private var conversationBeingRenamed: DebugAssistantConversation?
    @State private var conversationRenameDraft = ""
    @State private var conversationPendingDeletion: DebugAssistantConversation?
    @State private var isTrustPopoverPresented = false
    @State private var resultPendingReplay: InvestigationResult?

    private var draftBinding: Binding<String> {
        Binding(
            get: { coordinator.activeWorkspace.debugAssistantDraft },
            set: { coordinator.activeWorkspace.debugAssistantDraft = $0 }
        )
    }

    private var reviewPackBinding: Binding<InvestigationContextPack?> {
        Binding(
            get: { coordinator.activeWorkspace.debugAssistantReviewPack },
            set: { value in
                if value == nil {
                    coordinator.dismissDebugAssistantReview()
                }
            }
        )
    }

    private var renameConversationBinding: Binding<Bool> {
        Binding(
            get: { conversationBeingRenamed != nil },
            set: { isPresented in
                if !isPresented {
                    conversationBeingRenamed = nil
                    conversationRenameDraft = ""
                }
            }
        )
    }

    private var deleteConversationBinding: Binding<Bool> {
        Binding(
            get: { conversationPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    conversationPendingDeletion = nil
                }
            }
        )
    }

    private var prepareReplayBinding: Binding<Bool> {
        Binding(
            get: { resultPendingReplay != nil },
            set: { isPresented in
                if !isPresented {
                    resultPendingReplay = nil
                }
            }
        )
    }

    private var filteredConversations: [DebugAssistantConversation] {
        coordinator.activeWorkspace.debugAssistantConversations
            .filter { $0.matches(conversationSearch) }
            .sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var assistantConfiguration: AssistantProviderConfiguration? {
        AppSettingsManager.shared.settings.assistantProviderConfiguration
    }

    private var configuredModelIsAvailable: Bool {
        AppSettingsManager.shared.settings.debugAssistantModelAccessEnabled
            && assistantConfiguration?.isComplete == true
    }

    private var configuredModelLabel: String {
        guard let assistantConfiguration, assistantConfiguration.isComplete else {
            return String(localized: "No Configured Model")
        }
        return String(
            localized: "Global Default · \(assistantConfiguration.kind.title) · \(assistantConfiguration.model)"
        )
    }

    private var modelSelectionLabel: String {
        guard coordinator.activeWorkspace.debugAssistantUsesConfiguredModel,
              configuredModelIsAvailable else
        {
            return String(localized: "Built-in")
        }
        return assistantConfiguration?.model ?? String(localized: "Model")
    }

    private var selectedTransactions: [HTTPTransaction] {
        coordinator.debugAssistantSelectedTransactions()
    }

    private var primaryTransaction: HTTPTransaction? {
        selectedTransactions.first ?? coordinator.selectedTransaction
    }

    private var contextTransactions: [HTTPTransaction] {
        coordinator.debugAssistantContextTransactions()
    }

    private var relatedTransactionCount: Int {
        coordinator.debugAssistantRelatedTransactionCount()
    }

    private var selectedContextCount: Int {
        min(selectedTransactions.count, InvestigationContextLimits.default.maxTransactions)
    }

    private var conversationIsEmpty: Bool {
        coordinator.activeWorkspace.debugAssistantMessages.isEmpty
    }

    private var isBusy: Bool {
        if coordinator.activeWorkspace.isPreparingDebugAssistantReview {
            return true
        }
        if case .investigating = coordinator.activeWorkspace.debugAssistantState {
            return true
        }
        if case .streaming = coordinator.activeWorkspace.modelInvestigationState {
            return true
        }
        return false
    }

    private var canSendDraft: Bool {
        !isBusy
            && !coordinator.activeWorkspace.debugAssistantDraft
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var streamingText: String {
        guard case let .streaming(_, _, _, _, text) = coordinator.activeWorkspace.modelInvestigationState else {
            return ""
        }
        return text
    }

    private var assistantHeader: some View {
        HStack(spacing: 8) {
            Text(coordinator.activeWorkspace.debugAssistantConversationTitle)
                .font(assistantFont(appMetrics.primaryFontSize, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 6)

            Button {
                isConversationSwitcherPresented.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .keyboardShortcut("k", modifiers: .command)
            .help(String(localized: "Search conversations (⌘K)"))
            .accessibilityLabel(String(localized: "Conversation History"))
            .popover(isPresented: $isConversationSwitcherPresented, arrowEdge: .top) {
                conversationSwitcher
            }

            Button {
                coordinator.newDebugAssistantConversation()
                isConversationSwitcherPresented = false
                isComposerFocused = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(String(localized: "New conversation"))
            .accessibilityLabel(String(localized: "New Conversation"))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: max(36, appMetrics.primaryFontSize + 20))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var conversationSwitcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Conversations"))
                .font(assistantFont(appMetrics.primaryFontSize, weight: .semibold))

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    String(localized: "Search titles and messages"),
                    text: $conversationSearch
                )
                .textFieldStyle(.plain)
            }
            .font(assistantFont(appMetrics.controlFontSize))
            .padding(.horizontal, 8)
            .frame(height: max(30, appMetrics.controlFontSize + 16))
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }

            if filteredConversations.isEmpty {
                ContentUnavailableView {
                    Label(
                        conversationSearch.isEmpty
                            ? String(localized: "No Conversations")
                            : String(localized: "No Results"),
                        systemImage: conversationSearch.isEmpty
                            ? "bubble.left.and.bubble.right"
                            : "magnifyingglass"
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredConversations) { conversation in
                            conversationHistoryRow(conversation)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 352, height: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var attachedContextHeader: some View {
        if let transaction = primaryTransaction {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(for: transaction))
                    .frame(width: 7, height: 7)

                Text(requestSummary(for: transaction))
                    .font(assistantFont(appMetrics.secondaryFontSize, monospaced: true))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Menu {
                    Button {
                        coordinator.setDebugAssistantTrafficScope(.selectedOnly)
                    } label: {
                        Label(
                            String(localized: "Selected Traffic Only (\(selectedContextCount))"),
                            systemImage: coordinator.activeWorkspace.debugAssistantTrafficScope == .selectedOnly
                                ? "checkmark" : "circle"
                        )
                    }

                    Button {
                        coordinator.setDebugAssistantTrafficScope(.selectedAndRelated)
                    } label: {
                        Label(
                            String(localized: "Include Related Requests (+\(relatedTransactionCount))"),
                            systemImage: coordinator.activeWorkspace.debugAssistantTrafficScope == .selectedAndRelated
                                ? "checkmark" : "circle"
                        )
                    }
                    .disabled(relatedTransactionCount == 0)
                } label: {
                    Label("\(contextTransactions.count)", systemImage: "paperclip")
                        .font(assistantFont(appMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .controlSize(.small)
                .help(String(localized: "Choose the read-only traffic scope"))
                .accessibilityLabel(
                    String(localized: "Read-only traffic scope, \(contextTransactions.count) requests")
                )
            }
            .padding(.horizontal, 10)
            .frame(minHeight: max(32, appMetrics.secondaryFontSize + 18))
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                String(
                    localized: "Attached traffic: \(requestSummary(for: transaction)), \(contextTransactions.count) requests"
                )
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                Text(String(localized: "Select traffic to add context"))
                    .font(assistantFont(appMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: max(32, appMetrics.secondaryFontSize + 18))
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var conversationTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if conversationIsEmpty {
                        emptyConversationView
                    }

                    ForEach(coordinator.activeWorkspace.debugAssistantMessages) { message in
                        conversationMessage(message)
                            .id(message.id)
                    }

                    activeAssistantTurn
                        .id(Self.activeTurnID)

                    Color.clear
                        .frame(height: 1)
                        .id(Self.transcriptBottomID)
                }
                .padding(10)
            }
            .onChange(of: coordinator.activeWorkspace.debugAssistantMessages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: streamingText) {
                scrollToBottom(proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyConversationView: some View {
        VStack(spacing: 12) {
            Image(systemName: primaryTransaction == nil ? "bubble.left" : "sparkles")
                .font(assistantFont(appMetrics.primaryFontSize + 8, weight: .medium))
                .foregroundStyle(.secondary)

            Text(primaryTransaction == nil
                ? String(localized: "Ask about captured traffic")
                : String(localized: "What should I check?"))
                .font(assistantFont(appMetrics.primaryFontSize, weight: .semibold))

            if primaryTransaction == nil {
                Text(String(localized: "Select a request or start typing below."))
                    .font(assistantFont(appMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
            } else {
                suggestionGrid
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var suggestionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
            spacing: 6
        ) {
            ForEach(DebugAssistantRecipe.allCases) { recipe in
                Button {
                    coordinator.startDebugAssistant(recipe)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: recipe.systemImage)
                            .frame(width: 14)
                        Text(recipe.title)
                            .font(assistantFont(appMetrics.metadataFontSize, weight: .medium))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)
                .help(recipe.detail)
            }
        }
        .frame(maxWidth: 360)
    }

    @ViewBuilder private var activeAssistantTurn: some View {
        switch coordinator.activeWorkspace.debugAssistantState {
        case .idle,
             .result:
            modelAssistantTurn
        case let .investigating(_, recipe):
            workEvent(
                title: String(localized: "Investigating \(recipe.title.lowercased())"),
                cancel: coordinator.cancelDebugAssistant
            )
        case let .failed(message):
            failureTurn(message)
        }
    }

    @ViewBuilder private var modelAssistantTurn: some View {
        switch coordinator.activeWorkspace.modelInvestigationState {
        case .idle,
             .completed:
            EmptyView()
        case let .streaming(_, provider, model, endpointHost, text):
            assistantBubble {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text(text.isEmpty ? String(localized: "Thinking…") : String(localized: "Responding…"))
                        .font(assistantFont(appMetrics.secondaryFontSize, weight: .medium))
                    Spacer(minLength: 0)
                    Button(String(localized: "Stop")) {
                        coordinator.cancelDebugAssistantModelAnalysis()
                    }
                    .controlSize(.mini)
                }
                if !text.isEmpty {
                    Text(text)
                        .font(assistantFont(appMetrics.primaryFontSize))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                modelSourceLabel(
                    provider: provider.title,
                    model: model,
                    endpointHost: endpointHost,
                    usage: nil
                )
            }
        case let .failed(message):
            assistantBubble {
                Label(
                    String(localized: "I couldn’t complete the model response."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(assistantFont(appMetrics.secondaryFontSize, weight: .semibold))
                .foregroundStyle(.red)
                Text(message)
                    .font(assistantFont(appMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(String(localized: "Review & Retry")) {
                        coordinator.prepareDebugAssistantReview()
                    }
                    .controlSize(.small)

                    if assistantConfiguration?.kind == .ollama {
                        Button(String(localized: "Check Local Model…")) {
                            RockxySettingsTab.select(.assistant)
                            openSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if primaryTransaction != nil, !isBusy, conversationIsEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(DebugAssistantRecipe.allCases.prefix(2)) { recipe in
                            Button(recipe.title) {
                                coordinator.startDebugAssistant(recipe)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .font(assistantFont(appMetrics.metadataFontSize))
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    primaryTransaction == nil
                        ? String(localized: "Ask Rockxy AI Assistant…")
                        : String(localized: "Ask about this traffic…"),
                    text: draftBinding,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(assistantFont(appMetrics.primaryFontSize))
                .lineLimit(1 ... 4)
                .focused($isComposerFocused)
                .onSubmit(sendDraft)
                .disabled(isBusy)

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up")
                        .font(assistantFont(appMetrics.controlFontSize, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSendDraft)
                .help(String(localized: "Send message"))
                .accessibilityLabel(String(localized: "Send Message"))
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isComposerFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isBusy else {
                    return
                }
                isComposerFocused = true
            }

            HStack(spacing: 8) {
                Menu {
                    Button {
                        coordinator.activeWorkspace.debugAssistantUsesConfiguredModel = false
                    } label: {
                        Label(
                            String(localized: "Built-in Analysis (No Model)"),
                            systemImage: coordinator.activeWorkspace.debugAssistantUsesConfiguredModel
                                ? "circle" : "checkmark"
                        )
                    }

                    Divider()

                    Button {
                        coordinator.activeWorkspace.debugAssistantUsesConfiguredModel = true
                    } label: {
                        Label(
                            configuredModelLabel,
                            systemImage: coordinator.activeWorkspace.debugAssistantUsesConfiguredModel
                                ? "checkmark" : "circle"
                        )
                    }
                    .disabled(!configuredModelIsAvailable)

                    Divider()

                    Button {
                        RockxySettingsTab.select(.assistant)
                        openSettings()
                    } label: {
                        Label(String(localized: "Manage AI Models…"), systemImage: "gearshape")
                    }
                } label: {
                    Label(modelSelectionLabel, systemImage: "cpu")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .controlSize(.mini)
                .font(assistantFont(appMetrics.metadataFontSize))
                .fixedSize()
                .help(String(localized: "Choose local analysis or the app-wide AI model"))

                Spacer(minLength: 4)

                Button {
                    isTrustPopoverPresented.toggle()
                } label: {
                    Label(String(localized: "Read-only"), systemImage: "lock.shield")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .font(assistantFont(appMetrics.metadataFontSize))
                .foregroundStyle(.secondary)
                .help(String(localized: "Review the AI Assistant trust boundary"))
                .accessibilityLabel(String(localized: "Read-only Assistant privacy details"))
                .popover(isPresented: $isTrustPopoverPresented, arrowEdge: .bottom) {
                    AssistantTrustPopover()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func conversationHistoryRow(_ conversation: DebugAssistantConversation) -> some View {
        Button {
            coordinator.selectDebugAssistantConversation(conversation.id)
            isConversationSwitcherPresented = false
            isComposerFocused = true
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .font(assistantFont(appMetrics.metadataFontSize))
                                .foregroundStyle(.secondary)
                        }
                        Text(conversation.title)
                            .font(assistantFont(appMetrics.secondaryFontSize, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(conversation.preview)
                        .font(assistantFont(appMetrics.metadataFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(relativeDateLabel(conversation.updatedAt))
                    .font(assistantFont(appMetrics.metadataFontSize))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                conversation.id == coordinator.activeWorkspace.debugAssistantConversationID
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.16)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                coordinator.togglePinnedDebugAssistantConversation(conversation.id)
            } label: {
                Label(
                    conversation.isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                conversationBeingRenamed = conversation
                conversationRenameDraft = conversation.title
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                conversationPendingDeletion = conversation
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
        .accessibilityLabel("\(conversation.title), \(conversation.preview)")
    }

    @ViewBuilder
    private func conversationMessage(_ message: DebugAssistantMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message.text)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if let investigation = message.investigation {
                    completedWorkEvent(investigation)
                }

                assistantBubble {
                    Text(message.text.isEmpty
                        ? String(localized: "The model completed without returning text.")
                        : message.text)
                        .font(assistantFont(appMetrics.primaryFontSize))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if let investigation = message.investigation {
                        investigationDetails(investigation)
                    }

                    if let modelResult = message.modelResult {
                        modelAttribution(modelResult)
                    }
                }
            }
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 44)
            Text(text)
                .font(assistantFont(appMetrics.primaryFontSize))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "You: \(text)"))
    }

    private func assistantBubble(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "AI Assistant Response"))
    }

    private func investigationDetails(_ result: InvestigationResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if !result.evidence.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.evidence.prefix(3)) { evidence in
                            Button {
                                coordinator.revealDebugAssistantEvidence(evidence)
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(evidenceColor(evidence.kind))
                                        .frame(width: 6, height: 6)
                                    Text(evidence.title)
                                        .font(assistantFont(appMetrics.metadataFontSize, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(evidence.sourceTransactionID == nil)
                            .help(evidence.detail)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label(
                        String(localized: "\(result.evidence.count) Findings"),
                        systemImage: "list.bullet"
                    )
                    .font(assistantFont(appMetrics.metadataFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }

            Label(result.nextStep, systemImage: "arrow.turn.down.right")
                .font(assistantFont(appMetrics.secondaryFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if isCurrentResult(result),
               coordinator.activeWorkspace.debugAssistantUsesConfiguredModel,
               configuredModelIsAvailable
            {
                HStack(spacing: 8) {
                    if coordinator.activeWorkspace.isPreparingDebugAssistantReview {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Preparing redacted preview…"))
                            .font(assistantFont(appMetrics.secondaryFontSize))
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            coordinator.prepareDebugAssistantReview()
                        } label: {
                            Label(String(localized: "Continue With Model"), systemImage: "lock.shield")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }

            if isCurrentResult(result) {
                assistantHandoffButtons(for: result)
            }
        }
    }

    private func assistantHandoffButtons(for result: InvestigationResult) -> some View {
        HStack(spacing: 6) {
            ForEach(AssistantTrustPolicy.recommendedHandoffs(for: result.recipe)) { handoff in
                Button {
                    if handoff == .prepareReplay {
                        resultPendingReplay = result
                    } else {
                        coordinator.performUserInitiatedDebugAssistantHandoff(handoff, result: result)
                    }
                } label: {
                    Label(handoff.title, systemImage: handoff.systemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func modelAttribution(_ result: ModelInvestigationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if result.blockedToolCallCount > 0 {
                Label(
                    String(localized: "Rockxy blocked \(result.blockedToolCallCount) model action request(s)."),
                    systemImage: "hand.raised.fill"
                )
                .font(assistantFont(appMetrics.metadataFontSize))
                .foregroundStyle(.orange)
            }
            modelSourceLabel(
                provider: result.provider.title,
                model: result.model,
                endpointHost: result.endpointHost,
                usage: result.usage
            )
        }
    }

    private func modelSourceLabel(
        provider: String,
        model: String,
        endpointHost: String,
        usage: AssistantUsage?
    )
        -> some View
    {
        Menu {
            Button("\(provider) · \(model)") {}
                .disabled(true)
            Button(endpointHost) {}
                .disabled(true)
            if let usage {
                Divider()
                Button(String(localized: "\(usage.inputTokens) input · \(usage.outputTokens) output")) {}
                    .disabled(true)
            }
        } label: {
            Label(model, systemImage: "cpu")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.mini)
        .font(assistantFont(appMetrics.metadataFontSize, monospaced: true))
        .foregroundStyle(.secondary)
        .help("\(provider) · \(model) · \(endpointHost)")
        .accessibilityLabel(String(localized: "Model details: \(provider), \(model), \(endpointHost)"))
    }

    private func workEvent(title: String, cancel: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(assistantFont(appMetrics.secondaryFontSize, weight: .medium))
            Spacer(minLength: 4)
            Button(String(localized: "Stop"), action: cancel)
                .controlSize(.mini)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completedWorkEvent(_ result: InvestigationResult) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(String(localized: "Local analysis · \(result.scopeTransactionIDs.count) requests"))
                .font(assistantFont(appMetrics.metadataFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureTurn(_ message: String) -> some View {
        assistantBubble {
            Label(
                String(localized: "I couldn’t finish that investigation."),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(assistantFont(appMetrics.secondaryFontSize, weight: .semibold))
            .foregroundStyle(.red)
            Text(message)
                .font(assistantFont(appMetrics.secondaryFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if primaryTransaction != nil {
                Button(String(localized: "Try Again")) {
                    coordinator.startDebugAssistant(.explainFailure)
                }
                .controlSize(.small)
            }
        }
    }

    private func sendDraft() {
        guard canSendDraft else {
            return
        }
        coordinator.sendDebugAssistantMessage()
    }

    private func isCurrentResult(_ result: InvestigationResult) -> Bool {
        guard case let .result(current) = coordinator.activeWorkspace.debugAssistantState else {
            return false
        }
        return current == result
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(Self.transcriptBottomID, anchor: .bottom)
            }
        }
    }

    private func requestSummary(for transaction: HTTPTransaction) -> String {
        let status = transaction.response.map { String($0.statusCode) } ?? "—"
        return "\(transaction.request.method) \(status)  \(transaction.request.host)\(transaction.request.path)"
    }

    private func evidenceColor(_ kind: InvestigationEvidenceKind) -> Color {
        switch kind {
        case .observed: .blue
        case .derived: .purple
        case .inferred: .orange
        case .unknown: .secondary
        }
    }

    private func statusColor(for transaction: HTTPTransaction) -> Color {
        guard let status = transaction.response?.statusCode else {
            return transaction.state == .failed ? .red : .secondary
        }
        switch status {
        case 200 ..< 300: return .green
        case 300 ..< 400: return .blue
        case 400 ..< 500: return .orange
        case 500...: return .red
        default: return .secondary
        }
    }

    private func relativeDateLabel(_ date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 {
            return String(localized: "Now")
        }
        if interval < 3_600 {
            return String(localized: "\(Int(interval / 60))m")
        }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func assistantFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        monospaced: Bool = false
    )
        -> Font
    {
        appMetrics.swiftUIFont(size: size, weight: weight, monospaced: monospaced)
    }
}
