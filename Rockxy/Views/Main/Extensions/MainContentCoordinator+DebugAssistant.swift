import Foundation

// MARK: - MainContentCoordinator + DebugAssistant

extension MainContentCoordinator {
    func sendDebugAssistantMessage() {
        let workspace = activeWorkspace
        let prompt = workspace.debugAssistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return
        }
        workspace.debugAssistantDraft = ""
        guard !resolveSelectedTransactions().isEmpty else {
            if workspace.debugAssistantMessages.isEmpty {
                workspace.debugAssistantConversationTitle = debugAssistantConversationTitle(from: prompt)
                workspace.debugAssistantConversationUpdatedAt = Date()
            }
            workspace.debugAssistantMessages.append(.user(prompt))
            workspace.debugAssistantMessages.append(.assistant(
                String(
                    localized: "I can help investigate captured traffic. Select one or more requests, then ask me what failed, what changed, or what to try next."
                )
            ))
            syncCurrentDebugAssistantConversation(workspace)
            return
        }
        startDebugAssistant(DebugAssistantRecipe.suggestedRecipe(for: prompt), prompt: prompt)
    }

    func startDebugAssistant(_ recipe: DebugAssistantRecipe) {
        startDebugAssistant(recipe, prompt: recipe.prompt)
    }

    func resetDebugAssistantConversation() {
        newDebugAssistantConversation()
    }

    func newDebugAssistantConversation() {
        let workspace = activeWorkspace
        syncCurrentDebugAssistantConversation(workspace)
        clearActiveDebugAssistantState(workspace)
    }

    func selectDebugAssistantConversation(_ conversationID: UUID) {
        let workspace = activeWorkspace
        guard conversationID != workspace.debugAssistantConversationID,
              let conversation = workspace.debugAssistantConversations.first(where: { $0.id == conversationID }) else
        {
            return
        }

        syncCurrentDebugAssistantConversation(workspace)
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantConversationID = conversation.id
        workspace.debugAssistantConversationTitle = conversation.title
        workspace.debugAssistantConversationCreatedAt = conversation.createdAt
        workspace.debugAssistantConversationUpdatedAt = conversation.updatedAt
        workspace.debugAssistantMessages = conversation.messages
        workspace.debugAssistantDraft = ""
        workspace.debugAssistantState = conversation.messages.compactMap(\.investigation).last
            .map(DebugAssistantState.result)
            ?? .idle
        workspace.modelInvestigationState = conversation.messages.compactMap(\.modelResult).last
            .map(ModelInvestigationState.completed) ?? .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
    }

    func renameDebugAssistantConversation(_ conversationID: UUID, title: String) {
        let workspace = activeWorkspace
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }
        if workspace.debugAssistantConversationID == conversationID {
            workspace.debugAssistantConversationTitle = normalized
            workspace.debugAssistantConversationUpdatedAt = Date()
            syncCurrentDebugAssistantConversation(workspace)
            return
        }
        guard let index = workspace.debugAssistantConversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        workspace.debugAssistantConversations[index].title = normalized
        workspace.debugAssistantConversations[index].updatedAt = Date()
    }

    func togglePinnedDebugAssistantConversation(_ conversationID: UUID) {
        let workspace = activeWorkspace
        syncCurrentDebugAssistantConversation(workspace)
        guard let index = workspace.debugAssistantConversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        workspace.debugAssistantConversations[index].isPinned.toggle()
    }

    func deleteDebugAssistantConversation(_ conversationID: UUID) {
        let workspace = activeWorkspace
        workspace.debugAssistantConversations.removeAll { $0.id == conversationID }
        guard workspace.debugAssistantConversationID == conversationID else {
            return
        }
        clearActiveDebugAssistantState(workspace)
    }

    private func startDebugAssistant(_ recipe: DebugAssistantRecipe, prompt: String) {
        let workspace = activeWorkspace
        let selectedTransactions = resolveSelectedTransactions()
        guard !selectedTransactions.isEmpty else {
            workspace.debugAssistantState = .failed(
                message: String(localized: "Select at least one request to investigate.")
            )
            return
        }

        if workspace.debugAssistantMessages.isEmpty {
            workspace.debugAssistantConversationTitle = debugAssistantConversationTitle(from: prompt)
            workspace.debugAssistantConversationUpdatedAt = Date()
        }
        workspace.debugAssistantMessages.append(.user(prompt))
        syncCurrentDebugAssistantConversation(workspace)
        cancelDebugAssistantTask(for: workspace.id)
        let selected = selectedTransactions.map(InvestigationTransactionSnapshot.init(transaction:))
        let session = debugAssistantRelevantTransactions(selected: selectedTransactions)
            .map(InvestigationTransactionSnapshot.init(transaction:))
        let runID = UUID()
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantState = .investigating(runID: runID, recipe: recipe)

        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try DebugAssistantEngine().investigate(
                recipe: recipe,
                selected: selected,
                session: session
            )
            try Task.checkCancellation()
            return result
        }
        debugAssistantTasks[workspace.id] = Task { [weak self] in
            do {
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self,
                      let currentWorkspace = self.workspaceStore.workspaces.first(where: { $0.id == workspace.id }),
                      case let .investigating(currentRunID, _) = currentWorkspace.debugAssistantState,
                      currentRunID == runID else
                {
                    return
                }
                currentWorkspace.debugAssistantState = .result(result)
                currentWorkspace.debugAssistantMessages.append(.assistant(result))
                self.syncCurrentDebugAssistantConversation(currentWorkspace)
                self.debugAssistantTasks[workspace.id] = nil
            } catch is CancellationError {
                self?.debugAssistantTasks[workspace.id] = nil
            } catch {
                guard let self,
                      let currentWorkspace = self.workspaceStore.workspaces.first(where: { $0.id == workspace.id }),
                      case let .investigating(currentRunID, _) = currentWorkspace.debugAssistantState,
                      currentRunID == runID else
                {
                    return
                }
                currentWorkspace.debugAssistantState = .failed(
                    message: error.localizedDescription
                )
                self.debugAssistantTasks[workspace.id] = nil
            }
        }
    }

    func cancelDebugAssistant() {
        let workspace = activeWorkspace
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
    }

    func backToDebugAssistantRecipes() {
        let workspace = activeWorkspace
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
    }

    func prepareDebugAssistantReview() {
        let workspace = activeWorkspace
        guard case let .result(result) = workspace.debugAssistantState else {
            return
        }
        let snapshots = result.scopeTransactionIDs.compactMap { id in
            transaction(for: id).map(InvestigationTransactionSnapshot.init(transaction:))
        }
        guard !snapshots.isEmpty else {
            workspace.debugAssistantState = .failed(
                message: String(localized: "The captured requests are no longer available for review.")
            )
            return
        }

        cancelDebugAssistantTask(for: workspace.id)
        workspace.isPreparingDebugAssistantReview = true
        workspace.debugAssistantReviewPack = nil
        let settingsSnapshot = assistantSettingsProvider()
        workspace.debugAssistantReviewConfiguration = settingsSnapshot.assistantProviderConfiguration
        workspace.debugAssistantReviewModelAccessEnabled = settingsSnapshot.debugAssistantModelAccessEnabled
        let selectedTransactionID = result.selectedTransactionID
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let pack = try InvestigationContextBuilder().build(snapshots: snapshots)
            try Task.checkCancellation()
            return pack
        }
        debugAssistantTasks[workspace.id] = Task { [weak self] in
            do {
                let pack = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self,
                      let currentWorkspace = self.workspaceStore.workspaces.first(where: { $0.id == workspace.id }),
                      case let .result(currentResult) = currentWorkspace.debugAssistantState,
                      currentResult.selectedTransactionID == selectedTransactionID else
                {
                    return
                }
                currentWorkspace.isPreparingDebugAssistantReview = false
                currentWorkspace.debugAssistantReviewPack = pack
                self.debugAssistantTasks[workspace.id] = nil
            } catch is CancellationError {
                self?.workspaceStore.workspaces.first(where: { $0.id == workspace.id })?
                    .isPreparingDebugAssistantReview = false
                self?.debugAssistantTasks[workspace.id] = nil
            } catch {
                guard let self,
                      let currentWorkspace = self.workspaceStore.workspaces.first(where: { $0.id == workspace.id }) else
                {
                    return
                }
                currentWorkspace.isPreparingDebugAssistantReview = false
                currentWorkspace.debugAssistantState = .failed(message: error.localizedDescription)
                self.debugAssistantTasks[workspace.id] = nil
            }
        }
    }

    func dismissDebugAssistantReview() {
        let workspace = activeWorkspace
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
    }

    func sendDebugAssistantReview() {
        let workspace = activeWorkspace
        guard case let .result(result) = workspace.debugAssistantState,
              let pack = workspace.debugAssistantReviewPack else
        {
            return
        }

        let settings = assistantSettingsProvider()
        guard workspace.debugAssistantReviewModelAccessEnabled,
              settings.debugAssistantModelAccessEnabled else
        {
            workspace.modelInvestigationState = .failed(
                message: String(localized: "Enable model access in AI Assistant Settings before sending data.")
            )
            return
        }
        guard let configuration = workspace.debugAssistantReviewConfiguration,
              configuration.isComplete,
              settings.assistantProviderConfiguration == configuration else
        {
            workspace.modelInvestigationState = .failed(
                message: String(localized: "The provider configuration changed. Review the outbound data again.")
            )
            dismissDebugAssistantReview()
            return
        }

        cancelDebugAssistantTask(for: workspace.id)
        let runID = UUID()
        let selectedTransactionID = result.selectedTransactionID
        let request = AssistantPromptBuilder().build(
            result: result,
            pack: pack,
            configuration: configuration
        )
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.modelInvestigationState = .streaming(
            runID: runID,
            provider: configuration.kind,
            model: configuration.model,
            endpointHost: configuration.endpointHost,
            text: ""
        )

        debugAssistantTasks[workspace.id] = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let stream = try await assistantRuntime.stream(
                    request: request,
                    configuration: configuration
                )
                var text = ""
                var usage: AssistantUsage?
                var toolCalls: [AssistantToolCall] = []
                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case let .textDelta(delta):
                        guard text.utf8.count + delta.utf8.count <= AssistantExecutionLimits.maxOutputBytes else {
                            throw AssistantProviderError.malformedResponse(
                                "The streamed model output exceeded Rockxy's size limit"
                            )
                        }
                        text += delta
                        guard self.isCurrentModelRun(
                            workspaceID: workspace.id,
                            runID: runID,
                            selectedTransactionID: selectedTransactionID
                        ) else {
                            return
                        }
                        workspace.modelInvestigationState = .streaming(
                            runID: runID,
                            provider: configuration.kind,
                            model: configuration.model,
                            endpointHost: configuration.endpointHost,
                            text: text
                        )
                    case let .usage(value):
                        usage = value
                    case let .toolCallCompleted(call):
                        guard toolCalls.count < AssistantExecutionLimits.maxToolCalls,
                              call.arguments.utf8.count <= AssistantExecutionLimits.maxToolArgumentBytes else
                        {
                            throw AssistantProviderError.malformedResponse(
                                "The streamed tool calls exceeded Rockxy's size limit"
                            )
                        }
                        toolCalls.append(call)
                    case .started,
                         .toolCallDelta,
                         .completed,
                         .unknown:
                        break
                    }
                }

                guard self.isCurrentModelRun(
                    workspaceID: workspace.id,
                    runID: runID,
                    selectedTransactionID: selectedTransactionID
                ) else {
                    return
                }
                let modelResult = ModelInvestigationResult(
                    provider: configuration.kind,
                    model: configuration.model,
                    endpointHost: configuration.endpointHost,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    usage: usage,
                    toolCalls: toolCalls
                )
                workspace.modelInvestigationState = .completed(modelResult)
                workspace.debugAssistantMessages.append(.assistant(modelResult))
                self.syncCurrentDebugAssistantConversation(workspace)
                self.debugAssistantTasks[workspace.id] = nil
            } catch is CancellationError {
                self.debugAssistantTasks[workspace.id] = nil
            } catch AssistantProviderError.cancelled {
                self.debugAssistantTasks[workspace.id] = nil
            } catch {
                guard self.isCurrentModelRun(
                    workspaceID: workspace.id,
                    runID: runID,
                    selectedTransactionID: selectedTransactionID
                ) else {
                    return
                }
                workspace.modelInvestigationState = .failed(message: error.localizedDescription)
                self.debugAssistantTasks[workspace.id] = nil
            }
        }
    }

    func cancelDebugAssistantModelAnalysis() {
        let workspace = activeWorkspace
        cancelDebugAssistantTask(for: workspace.id)
        workspace.modelInvestigationState = .idle
    }

    func revealDebugAssistantEvidence(_ evidence: InvestigationEvidence) {
        guard let id = evidence.sourceTransactionID,
              let transaction = transaction(for: id) else
        {
            return
        }
        let workspace = activeWorkspace
        workspace.selectedTransactionIDs = [id]
        workspace.selectedTransaction = transaction
        revealInspectorForSelectionIfNeeded()
    }

    func resetDebugAssistantForSelectionChange() {
        let workspace = activeWorkspace
        syncCurrentDebugAssistantConversation(workspace)
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
    }

    // MARK: Private

    private func cancelDebugAssistantTask(for workspaceID: UUID) {
        debugAssistantTasks[workspaceID]?.cancel()
        debugAssistantTasks[workspaceID] = nil
    }

    private func clearActiveDebugAssistantState(_ workspace: WorkspaceState) {
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantMessages.removeAll()
        workspace.debugAssistantDraft = ""
        workspace.debugAssistantConversationID = UUID()
        workspace.debugAssistantConversationTitle = String(localized: "New Conversation")
        workspace.debugAssistantConversationCreatedAt = Date()
        workspace.debugAssistantConversationUpdatedAt = Date()
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
    }

    private func syncCurrentDebugAssistantConversation(_ workspace: WorkspaceState) {
        guard !workspace.debugAssistantMessages.isEmpty else {
            return
        }
        let existingConversation = workspace.debugAssistantConversations.first {
            $0.id == workspace.debugAssistantConversationID
        }
        if existingConversation?.messages != workspace.debugAssistantMessages {
            workspace.debugAssistantConversationUpdatedAt = Date()
        }
        let conversation = DebugAssistantConversation(
            id: workspace.debugAssistantConversationID,
            title: workspace.debugAssistantConversationTitle,
            messages: workspace.debugAssistantMessages,
            createdAt: workspace.debugAssistantConversationCreatedAt,
            updatedAt: workspace.debugAssistantConversationUpdatedAt,
            isPinned: existingConversation?.isPinned ?? false
        )
        if let index = workspace.debugAssistantConversations.firstIndex(where: { $0.id == conversation.id }) {
            workspace.debugAssistantConversations[index] = conversation
        } else {
            workspace.debugAssistantConversations.append(conversation)
        }
    }

    private func debugAssistantConversationTitle(from prompt: String) -> String {
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard normalized.count > 42 else {
            return normalized
        }
        let cutoff = normalized.index(normalized.startIndex, offsetBy: 39)
        return String(normalized[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func isCurrentModelRun(
        workspaceID: UUID,
        runID: UUID,
        selectedTransactionID: UUID
    )
        -> Bool
    {
        guard let workspace = workspaceStore.workspaces.first(where: { $0.id == workspaceID }),
              case let .result(result) = workspace.debugAssistantState,
              result.selectedTransactionID == selectedTransactionID,
              case let .streaming(currentRunID, _, _, _, _) = workspace.modelInvestigationState else
        {
            return false
        }
        return currentRunID == runID
    }

    private func debugAssistantSessionTransactions() -> [HTTPTransaction] {
        var values: [HTTPTransaction] = []
        var seen: Set<UUID> = []
        for transaction in transactions + persistedFavorites where seen.insert(transaction.id).inserted {
            values.append(transaction)
        }
        return values
    }

    private func debugAssistantRelevantTransactions(selected: [HTTPTransaction]) -> [HTTPTransaction] {
        guard let primary = selected.first else {
            return []
        }
        var values = selected
        var seen = Set(selected.map(\.id))
        let related = debugAssistantSessionTransactions()
            .filter { $0.id != primary.id && $0.request.host == primary.request.host }
            .sorted {
                abs($0.timestamp.timeIntervalSince(primary.timestamp))
                    < abs($1.timestamp.timeIntervalSince(primary.timestamp))
            }
        for transaction in related.prefix(20) where seen.insert(transaction.id).inserted {
            values.append(transaction)
        }
        return values
    }
}
