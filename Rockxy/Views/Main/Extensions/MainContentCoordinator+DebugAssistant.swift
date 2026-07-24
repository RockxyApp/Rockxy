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
        guard !debugAssistantSelectedTransactions().isEmpty else {
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

    func presentDebugAssistant(
        for primary: HTTPTransaction,
        contextSelectionIDs: Set<UUID>
    ) {
        let validSelectionIDs = Set(
            contextSelectionIDs.filter { transaction(for: $0) != nil }
        )
        let effectiveSelectionIDs = validSelectionIDs.contains(primary.id)
            ? validSelectionIDs
            : Set([primary.id])

        selectedTransactionIDs = effectiveSelectionIDs
        selectTransaction(primary)

        let workspace = activeWorkspace
        workspace.activeMainTab = .traffic
        workspace.contextDockTab = .aiAssistant
        workspace.isDebugAssistantComposerFocusRequested = true
        setContextDockVisible(true)
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
        let latestInvestigation = conversation.messages.compactMap(\.investigation).last
        workspace.debugAssistantState = latestInvestigation.flatMap { result in
            workspace.selectedTransactionIDs.contains(result.selectedTransactionID)
                ? DebugAssistantState.result(result)
                : nil
        } ?? .idle
        workspace.modelInvestigationState = conversation.messages.compactMap(\.modelResult).last
            .map(ModelInvestigationState.completed) ?? .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
        workspace.debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
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
        let selectedTransactions = debugAssistantSelectedTransactions()
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
        let session = debugAssistantContextTransactions()
            .map(InvestigationTransactionSnapshot.init(transaction:))
        let runID = UUID()
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
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
        let taskID = UUID()
        let task = Task { [weak self] in
            defer {
                self?.clearDebugAssistantTask(for: workspace.id, matching: taskID)
            }
            do {
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self,
                      self.debugAssistantTasks[workspace.id]?.id == taskID,
                      let currentWorkspace = self.workspaceStore.workspaces.first(where: { $0.id == workspace.id }),
                      case let .investigating(currentRunID, _) = currentWorkspace.debugAssistantState,
                      currentRunID == runID else
                {
                    return
                }
                currentWorkspace.debugAssistantState = .result(result)
                self.clearDebugAssistantTask(for: workspace.id, matching: taskID)
                if self.shouldAutomaticallyUseConfiguredModel(currentWorkspace) {
                    self.prepareDebugAssistantReview(for: currentWorkspace, result: result)
                } else {
                    currentWorkspace.debugAssistantMessages.append(.assistant(result))
                    self.syncCurrentDebugAssistantConversation(currentWorkspace)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.debugAssistantTasks[workspace.id]?.id == taskID,
                      let currentWorkspace = self.workspaceStore.workspaces.first(where: { $0.id == workspace.id }),
                      case let .investigating(currentRunID, _) = currentWorkspace.debugAssistantState,
                      currentRunID == runID else
                {
                    return
                }
                currentWorkspace.debugAssistantState = .failed(
                    message: error.localizedDescription
                )
            }
        }
        debugAssistantTasks[workspace.id] = DebugAssistantTaskHandle(id: taskID, task: task)
    }

    func cancelDebugAssistant() {
        let workspace = activeWorkspace
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
    }

    func backToDebugAssistantRecipes() {
        let workspace = activeWorkspace
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
    }

    func prepareDebugAssistantReview() {
        let workspace = activeWorkspace
        guard case let .result(result) = workspace.debugAssistantState else {
            return
        }
        prepareDebugAssistantReview(for: workspace, result: result)
    }

    private func prepareDebugAssistantReview(
        for workspace: WorkspaceState,
        result: InvestigationResult
    ) {
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
        workspace.debugAssistantReviewRequest = nil
        let settingsSnapshot = assistantSettingsProvider()
        workspace.debugAssistantReviewConfiguration = settingsSnapshot.assistantProviderConfiguration
        workspace.debugAssistantReviewTrafficScope = workspace.debugAssistantTrafficScope
        workspace.debugAssistantReviewModelAccessEnabled = settingsSnapshot.debugAssistantModelAccessEnabled
        let contextLimits = settingsSnapshot.assistantProviderConfiguration.map {
            AssistantContextBudgeter().contextLimits(for: $0)
        } ?? .default
        let selectedTransactionID = result.selectedTransactionID
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let pack = try InvestigationContextBuilder().build(
                snapshots: snapshots,
                limits: contextLimits
            )
            try Task.checkCancellation()
            return pack
        }
        let taskID = UUID()
        let task = Task { [weak self] in
            defer {
                self?.clearDebugAssistantTask(for: workspace.id, matching: taskID)
            }
            do {
                let pack = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self,
                      self.debugAssistantTasks[workspace.id]?.id == taskID,
                      let currentWorkspace = self.workspaceStore.workspaces.first(where: { $0.id == workspace.id }),
                      case let .result(currentResult) = currentWorkspace.debugAssistantState,
                      currentResult.selectedTransactionID == selectedTransactionID else
                {
                    return
                }
                currentWorkspace.isPreparingDebugAssistantReview = false
                currentWorkspace.debugAssistantReviewPack = pack
                currentWorkspace.debugAssistantReviewRequest = currentWorkspace
                    .debugAssistantReviewConfiguration
                    .map { configuration in
                        AssistantPromptBuilder().build(
                            result: currentResult,
                            pack: pack,
                            configuration: configuration,
                            conversation: currentWorkspace.debugAssistantMessages
                        )
                    }
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.debugAssistantTasks[workspace.id]?.id == taskID,
                      let currentWorkspace = self.workspaceStore.workspaces.first(where: { $0.id == workspace.id }) else
                {
                    return
                }
                currentWorkspace.isPreparingDebugAssistantReview = false
                currentWorkspace.debugAssistantState = .failed(message: error.localizedDescription)
            }
        }
        debugAssistantTasks[workspace.id] = DebugAssistantTaskHandle(id: taskID, task: task)
    }

    func dismissDebugAssistantReview() {
        let workspace = activeWorkspace
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
    }

    func sendDebugAssistantReview() {
        let workspace = activeWorkspace
        guard case let .result(result) = workspace.debugAssistantState,
              let pack = workspace.debugAssistantReviewPack,
              let request = workspace.debugAssistantReviewRequest else
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
        guard workspace.debugAssistantReviewTrafficScope == workspace.debugAssistantTrafficScope,
              AssistantTrustPolicy.isReviewedScopeValid(pack, for: result) else
        {
            workspace.modelInvestigationState = .failed(
                message: String(localized: "The traffic scope changed. Review the exact data again before model access.")
            )
            dismissDebugAssistantReview()
            return
        }

        cancelDebugAssistantTask(for: workspace.id)
        let runID = UUID()
        let selectedTransactionID = result.selectedTransactionID
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.modelInvestigationState = .streaming(
            runID: runID,
            provider: configuration.kind,
            model: configuration.model,
            endpointHost: configuration.endpointHost,
            text: ""
        )

        let taskID = UUID()
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.clearDebugAssistantTask(for: workspace.id, matching: taskID)
            }
            do {
                let stream = try await assistantRuntime.stream(
                    request: request,
                    configuration: configuration
                )
                var textBuffer = AssistantStreamingTextBuffer(
                    startedAt: ProcessInfo.processInfo.systemUptime
                )
                var usage: AssistantUsage?
                var blockedToolCallCount = 0
                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case let .textDelta(delta):
                        let shouldPublish = try textBuffer.append(
                            delta,
                            at: ProcessInfo.processInfo.systemUptime
                        )
                        guard shouldPublish else {
                            continue
                        }
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
                            text: textBuffer.text
                        )
                        await Task.yield()
                    case let .usage(value):
                        usage = value
                    case let .toolCallCompleted(call):
                        guard blockedToolCallCount < AssistantExecutionLimits.maxToolCalls,
                              call.arguments.utf8.count <= AssistantExecutionLimits.maxToolArgumentBytes else
                        {
                            throw AssistantProviderError.malformedResponse(
                                "The streamed tool calls exceeded Rockxy's size limit"
                            )
                        }
                        blockedToolCallCount += 1
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
                let groundedText = AssistantResponseGrounder().finalize(
                    textBuffer.text,
                    against: result,
                    userQuestion: workspace.debugAssistantMessages
                        .last(where: { $0.role == .user })?
                        .text
                )
                let modelResult = ModelInvestigationResult(
                    provider: configuration.kind,
                    model: configuration.model,
                    endpointHost: configuration.endpointHost,
                    text: groundedText,
                    usage: usage,
                    blockedToolCallCount: blockedToolCallCount
                )
                workspace.modelInvestigationState = .completed(modelResult)
                workspace.debugAssistantMessages.append(.assistant(
                    modelResult,
                    investigation: result
                ))
                self.syncCurrentDebugAssistantConversation(workspace)
            } catch is CancellationError {
                return
            } catch AssistantProviderError.cancelled {
                return
            } catch {
                guard self.isCurrentModelRun(
                    workspaceID: workspace.id,
                    runID: runID,
                    selectedTransactionID: selectedTransactionID
                ) else {
                    return
                }
                workspace.modelInvestigationState = .failed(message: error.localizedDescription)
            }
        }
        debugAssistantTasks[workspace.id] = DebugAssistantTaskHandle(id: taskID, task: task)
    }

    func cancelDebugAssistantModelAnalysis() {
        let workspace = activeWorkspace
        cancelDebugAssistantTask(for: workspace.id)
        workspace.modelInvestigationState = .idle
    }

    func prepareDebugAssistantFollowUp(for result: InvestigationResult?) {
        let workspace = activeWorkspace
        guard workspace.debugAssistantDraft
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
        {
            return
        }

        workspace.debugAssistantDraft = switch result?.recipe {
        case .explainRequest:
            String(localized: "What should I inspect next in Rockxy?")
        case .explainFailure:
            String(localized: "Show me how to verify the leading cause in Rockxy.")
        case .compareWithSuccess:
            String(localized: "Which captured difference should I verify first?")
        case .checkAuthentication:
            String(localized: "What authentication evidence should I verify next?")
        case .prepareBugReport:
            String(localized: "What should I add before sharing this bug report?")
        case nil:
            String(localized: "What should I inspect next in Rockxy?")
        }
    }

    func revealDebugAssistantEvidence(_ evidence: InvestigationEvidence) {
        guard let id = evidence.sourceTransactionID else
        {
            return
        }
        revealDebugAssistantRequest(id: id)
    }

    func revealDebugAssistantRequest(id: UUID) {
        guard let transaction = transaction(for: id) else {
            activeToast = ToastMessage(
                style: .error,
                text: String(localized: "That captured request is no longer available.")
            )
            return
        }

        let workspace = activeWorkspace
        workspace.activeMainTab = .traffic
        if !workspace.filteredTransactions.contains(where: { $0.id == id }) {
            workspace.filterCriteria = .empty
            workspace.sidebarSelection = nil
            recomputeFilteredTransactions()
        }
        workspace.selectedTransactionIDs = [id]
        workspace.selectedTransaction = transaction
        workspace.contextDockTab = .details
        setContextDockVisible(true)
        revealInspectorForSelectionIfNeeded()
    }

    func setDebugAssistantTrafficScope(_ scope: AssistantTrafficScope) {
        let workspace = activeWorkspace
        guard workspace.debugAssistantTrafficScope != scope else {
            return
        }
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantTrafficScope = scope
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
    }

    func performUserInitiatedDebugAssistantHandoff(
        _ handoff: AssistantUserHandoff,
        result: InvestigationResult
    ) {
        let workspace = activeWorkspace
        guard case let .result(currentResult) = workspace.debugAssistantState,
              currentResult == result,
              workspace.selectedTransactionIDs.contains(result.selectedTransactionID),
              let primary = transaction(for: result.selectedTransactionID) else
        {
            activeToast = ToastMessage(
                style: .error,
                text: String(localized: "Select the original request and run the investigation again.")
            )
            return
        }

        switch handoff {
        case .prepareReplay,
             .compose:
            editAndReplayTransaction(primary)
        case .export:
            presentSelectedExport(format: .har)
        case .share:
            reviewSelectedTransactionsForGist()
        }
    }

    func debugAssistantSelectedTransactions() -> [HTTPTransaction] {
        let selected = resolveSelectedTransactions()
        guard let primary = selectedTransaction,
              selectedTransactionIDs.contains(primary.id),
              let primaryIndex = selected.firstIndex(where: { $0.id == primary.id }) else
        {
            return selected
        }
        var ordered = selected
        ordered.remove(at: primaryIndex)
        ordered.insert(primary, at: 0)
        return ordered
    }

    func debugAssistantContextTransactions() -> [HTTPTransaction] {
        let selected = debugAssistantSelectedTransactions()
        let maximumCount = InvestigationContextLimits.default.maxTransactions
        let boundedSelection = Array(selected.prefix(maximumCount))
        guard activeWorkspace.debugAssistantTrafficScope == .selectedAndRelated,
              let primary = boundedSelection.first else
        {
            return boundedSelection
        }
        var values = boundedSelection
        var seen = Set(boundedSelection.map(\.id))
        for transaction in debugAssistantRelatedTransactions(to: primary)
            where seen.insert(transaction.id).inserted
        {
            guard values.count < maximumCount else {
                break
            }
            values.append(transaction)
        }
        return values
    }

    func debugAssistantRelatedTransactionCount() -> Int {
        guard let primary = debugAssistantSelectedTransactions().first else {
            return 0
        }
        let selectedIDs = selectedTransactionIDs
        let availableCount = debugAssistantRelatedTransactions(to: primary)
            .filter { !selectedIDs.contains($0.id) }
            .count
        let remainingCapacity = max(
            0,
            InvestigationContextLimits.default.maxTransactions - debugAssistantSelectedTransactions().count
        )
        return min(availableCount, remainingCapacity)
    }

    func resetDebugAssistantForSelectionChange() {
        let workspace = activeWorkspace
        syncCurrentDebugAssistantConversation(workspace)
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
        workspace.debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
    }

    // MARK: Private

    private func cancelDebugAssistantTask(for workspaceID: UUID) {
        debugAssistantTasks.removeValue(forKey: workspaceID)?.task.cancel()
    }

    func clearDebugAssistantTask(for workspaceID: UUID, matching taskID: UUID) {
        guard debugAssistantTasks[workspaceID]?.id == taskID else {
            return
        }
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
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.isPreparingDebugAssistantReview = false
        workspace.debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
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

    private func shouldAutomaticallyUseConfiguredModel(_ workspace: WorkspaceState) -> Bool {
        guard workspace.debugAssistantUsesConfiguredModel else {
            return false
        }
        let settings = assistantSettingsProvider()
        return settings.debugAssistantModelAccessEnabled
            && settings.assistantProviderConfiguration?.isComplete == true
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

    private func debugAssistantRelatedTransactions(to primary: HTTPTransaction) -> [HTTPTransaction] {
        debugAssistantSessionTransactions()
            .filter { $0.id != primary.id && $0.request.host == primary.request.host }
            .sorted {
                abs($0.timestamp.timeIntervalSince(primary.timestamp))
                    < abs($1.timestamp.timeIntervalSince(primary.timestamp))
            }
            .prefix(20)
            .map { $0 }
    }
}
