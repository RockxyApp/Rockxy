import Foundation

// MARK: - MainContentCoordinator + DebugAssistant

extension MainContentCoordinator {
    func sendDebugAssistantMessage() {
        let workspace = activeWorkspace
        let prompt = workspace.debugAssistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return
        }
        guard !debugAssistantConversationHasContextMismatch() else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(localized: "Restore this conversation's traffic or start a new conversation.", bundle: RockxyLocalization.bundle)
            )
            return
        }
        guard prompt.utf8.count <= DebugAssistantConversationLimits.maximumPromptBytes else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(localized: "Shorten this message before sending it to the Assistant.", bundle: RockxyLocalization.bundle)
            )
            return
        }
        workspace.debugAssistantDraft = ""
        guard !debugAssistantSelectedTransactions().isEmpty else {
            // No selected traffic: answer the Rockxy product/workflow question. The conversation
            // stays context-free and renders as a normal plain assistant response — never a fake
            // traffic investigation.
            sendDebugAssistantProductHelp(prompt: prompt)
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
        workspace.debugAssistantConversationContext = conversation.context
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
        workspace.debugAssistantProductHelpState = .idle
        resetDebugAssistantReviewState(workspace)
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
        if !workspace.debugAssistantConversations[index].isPinned,
           workspace.debugAssistantConversations.count(where: \.isPinned)
           >= DebugAssistantConversationLimits.maximumPinnedConversationsPerWorkspace
        {
            activeToast = ToastMessage(
                style: .warning,
                text: String(localized: "Unpin another Assistant conversation before pinning this one.", bundle: RockxyLocalization.bundle)
            )
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
                message: String(localized: "Select at least one request to investigate.", bundle: RockxyLocalization.bundle)
            )
            return
        }
        guard let conversationContext = currentDebugAssistantConversationContext() else {
            return
        }
        if let existingContext = workspace.debugAssistantConversationContext,
           !existingContext.matches(
               primaryTransactionID: conversationContext.primaryTransactionID,
               selectedTransactionIDs: conversationContext.selectedTransactionIDs,
               requestedSelectionCount: conversationContext.requestedSelectionCount
           )
        {
            activeToast = ToastMessage(
                style: .warning,
                text: String(localized: "Restore this conversation's traffic or start a new conversation.", bundle: RockxyLocalization.bundle)
            )
            return
        }
        workspace.debugAssistantConversationContext = conversationContext

        if workspace.debugAssistantMessages.isEmpty {
            workspace.debugAssistantConversationTitle = debugAssistantConversationTitle(from: prompt)
            workspace.debugAssistantConversationUpdatedAt = Date()
        }
        workspace.debugAssistantMessages.append(.user(prompt))
        syncCurrentDebugAssistantConversation(workspace)
        cancelDebugAssistantTask(for: workspace.id)
        let contextTransactions = debugAssistantContextTransactions()
        let boundedSelected = Array(
            selectedTransactions.prefix(InvestigationContextLimits.default.maxTransactions)
        )
        let selected = boundedSelected.map(InvestigationTransactionSnapshot.init(transaction:))
        let session = contextTransactions
            .map(InvestigationTransactionSnapshot.init(transaction:))
        let runID = UUID()
        resetDebugAssistantReviewState(workspace)
        workspace.debugAssistantRequestedContextCount = selectedTransactions.count
            + (workspace.debugAssistantTrafficScope == .selectedAndRelated
                ? debugAssistantAvailableRelatedTransactionCount()
                : 0)
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantProductHelpState = .idle
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
                      let currentWorkspace = self.workspaceStore.allWorkspaces.first(where: { $0.id == workspace.id }),
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
                      let currentWorkspace = self.workspaceStore.allWorkspaces.first(where: { $0.id == workspace.id }),
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
        resetDebugAssistantReviewState(workspace)
    }

    func backToDebugAssistantRecipes() {
        let workspace = activeWorkspace
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        resetDebugAssistantReviewState(workspace)
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
                message: String(localized: "The captured requests are no longer available for review.", bundle: RockxyLocalization.bundle)
            )
            return
        }

        cancelDebugAssistantTask(for: workspace.id)
        workspace.isPreparingDebugAssistantReview = true
        workspace.isPreparingDebugAssistantReviewOverride = false
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewSummary = nil
        let settingsSnapshot = assistantSettingsProvider()
        workspace.debugAssistantReviewConfiguration = settingsSnapshot.assistantProviderConfiguration
        workspace.debugAssistantReviewTrafficScope = workspace.debugAssistantTrafficScope
        workspace.debugAssistantReviewModelAccessEnabled = settingsSnapshot.debugAssistantModelAccessEnabled
        let contextLimits = settingsSnapshot.assistantProviderConfiguration.map {
            AssistantContextBudgeter().contextLimits(for: $0)
        } ?? .default
        let selectedTransactionID = result.selectedTransactionID
        let requestedTransactionCount = workspace.debugAssistantRequestedContextCount
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let pack = try InvestigationContextBuilder().build(
                snapshots: snapshots,
                requestedTransactionCount: requestedTransactionCount,
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
                      let currentWorkspace = self.workspaceStore.allWorkspaces.first(where: { $0.id == workspace.id }),
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
                currentWorkspace.debugAssistantReviewSummary = self.makeDebugAssistantReviewSummary(
                    result: currentResult,
                    pack: pack,
                    scope: currentWorkspace.debugAssistantTrafficScope,
                    overrideApplied: false
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.debugAssistantTasks[workspace.id]?.id == taskID,
                      let currentWorkspace = self.workspaceStore.allWorkspaces.first(where: { $0.id == workspace.id }) else
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
        if workspace.isPreparingDebugAssistantReviewOverride {
            cancelDebugAssistantTask(for: workspace.id)
        }
        workspace.isPreparingDebugAssistantReviewOverride = false
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.debugAssistantReviewSummary = nil
    }

    func sendDebugAssistantReview() {
        let workspace = activeWorkspace
        guard !workspace.isPreparingDebugAssistantReviewOverride else {
            return
        }
        guard case let .result(result) = workspace.debugAssistantState,
              let pack = workspace.debugAssistantReviewPack,
              let request = workspace.debugAssistantReviewRequest else
        {
            return
        }

        guard let configuration = validatedDebugAssistantReviewConfiguration(
            workspace: workspace,
            result: result,
            pack: pack
        ) else {
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
        workspace.debugAssistantReviewSummary = nil
        workspace.isPreparingDebugAssistantReviewOverride = false
        workspace.modelInvestigationState = .streaming(
            runID: runID,
            provider: configuration.kind,
            executionLocation: configuration.executionLocation,
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
                            executionLocation: configuration.executionLocation,
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

    /// One-time include-excluded override for the current review. Rebuilds the opted-in related
    /// context from the unfiltered nearest set while leaving Focus/Noise settings untouched, then
    /// atomically republishes the deterministic result, prompt, pack, and summary under the same id.
    func applyDebugAssistantReviewFocusNoiseOverride() {
        let workspace = activeWorkspace
        guard case let .result(result) = workspace.debugAssistantState,
              let previousPack = workspace.debugAssistantReviewPack,
              workspace.debugAssistantReviewSummary?.canOverrideFocusNoise == true,
              !workspace.isPreparingDebugAssistantReviewOverride,
              workspace.debugAssistantTrafficScope == .selectedAndRelated,
              let primary = transaction(for: result.selectedTransactionID),
              selectedTransactionIDs.contains(primary.id) else
        {
            return
        }

        let boundedSelected = Array(
            debugAssistantSelectedTransactions().prefix(InvestigationContextLimits.default.maxTransactions)
        )
        let rawRelatedCount = debugAssistantRawRelatedCandidates(for: primary).count
        let overrideSnapshots = debugAssistantContextTransactions(ignoringFocusNoise: true)
            .map(InvestigationTransactionSnapshot.init(transaction:))
        let selectedSnapshots = Array(overrideSnapshots.prefix(boundedSelected.count))
        let snapshotByID = Dictionary(
            overrideSnapshots.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let requestedCount = boundedSelected.count + rawRelatedCount

        let settingsSnapshot = assistantSettingsProvider()
        let configuration = settingsSnapshot.assistantProviderConfiguration
        let contextLimits = configuration.map {
            AssistantContextBudgeter().contextLimits(for: $0)
        } ?? .default
        let recipe = result.recipe
        let previousPackID = previousPack.id
        let scope = workspace.debugAssistantTrafficScope
        let conversationID = workspace.debugAssistantConversationID
        let selectedIDsAtStart = workspace.selectedTransactionIDs

        cancelDebugAssistantTask(for: workspace.id)
        workspace.isPreparingDebugAssistantReviewOverride = true
        workspace.debugAssistantReviewConfiguration = configuration
        workspace.debugAssistantReviewTrafficScope = scope
        workspace.debugAssistantReviewModelAccessEnabled = settingsSnapshot.debugAssistantModelAccessEnabled

        let worker = Task
            .detached(priority: .userInitiated) { () -> (InvestigationResult, InvestigationContextPack) in
                try Task.checkCancellation()
                let newResult = try DebugAssistantEngine().investigate(
                    recipe: recipe,
                    selected: selectedSnapshots,
                    session: overrideSnapshots
                )
                try Task.checkCancellation()
                let scopeSnapshots = newResult.scopeTransactionIDs.compactMap { snapshotByID[$0] }
                let builtPack = try InvestigationContextBuilder().build(
                    snapshots: scopeSnapshots,
                    requestedTransactionCount: requestedCount,
                    limits: contextLimits
                )
                try Task.checkCancellation()
                return (newResult, InvestigationContextPack(
                    id: previousPackID,
                    scopeTransactionIDs: builtPack.scopeTransactionIDs,
                    payload: builtPack.payload,
                    preview: builtPack.preview,
                    manifest: builtPack.manifest
                ))
            }
        let taskID = UUID()
        let task = Task { [weak self] in
            defer {
                self?.clearDebugAssistantTask(for: workspace.id, matching: taskID)
            }
            do {
                let (newResult, pack) = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard let self,
                      self.debugAssistantTasks[workspace.id]?.id == taskID,
                      let currentWorkspace = self.workspaceStore.allWorkspaces.first(where: { $0.id == workspace.id }),
                      case let .result(currentResult) = currentWorkspace.debugAssistantState,
                      currentResult == result,
                      currentWorkspace.debugAssistantTrafficScope == scope,
                      currentWorkspace.debugAssistantConversationID == conversationID,
                      currentWorkspace.selectedTransactionIDs == selectedIDsAtStart else
                {
                    return
                }
                self.publishDebugAssistantOverride(
                    to: currentWorkspace,
                    previousResult: result,
                    newResult: newResult,
                    pack: pack,
                    requestedCount: requestedCount,
                    scope: scope
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.debugAssistantTasks[workspace.id]?.id == taskID,
                      let currentWorkspace = self.workspaceStore.allWorkspaces
                      .first(where: { $0.id == workspace.id }) else
                {
                    return
                }
                currentWorkspace.isPreparingDebugAssistantReviewOverride = false
                self.activeToast = ToastMessage(
                    style: .warning,
                    text: String(localized: "Rockxy could not include the excluded traffic. The reviewed data is unchanged.", bundle: RockxyLocalization.bundle)
                )
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
        guard !debugAssistantConversationHasContextMismatch() else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(localized: "Restore this conversation's traffic before following up.", bundle: RockxyLocalization.bundle)
            )
            return
        }
        guard workspace.debugAssistantDraft
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
        {
            return
        }

        workspace.debugAssistantDraft = switch result?.recipe {
        case .explainRequest:
            String(localized: "What should I inspect next in Rockxy?", bundle: RockxyLocalization.bundle)
        case .explainFailure:
            String(localized: "Show me how to verify the leading cause in Rockxy.", bundle: RockxyLocalization.bundle)
        case .compareWithSuccess:
            String(localized: "Which captured difference should I verify first?", bundle: RockxyLocalization.bundle)
        case .checkAuthentication:
            String(localized: "What authentication evidence should I verify next?", bundle: RockxyLocalization.bundle)
        case .prepareBugReport:
            String(localized: "What should I add before sharing this bug report?", bundle: RockxyLocalization.bundle)
        case nil:
            String(localized: "What should I inspect next in Rockxy?", bundle: RockxyLocalization.bundle)
        }
    }

    func revealDebugAssistantEvidence(_ evidence: InvestigationEvidence) {
        guard let id = evidence.sourceTransactionID else {
            return
        }
        revealDebugAssistantRequest(id: id)
    }

    func revealDebugAssistantRequest(id: UUID) {
        guard let transaction = transaction(for: id) else {
            activeToast = ToastMessage(
                style: .error,
                text: String(localized: "That captured request is no longer available.", bundle: RockxyLocalization.bundle)
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
        resetDebugAssistantReviewState(workspace)
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
                text: String(localized: "Select the original request and run the investigation again.", bundle: RockxyLocalization.bundle)
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

    /// Selected transactions (always first, unfiltered) plus automatically discovered related
    /// requests. In normal mode related candidates obey the active Focus/Noise scope; the one-time
    /// review override passes `ignoringFocusNoise: true` to reconsider the full nearest set.
    func debugAssistantContextTransactions(ignoringFocusNoise: Bool = false) -> [HTTPTransaction] {
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
        let related = ignoringFocusNoise
            ? debugAssistantRawRelatedCandidates(for: primary)
            : debugAssistantRelatedPartition(for: primary).eligible
        for transaction in related where seen.insert(transaction.id).inserted {
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
        let eligibleCount = debugAssistantRelatedPartition(for: primary).eligible.count
        let remainingCapacity = max(
            0,
            InvestigationContextLimits.default.maxTransactions - debugAssistantSelectedTransactions().count
        )
        return min(eligibleCount, remainingCapacity)
    }

    /// Raw nearest related candidates for the primary request, excluding explicitly selected IDs.
    /// Selection identity always wins over Focus/Noise, so selected transactions are never here.
    func debugAssistantRawRelatedCandidates(for primary: HTTPTransaction) -> [HTTPTransaction] {
        let selectedIDs = selectedTransactionIDs
        return debugAssistantRelatedTransactions(to: primary)
            .filter { !selectedIDs.contains($0.id) }
    }

    /// Partitions raw related candidates into Focus/Noise-eligible versus scope-excluded, preserving
    /// deterministic nearest ordering within each group.
    func debugAssistantRelatedPartition(
        for primary: HTTPTransaction
    )
        -> (eligible: [HTTPTransaction], scopeExcluded: [HTTPTransaction])
    {
        let workspace = activeWorkspace
        var eligible: [HTTPTransaction] = []
        var scopeExcluded: [HTTPTransaction] = []
        for transaction in debugAssistantRawRelatedCandidates(for: primary) {
            if isWithinFocusNoiseScope(transaction, workspace: workspace) {
                eligible.append(transaction)
            } else {
                scopeExcluded.append(transaction)
            }
        }
        return (eligible, scopeExcluded)
    }

    private func debugAssistantAvailableRelatedTransactionCount() -> Int {
        guard let primary = debugAssistantSelectedTransactions().first else {
            return 0
        }
        return debugAssistantRelatedPartition(for: primary).eligible.count
    }

    func resetDebugAssistantForSelectionChange() {
        let workspace = activeWorkspace
        syncCurrentDebugAssistantConversation(workspace)
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantState = .idle
        workspace.modelInvestigationState = .idle
        workspace.debugAssistantProductHelpState = .idle
        resetDebugAssistantReviewState(workspace)
        workspace.debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
    }

    func debugAssistantConversationHasContextMismatch() -> Bool {
        guard let conversationContext = activeWorkspace.debugAssistantConversationContext else {
            return false
        }
        guard let currentContext = currentDebugAssistantConversationContext() else {
            return true
        }
        return !conversationContext.matches(
            primaryTransactionID: currentContext.primaryTransactionID,
            selectedTransactionIDs: currentContext.selectedTransactionIDs,
            requestedSelectionCount: currentContext.requestedSelectionCount
        )
    }

    func restoreDebugAssistantConversationContext() {
        let workspace = activeWorkspace
        guard let context = workspace.debugAssistantConversationContext,
              let primary = transaction(for: context.primaryTransactionID) else
        {
            activeToast = ToastMessage(
                style: .error,
                text: String(localized: "The original captured traffic is no longer available.", bundle: RockxyLocalization.bundle)
            )
            return
        }
        let availableIDs = Set(
            context.selectedTransactionIDs.filter { transaction(for: $0) != nil }
        )
        guard availableIDs.contains(primary.id) else {
            activeToast = ToastMessage(
                style: .error,
                text: String(localized: "The original captured traffic is no longer available.", bundle: RockxyLocalization.bundle)
            )
            return
        }
        selectedTransactionIDs = availableIDs
        selectTransaction(primary)
    }

    func startNewDebugAssistantConversationForCurrentSelection() {
        newDebugAssistantConversation()
        activeWorkspace.isDebugAssistantComposerFocusRequested = true
    }

    // MARK: Private

    private func resetDebugAssistantReviewState(_ workspace: WorkspaceState) {
        workspace.debugAssistantReviewPack = nil
        workspace.debugAssistantReviewRequest = nil
        workspace.debugAssistantReviewConfiguration = nil
        workspace.debugAssistantReviewTrafficScope = nil
        workspace.debugAssistantReviewModelAccessEnabled = false
        workspace.debugAssistantReviewSummary = nil
        workspace.debugAssistantRequestedContextCount = 0
        workspace.isPreparingDebugAssistantReview = false
        workspace.isPreparingDebugAssistantReviewOverride = false
    }

    private func validatedDebugAssistantReviewConfiguration(
        workspace: WorkspaceState,
        result: InvestigationResult,
        pack: InvestigationContextPack
    )
        -> AssistantProviderConfiguration?
    {
        let settings = assistantSettingsProvider()
        guard workspace.debugAssistantReviewModelAccessEnabled,
              settings.debugAssistantModelAccessEnabled else
        {
            workspace.modelInvestigationState = .failed(
                message: String(localized: "Enable model access in AI Assistant Settings before sending data.", bundle: RockxyLocalization.bundle)
            )
            return nil
        }
        guard let configuration = workspace.debugAssistantReviewConfiguration,
              configuration.isComplete,
              settings.assistantProviderConfiguration == configuration else
        {
            workspace.modelInvestigationState = .failed(
                message: String(localized: "The provider configuration changed. Review the outbound data again.", bundle: RockxyLocalization.bundle)
            )
            dismissDebugAssistantReview()
            return nil
        }
        guard workspace.debugAssistantReviewTrafficScope == workspace.debugAssistantTrafficScope,
              AssistantTrustPolicy.isReviewedScopeValid(pack, for: result) else
        {
            workspace.modelInvestigationState = .failed(
                message: String(localized: "The traffic scope changed. Review the exact data again before model access.", bundle: RockxyLocalization.bundle)
            )
            dismissDebugAssistantReview()
            return nil
        }
        return configuration
    }

    private func publishDebugAssistantOverride(
        to workspace: WorkspaceState,
        previousResult: InvestigationResult,
        newResult: InvestigationResult,
        pack: InvestigationContextPack,
        requestedCount: Int,
        scope: AssistantTrafficScope
    ) {
        workspace.isPreparingDebugAssistantReviewOverride = false
        workspace.debugAssistantState = .result(newResult)
        workspace.debugAssistantRequestedContextCount = requestedCount
        workspace.debugAssistantReviewPack = pack
        workspace.debugAssistantReviewRequest = workspace.debugAssistantReviewConfiguration.map { configuration in
            AssistantPromptBuilder().build(
                result: newResult,
                pack: pack,
                configuration: configuration,
                conversation: workspace.debugAssistantMessages
            )
        }
        workspace.debugAssistantReviewSummary = makeDebugAssistantReviewSummary(
            result: newResult,
            pack: pack,
            scope: scope,
            overrideApplied: true
        )
        replaceLatestInvestigationMessage(in: workspace, matching: previousResult, with: newResult)
    }

    private func makeDebugAssistantReviewSummary(
        result: InvestigationResult,
        pack: InvestigationContextPack,
        scope: AssistantTrafficScope,
        overrideApplied: Bool
    )
        -> DebugAssistantReviewSummary
    {
        guard scope == .selectedAndRelated,
              let primary = transaction(for: result.selectedTransactionID) else
        {
            return DebugAssistantReviewSummary(overrideApplied: overrideApplied)
        }
        let partition = debugAssistantRelatedPartition(for: primary)
        let selectedIDs = Set(
            debugAssistantSelectedTransactions()
                .prefix(InvestigationContextLimits.default.maxTransactions)
                .map(\.id)
        )
        let reviewedRelatedIDs = Set(pack.scopeTransactionIDs).subtracting(selectedIDs)
        let unfilteredRelatedIDs = Set(
            debugAssistantContextTransactions(ignoringFocusNoise: true).map(\.id)
        ).subtracting(selectedIDs)
        let overrideExpandsReviewedSet = !overrideApplied
            && !partition.scopeExcluded.isEmpty
            && unfilteredRelatedIDs != reviewedRelatedIDs
        return DebugAssistantReviewSummary(
            rawRelatedFound: partition.eligible.count + partition.scopeExcluded.count,
            relatedIncluded: reviewedRelatedIDs.count,
            focusNoiseExcluded: partition.scopeExcluded.count,
            overrideApplied: overrideApplied,
            overrideExpandsReviewedSet: overrideExpandsReviewedSet
        )
    }

    private func replaceLatestInvestigationMessage(
        in workspace: WorkspaceState,
        matching old: InvestigationResult,
        with new: InvestigationResult
    ) {
        guard let index = workspace.debugAssistantMessages.lastIndex(where: { $0.investigation == old }) else {
            return
        }
        let message = workspace.debugAssistantMessages[index]
        workspace.debugAssistantMessages[index] = DebugAssistantMessage(
            id: message.id,
            role: message.role,
            text: message.modelResult == nil ? new.summary : message.text,
            investigation: new,
            modelResult: message.modelResult
        )
        syncCurrentDebugAssistantConversation(workspace)
    }

    func cancelDebugAssistantTask(for workspaceID: UUID) {
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
        workspace.debugAssistantProductHelpState = .idle
        workspace.debugAssistantMessages.removeAll()
        workspace.debugAssistantDraft = ""
        workspace.debugAssistantConversationID = UUID()
        workspace.debugAssistantConversationTitle = String(localized: "New Conversation", bundle: RockxyLocalization.bundle)
        workspace.debugAssistantConversationCreatedAt = Date()
        workspace.debugAssistantConversationUpdatedAt = Date()
        workspace.debugAssistantConversationContext = nil
        resetDebugAssistantReviewState(workspace)
        workspace.debugAssistantTrafficScope = AssistantTrustPolicy.defaultTrafficScope
    }

    func syncCurrentDebugAssistantConversation(_ workspace: WorkspaceState) {
        guard !workspace.debugAssistantMessages.isEmpty else {
            return
        }
        workspace.debugAssistantMessages = boundedDebugAssistantMessages(
            workspace.debugAssistantMessages
        )
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
            context: workspace.debugAssistantConversationContext,
            createdAt: workspace.debugAssistantConversationCreatedAt,
            updatedAt: workspace.debugAssistantConversationUpdatedAt,
            isPinned: existingConversation?.isPinned ?? false
        )
        if let index = workspace.debugAssistantConversations.firstIndex(where: { $0.id == conversation.id }) {
            workspace.debugAssistantConversations[index] = conversation
        } else {
            workspace.debugAssistantConversations.append(conversation)
        }
        enforceDebugAssistantConversationCapacity(workspace)
    }

    func shouldAutomaticallyUseConfiguredModel(_ workspace: WorkspaceState) -> Bool {
        guard workspace.debugAssistantUsesConfiguredModel else {
            return false
        }
        let settings = assistantSettingsProvider()
        return settings.debugAssistantModelAccessEnabled
            && settings.assistantProviderConfiguration?.isComplete == true
    }

    func debugAssistantConversationTitle(from prompt: String) -> String {
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard normalized.count > 42 else {
            return normalized
        }
        let cutoff = normalized.index(normalized.startIndex, offsetBy: 39)
        return String(normalized[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func currentDebugAssistantConversationContext() -> DebugAssistantConversationContext? {
        let selected = debugAssistantSelectedTransactions()
        guard let primary = selected.first else {
            return nil
        }
        return DebugAssistantConversationContext(
            primaryTransactionID: primary.id,
            selectedTransactionIDs: Array(
                selected.prefix(InvestigationContextLimits.default.maxTransactions)
            ).map(\.id),
            requestedSelectionCount: selected.count
        )
    }

    private func boundedDebugAssistantMessages(
        _ messages: [DebugAssistantMessage]
    )
        -> [DebugAssistantMessage]
    {
        var retained: [DebugAssistantMessage] = []
        var retainedBytes = 0
        for message in messages.reversed() {
            guard retained.count < DebugAssistantConversationLimits.maximumMessagesPerConversation else {
                break
            }
            let messageBytes = message.retainedTextBytes
            guard retained.isEmpty
                || retainedBytes + messageBytes
                <= DebugAssistantConversationLimits.maximumConversationTextBytes else
            {
                break
            }
            retained.append(message)
            retainedBytes += messageBytes
        }
        return retained.reversed()
    }

    private func enforceDebugAssistantConversationCapacity(_ workspace: WorkspaceState) {
        func exceedsCapacity() -> Bool {
            workspace.debugAssistantConversations.count
                > DebugAssistantConversationLimits.maximumConversationsPerWorkspace
                || workspace.debugAssistantConversations.reduce(0) { $0 + $1.retainedTextBytes }
                > DebugAssistantConversationLimits.maximumWorkspaceTextBytes
        }

        while exceedsCapacity() {
            let inactive = workspace.debugAssistantConversations.filter {
                $0.id != workspace.debugAssistantConversationID
            }
            let candidate = inactive
                .filter { !$0.isPinned }
                .min(by: { $0.updatedAt < $1.updatedAt })
                ?? inactive.min(by: { $0.updatedAt < $1.updatedAt })
            guard let candidate else {
                break
            }
            workspace.debugAssistantConversations.removeAll { $0.id == candidate.id }
        }
    }

    private func isCurrentModelRun(
        workspaceID: UUID,
        runID: UUID,
        selectedTransactionID: UUID
    )
        -> Bool
    {
        guard let workspace = workspaceStore.allWorkspaces.first(where: { $0.id == workspaceID }),
              case let .result(result) = workspace.debugAssistantState,
              result.selectedTransactionID == selectedTransactionID,
              case let .streaming(currentRunID, _, _, _, _, _) = workspace.modelInvestigationState else
        {
            return false
        }
        return currentRunID == runID
    }

    private func debugAssistantRelatedTransactions(to primary: HTTPTransaction) -> [HTTPTransaction] {
        ensureDebugAssistantTrafficIndex()
        let cacheKey = DebugAssistantRelatedCacheKey(
            primaryTransactionID: primary.id,
            trafficIndexGeneration: debugAssistantTrafficIndexGeneration
        )
        if let cache = debugAssistantRelatedCache, cache.key == cacheKey {
            return cache.transactions
        }

        var nearest: [(distance: TimeInterval, transaction: HTTPTransaction)] = []
        for transaction in debugAssistantTransactionsByHost[primary.request.host] ?? []
            where transaction.id != primary.id
        {
            let candidate = (
                distance: abs(transaction.timestamp.timeIntervalSince(primary.timestamp)),
                transaction: transaction
            )
            if nearest.count < 20 {
                nearest.append(candidate)
                continue
            }
            guard let farthestIndex = nearest.indices.max(by: {
                nearest[$0].distance < nearest[$1].distance
            }), candidate.distance < nearest[farthestIndex].distance else {
                continue
            }
            nearest[farthestIndex] = candidate
        }
        let values = nearest.sorted {
            if $0.distance != $1.distance {
                return $0.distance < $1.distance
            }
            return $0.transaction.timestamp < $1.transaction.timestamp
        }.map(\.transaction)
        debugAssistantRelatedCache = (cacheKey, values)
        return values
    }

    func appendToDebugAssistantTrafficIndex(_ appended: [HTTPTransaction]) {
        let expectedPreviousLiveCount = max(0, transactions.count - appended.count)
        guard debugAssistantIndexedLiveCount == expectedPreviousLiveCount,
              debugAssistantIndexedFavoriteCount == persistedFavorites.count else
        {
            rebuildDebugAssistantTrafficIndex()
            return
        }
        for transaction in appended where debugAssistantIndexedTransactionIDs.insert(transaction.id).inserted {
            debugAssistantTransactionsByHost[transaction.request.host, default: []].append(transaction)
        }
        debugAssistantIndexedLiveCount = transactions.count
        debugAssistantIndexedFavoriteCount = persistedFavorites.count
        debugAssistantTrafficIndexGeneration &+= 1
        debugAssistantRelatedCache = nil
    }

    private func ensureDebugAssistantTrafficIndex() {
        guard debugAssistantIndexedLiveCount != transactions.count
            || debugAssistantIndexedFavoriteCount != persistedFavorites.count else
        {
            return
        }
        rebuildDebugAssistantTrafficIndex()
    }

    private func rebuildDebugAssistantTrafficIndex() {
        var valuesByHost: [String: [HTTPTransaction]] = [:]
        var seen: Set<UUID> = []
        for transaction in transactions + persistedFavorites where seen.insert(transaction.id).inserted {
            valuesByHost[transaction.request.host, default: []].append(transaction)
        }
        debugAssistantTransactionsByHost = valuesByHost
        debugAssistantIndexedTransactionIDs = seen
        debugAssistantIndexedLiveCount = transactions.count
        debugAssistantIndexedFavoriteCount = persistedFavorites.count
        debugAssistantTrafficIndexGeneration &+= 1
        debugAssistantRelatedCache = nil
    }
}
