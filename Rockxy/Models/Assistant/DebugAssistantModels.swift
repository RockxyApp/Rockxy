import Foundation

// MARK: - DebugAssistantRecipe

enum DebugAssistantRecipe: String, CaseIterable, Identifiable {
    case explainRequest
    case explainFailure
    case compareWithSuccess
    case checkAuthentication
    case whyIsThisSlow
    case findRelatedRequests
    case prepareBugReport

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .explainRequest:
            String(localized: "Explain This Request", bundle: RockxyLocalization.bundle)
        case .explainFailure:
            String(localized: "Explain This Failure", bundle: RockxyLocalization.bundle)
        case .compareWithSuccess:
            String(localized: "Compare With Successful Request", bundle: RockxyLocalization.bundle)
        case .checkAuthentication:
            String(localized: "Check Authentication", bundle: RockxyLocalization.bundle)
        case .whyIsThisSlow:
            String(localized: "Why Is This Slow?", bundle: RockxyLocalization.bundle)
        case .findRelatedRequests:
            String(localized: "Find Related Requests", bundle: RockxyLocalization.bundle)
        case .prepareBugReport:
            String(localized: "Prepare Bug Report", bundle: RockxyLocalization.bundle)
        }
    }

    var detail: String {
        switch self {
        case .explainRequest:
            String(
                localized: "Explain what the request does, its captured outcome, and anything worth checking.",
                bundle: RockxyLocalization.bundle
            )
        case .explainFailure:
            String(
                localized: "Trace the status, response headers, timing, and nearby failures.",
                bundle: RockxyLocalization.bundle
            )
        case .compareWithSuccess:
            String(
                localized: "Find the closest successful request and compare captured evidence.",
                bundle: RockxyLocalization.bundle
            )
        case .checkAuthentication:
            String(
                localized: "Review credential presence and authentication response signals.",
                bundle: RockxyLocalization.bundle
            )
        case .whyIsThisSlow:
            String(
                localized: "Break the captured time into connection, server wait, and transfer, and compare with similar requests.",
                bundle: RockxyLocalization.bundle
            )
        case .findRelatedRequests:
            String(
                localized: "List captured requests to the same endpoint and host around the same time.",
                bundle: RockxyLocalization.bundle
            )
        case .prepareBugReport:
            String(
                localized: "Summarize reproducible evidence without exposing captured secrets.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var systemImage: String {
        switch self {
        case .explainRequest: "doc.text.magnifyingglass"
        case .explainFailure: "exclamationmark.magnifyingglass"
        case .compareWithSuccess: "arrow.left.arrow.right"
        case .checkAuthentication: "key.horizontal"
        case .whyIsThisSlow: "timer"
        case .findRelatedRequests: "point.3.connected.trianglepath.dotted"
        case .prepareBugReport: "doc.text"
        }
    }

    var prompt: String {
        switch self {
        case .explainRequest:
            String(
                localized: "Explain what this request does and whether anything looks unusual.",
                bundle: RockxyLocalization.bundle
            )
        case .explainFailure:
            String(localized: "Why did this request fail?", bundle: RockxyLocalization.bundle)
        case .compareWithSuccess:
            String(localized: "Compare this with the last successful request.", bundle: RockxyLocalization.bundle)
        case .checkAuthentication:
            String(localized: "Do you see an authentication problem here?", bundle: RockxyLocalization.bundle)
        case .whyIsThisSlow:
            String(localized: "Why is this request slow?", bundle: RockxyLocalization.bundle)
        case .findRelatedRequests:
            String(localized: "Which other requests are related to this one?", bundle: RockxyLocalization.bundle)
        case .prepareBugReport:
            String(localized: "Turn this traffic into a concise bug report.", bundle: RockxyLocalization.bundle)
        }
    }

    static func suggestedRecipe(for prompt: String) -> DebugAssistantRecipe {
        let normalized = prompt.lowercased()
        if normalized.contains("auth")
            || normalized.contains("token")
            || normalized.contains("credential")
            || normalized.contains("401")
            || normalized.contains("403")
        {
            return .checkAuthentication
        }
        if normalized.contains("compare")
            || normalized.contains("diff")
            || normalized.contains("successful")
            || normalized.contains("success")
        {
            return .compareWithSuccess
        }
        if normalized.contains("slow")
            || normalized.contains("latency")
            || normalized.contains("takes long")
            || normalized.contains("performance")
        {
            return .whyIsThisSlow
        }
        if (normalized.contains("related") && !normalized.contains("unrelated"))
            || normalized.contains("same endpoint")
            || normalized.contains("other requests")
        {
            return .findRelatedRequests
        }
        if normalized.contains("bug")
            || normalized.contains("report")
            || normalized.contains("issue")
            || normalized.contains("repro")
        {
            return .prepareBugReport
        }
        if normalized.contains("fail")
            || normalized.contains("error")
            || normalized.contains("wrong")
            || normalized.contains("broken")
            || normalized.contains("timeout")
            || normalized.contains("why did")
        {
            return .explainFailure
        }
        return .explainRequest
    }
}

// MARK: - DebugAssistantMessageRole

enum DebugAssistantMessageRole: String, Codable {
    case user
    case assistant
}

// MARK: - DebugAssistantMessage

struct DebugAssistantMessage: Identifiable, Equatable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        role: DebugAssistantMessageRole,
        text: String,
        investigation: InvestigationResult? = nil,
        modelResult: ModelInvestigationResult? = nil,
        productHandoff: AssistantProductHandoff? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.investigation = investigation
        self.modelResult = modelResult
        self.productHandoff = productHandoff
    }

    // MARK: Internal

    let id: UUID
    let role: DebugAssistantMessageRole
    let text: String
    let investigation: InvestigationResult?
    let modelResult: ModelInvestigationResult?
    /// At most one source-backed native window a product-help answer may offer to open. Navigation
    /// only — never an executed workflow. Always nil on traffic-investigation messages.
    let productHandoff: AssistantProductHandoff?

    var searchableText: String {
        var fragments = [text]
        if let investigation {
            fragments.append(contentsOf: [investigation.scopeSummary, investigation.nextStep])
            for evidence in investigation.evidence {
                fragments.append(contentsOf: [evidence.kind.title, evidence.title, evidence.detail])
            }
        }
        if let modelResult {
            fragments.append(contentsOf: [
                modelResult.provider.title,
                modelResult.model,
                modelResult.endpointHost
            ])
        }
        return fragments.joined(separator: "\n")
    }

    var retainedTextBytes: Int {
        searchableText.utf8.count
    }

    static func user(_ text: String) -> DebugAssistantMessage {
        DebugAssistantMessage(role: .user, text: text)
    }

    static func assistant(_ result: InvestigationResult) -> DebugAssistantMessage {
        DebugAssistantMessage(
            role: .assistant,
            text: result.summary,
            investigation: result
        )
    }

    static func assistant(
        _ text: String,
        handoff: AssistantProductHandoff? = nil
    )
        -> DebugAssistantMessage
    {
        DebugAssistantMessage(role: .assistant, text: text, productHandoff: handoff)
    }

    static func assistant(
        _ result: ModelInvestigationResult,
        investigation: InvestigationResult? = nil,
        handoff: AssistantProductHandoff? = nil
    )
        -> DebugAssistantMessage
    {
        DebugAssistantMessage(
            role: .assistant,
            text: result.text,
            investigation: investigation,
            modelResult: result,
            productHandoff: handoff
        )
    }
}

// MARK: - DebugAssistantConversationContext

/// Stable, bounded identity for the captured traffic attached to a conversation.
/// Only the requests Rockxy can actually include are retained; the original count
/// remains visible so a large selection is never represented as complete.
struct DebugAssistantConversationContext: Equatable {
    // MARK: Lifecycle

    init(
        primaryTransactionID: UUID,
        selectedTransactionIDs: [UUID],
        requestedSelectionCount: Int
    ) {
        var orderedIDs = [primaryTransactionID]
        var seen: Set<UUID> = [primaryTransactionID]
        for id in selectedTransactionIDs where seen.insert(id).inserted {
            orderedIDs.append(id)
        }
        self.primaryTransactionID = primaryTransactionID
        self.selectedTransactionIDs = Array(
            orderedIDs.prefix(InvestigationContextLimits.default.maxTransactions)
        )
        self.requestedSelectionCount = max(requestedSelectionCount, self.selectedTransactionIDs.count)
    }

    // MARK: Internal

    let primaryTransactionID: UUID
    let selectedTransactionIDs: [UUID]
    let requestedSelectionCount: Int

    var summary: String {
        if requestedSelectionCount == selectedTransactionIDs.count {
            return String(AttributedString(
                localized: "^[\(selectedTransactionIDs.count) selected request](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        }
        return String(AttributedString(
            localized: "\(selectedTransactionIDs.count) of ^[\(requestedSelectionCount) selected request](inflect: true)",
            bundle: RockxyLocalization.bundle,
            locale: RockxyLocalization.locale
        ).characters)
    }

    func matches(
        primaryTransactionID: UUID?,
        selectedTransactionIDs: [UUID],
        requestedSelectionCount: Int
    )
        -> Bool
    {
        self.primaryTransactionID == primaryTransactionID
            && Set(self.selectedTransactionIDs) == Set(selectedTransactionIDs)
            && (
                self.requestedSelectionCount == requestedSelectionCount
                    || self.selectedTransactionIDs.count == requestedSelectionCount
            )
    }
}

// MARK: - DebugAssistantConversationLimits

enum DebugAssistantConversationLimits {
    static let maximumPromptBytes = 16 * 1_024
    static let maximumMessagesPerConversation = 48
    static let maximumConversationTextBytes = 2 * 1_024 * 1_024
    static let maximumConversationsPerWorkspace = 32
    static let maximumPinnedConversationsPerWorkspace = 8
    static let maximumWorkspaceTextBytes = 8 * 1_024 * 1_024
}

// MARK: - DebugAssistantConversation

/// A workspace-local assistant thread. Keeping the captured evidence snapshots in memory avoids
/// silently persisting potentially sensitive traffic while still making new-chat and history
/// navigation behave like a real conversation product.
struct DebugAssistantConversation: Identifiable, Equatable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        title: String,
        messages: [DebugAssistantMessage],
        context: DebugAssistantConversationContext? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.context = context
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    // MARK: Internal

    let id: UUID
    var title: String
    var messages: [DebugAssistantMessage]
    var context: DebugAssistantConversationContext?
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    var preview: String {
        messages.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text
            ?? String(localized: "No messages yet", bundle: RockxyLocalization.bundle)
    }

    var retainedTextBytes: Int {
        title.utf8.count + messages.reduce(0) { $0 + $1.retainedTextBytes }
    }

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return true
        }
        return title.localizedCaseInsensitiveContains(normalized)
            || messages.contains { $0.searchableText.localizedCaseInsensitiveContains(normalized) }
    }
}

// MARK: - InvestigationEvidenceKind

enum InvestigationEvidenceKind: String, CaseIterable, Codable {
    case observed
    case derived
    case inferred
    case unknown

    // MARK: Internal

    var title: String {
        switch self {
        case .observed: String(localized: "Observed", bundle: RockxyLocalization.bundle)
        case .derived: String(localized: "Derived", bundle: RockxyLocalization.bundle)
        case .inferred: String(localized: "Inferred", bundle: RockxyLocalization.bundle)
        case .unknown: String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - InvestigationEvidence

struct InvestigationEvidence: Identifiable, Equatable {
    let id: String
    let kind: InvestigationEvidenceKind
    let title: String
    let detail: String
    let sourceTransactionID: UUID?
}

// MARK: - InvestigationResult

struct InvestigationResult: Equatable {
    let recipe: DebugAssistantRecipe
    let selectedTransactionID: UUID
    let scopeTransactionIDs: [UUID]
    let scopeSummary: String
    let summary: String
    let evidence: [InvestigationEvidence]
    let nextStep: String
}

// MARK: - DebugAssistantState

enum DebugAssistantState: Equatable {
    case idle
    case investigating(runID: UUID, recipe: DebugAssistantRecipe)
    case result(InvestigationResult)
    case failed(message: String)
}

// MARK: - DebugAssistantProductHelpState

/// Streaming lifecycle for a no-selection product/workflow question. It is fully independent from
/// traffic investigation: it never carries an `InvestigationResult`, never builds Review Data, and
/// the conversation stays context-free (`debugAssistantConversationContext == nil`) throughout.
enum DebugAssistantProductHelpState: Equatable {
    case idle
    case streaming(
        runID: UUID,
        provider: AssistantProviderKind,
        executionLocation: AssistantExecutionLocation,
        model: String,
        endpointHost: String,
        text: String
    )
    /// Carries the original question and matched handoff so recovery can re-run without a stale
    /// investigation retry and can still offer the source-backed navigation.
    case failed(message: String, question: String, handoff: AssistantProductHandoff?)
}

// MARK: - InvestigationTransactionSnapshot

/// Immutable value copied from a live transaction before investigation work leaves the main actor.
struct InvestigationTransactionSnapshot {
    // MARK: Lifecycle

    @MainActor
    init(transaction: HTTPTransaction) {
        id = transaction.id
        timestamp = transaction.timestamp
        request = transaction.request
        response = transaction.response
        isFailed = transaction.state == .failed
        duration = transaction.timingInfo?.totalDuration ?? transaction.measuredDuration
        timing = transaction.timingInfo
        clientApp = transaction.clientApp
        matchedRuleName = transaction.matchedRuleName
        matchedRuleActionSummary = transaction.matchedRuleActionSummary
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let request: HTTPRequestData
    let response: HTTPResponseData?
    let isFailed: Bool
    let duration: TimeInterval?
    /// Captured phase breakdown, when the proxy measured one.
    let timing: TimingInfo?
    let clientApp: String?
    let matchedRuleName: String?
    let matchedRuleActionSummary: String?

    var statusCode: Int? {
        response?.statusCode
    }

    var isSuccessful: Bool {
        guard let statusCode else {
            return false
        }
        return (200 ..< 400).contains(statusCode) && !isFailed
    }

    func requestHeader(named name: String) -> HTTPHeader? {
        request.headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func responseHeader(named name: String) -> HTTPHeader? {
        response?.headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
