import Foundation

// MARK: - MainContentCoordinator + AssistantProductHelp

/// No-selection, workspace-aware product/workflow help for the AI Assistant. This path is
/// deliberately isolated from traffic investigation: it keeps the conversation context-free
/// (`debugAssistantConversationContext == nil`), never builds Review Data, and offers at most one
/// source-backed, user-clicked direct-open handoff from the static `AssistantProductHelpCatalog`.
/// It may answer basic current-state questions from an aggregate-only `AssistantWorkspaceSummary`
/// (bounded scalar counts + capture state) — never any per-transaction content or identifiers.
extension MainContentCoordinator {
    /// Appends the user's question and produces a product-help answer. When the configured model is
    /// enabled and available the answer streams through the provider runtime; otherwise it is the
    /// deterministic response (a current-count answer or the catalog fallback). The conversation
    /// stays context-free throughout.
    func sendDebugAssistantProductHelp(prompt: String) {
        let workspace = activeWorkspace
        if workspace.debugAssistantMessages.isEmpty {
            workspace.debugAssistantConversationTitle = debugAssistantConversationTitle(from: prompt)
            workspace.debugAssistantConversationUpdatedAt = Date()
        }
        workspace.debugAssistantMessages.append(.user(prompt))
        workspace.debugAssistantProductHelpState = .idle
        syncCurrentDebugAssistantConversation(workspace)
        cancelDebugAssistantTask(for: workspace.id)

        let summary = currentAssistantWorkspaceSummary()
        let handoff = AssistantProductHelpCatalog.shared.match(prompt: prompt)?.handoff

        guard shouldAutomaticallyUseConfiguredModel(workspace) else {
            appendDeterministicProductHelp(to: workspace, question: prompt, summary: summary)
            return
        }
        streamDebugAssistantProductHelp(
            workspace: workspace,
            question: prompt,
            handoff: handoff,
            summary: summary
        )
    }

    /// Re-runs a failed product-help answer using the original question. Valid only while the
    /// conversation is still context-free; never routes into an investigation-only retry. A fresh
    /// workspace summary is rebuilt because the user is asking about *current* state.
    func retryDebugAssistantProductHelp() {
        let workspace = activeWorkspace
        guard case let .failed(_, question, handoff) = workspace.debugAssistantProductHelpState,
              workspace.debugAssistantConversationContext == nil else
        {
            return
        }
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantProductHelpState = .idle
        let summary = currentAssistantWorkspaceSummary()
        guard shouldAutomaticallyUseConfiguredModel(workspace) else {
            appendDeterministicProductHelp(to: workspace, question: question, summary: summary)
            return
        }
        streamDebugAssistantProductHelp(
            workspace: workspace,
            question: question,
            handoff: handoff,
            summary: summary
        )
    }

    func cancelDebugAssistantProductHelp() {
        let workspace = activeWorkspace
        cancelDebugAssistantTask(for: workspace.id)
        workspace.debugAssistantProductHelpState = .idle
    }

    // MARK: Private

    /// Aggregate-only snapshot of the current session/workspace built synchronously on the main
    /// actor from authoritative live state. Carries bounded scalar counts and capture state only —
    /// never any per-transaction content or identifiers.
    func currentAssistantWorkspaceSummary() -> AssistantWorkspaceSummary {
        let retained = transactions.count
        let visible = activeWorkspace.filteredTransactions.count
        let selected = debugAssistantSelectedTransactions().count
        return AssistantWorkspaceSummary(
            retainedRequestCount: retained,
            visibleRequestCount: visible,
            selectedRequestCount: selected,
            isScopeNarrowingResults: visible < retained,
            captureState: assistantWorkspaceCaptureState()
        )
    }

    private func assistantWorkspaceCaptureState() -> AssistantWorkspaceSummary.CaptureState {
        switch proxyDisplayState {
        case .starting: .starting
        case .stopping: .stopped
        case .running: .running
        case .paused: .paused
        case .stopped: .stopped
        }
    }

    /// Deterministic reply for the no-model path: a current-count answer built from the send-time
    /// summary when the question is a current-state question, otherwise the catalog fallback.
    private func deterministicProductHelpResponse(
        question: String,
        summary: AssistantWorkspaceSummary
    )
        -> AssistantProductHelpResponse
    {
        if AssistantWorkspaceSummary.isCurrentCountQuestion(question) {
            return AssistantProductHelpResponse(text: summary.deterministicAnswer, handoff: nil)
        }
        return AssistantProductHelpCatalog.shared.deterministicResponse(for: question)
    }

    private func appendDeterministicProductHelp(
        to workspace: WorkspaceState,
        question: String,
        summary: AssistantWorkspaceSummary
    ) {
        let response = deterministicProductHelpResponse(question: question, summary: summary)
        workspace.debugAssistantMessages.append(.assistant(response.text, handoff: response.handoff))
        syncCurrentDebugAssistantConversation(workspace)
    }

    private func streamDebugAssistantProductHelp(
        workspace: WorkspaceState,
        question: String,
        handoff: AssistantProductHandoff?,
        summary: AssistantWorkspaceSummary
    ) {
        let settings = assistantSettingsProvider()
        guard settings.debugAssistantModelAccessEnabled,
              let configuration = settings.assistantProviderConfiguration,
              configuration.isComplete else
        {
            appendDeterministicProductHelp(to: workspace, question: question, summary: summary)
            return
        }

        let request = AssistantProductHelpPromptBuilder().build(
            question: question,
            conversation: workspace.debugAssistantMessages,
            configuration: configuration,
            workspaceSummary: summary
        )
        let runID = UUID()
        let conversationID = workspace.debugAssistantConversationID
        workspace.debugAssistantProductHelpState = .streaming(
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
                let stream = try await assistantRuntime.stream(request: request, configuration: configuration)
                var textBuffer = AssistantStreamingTextBuffer(startedAt: ProcessInfo.processInfo.systemUptime)
                var usage: AssistantUsage?
                var blockedToolCallCount = 0
                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case let .textDelta(delta):
                        let shouldPublish = try textBuffer.append(delta, at: ProcessInfo.processInfo.systemUptime)
                        guard shouldPublish else {
                            continue
                        }
                        guard self.isCurrentProductHelpRun(
                            workspaceID: workspace.id,
                            runID: runID,
                            conversationID: conversationID
                        ) else {
                            return
                        }
                        workspace.debugAssistantProductHelpState = .streaming(
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

                guard self.isCurrentProductHelpRun(
                    workspaceID: workspace.id,
                    runID: runID,
                    conversationID: conversationID
                ) else {
                    return
                }
                let sanitized = AssistantResponseSanitizer.sanitize(textBuffer.text)
                let finalText = sanitized.isEmpty
                    ? self.deterministicProductHelpResponse(question: question, summary: summary).text
                    : sanitized
                let modelResult = ModelInvestigationResult(
                    provider: configuration.kind,
                    model: configuration.model,
                    endpointHost: configuration.endpointHost,
                    text: finalText,
                    usage: usage,
                    blockedToolCallCount: blockedToolCallCount
                )
                workspace.debugAssistantProductHelpState = .idle
                workspace.debugAssistantMessages.append(.assistant(modelResult, handoff: handoff))
                self.syncCurrentDebugAssistantConversation(workspace)
            } catch is CancellationError {
                return
            } catch AssistantProviderError.cancelled {
                return
            } catch {
                guard self.isCurrentProductHelpRun(
                    workspaceID: workspace.id,
                    runID: runID,
                    conversationID: conversationID
                ) else {
                    return
                }
                workspace.debugAssistantProductHelpState = .failed(
                    message: error.localizedDescription,
                    question: question,
                    handoff: handoff
                )
            }
        }
        debugAssistantTasks[workspace.id] = DebugAssistantTaskHandle(id: taskID, task: task)
    }

    /// A product-help completion may land only if the same context-free conversation is still active
    /// and its streaming run matches. Guards against a stale response arriving after the user started
    /// a new conversation, switched threads, or began a traffic investigation.
    private func isCurrentProductHelpRun(
        workspaceID: UUID,
        runID: UUID,
        conversationID: UUID
    )
        -> Bool
    {
        guard let workspace = workspaceStore.allWorkspaces.first(where: { $0.id == workspaceID }),
              workspace.debugAssistantConversationID == conversationID,
              workspace.debugAssistantConversationContext == nil,
              case let .streaming(currentRunID, _, _, _, _, _) = workspace.debugAssistantProductHelpState,
              currentRunID == runID else
        {
            return false
        }
        return true
    }
}
