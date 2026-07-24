import Foundation

// MARK: - DebugAssistantRecipe

enum DebugAssistantRecipe: String, CaseIterable, Identifiable {
    case explainRequest
    case explainFailure
    case compareWithSuccess
    case checkAuthentication
    case prepareBugReport

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .explainRequest:
            String(localized: "Explain This Request")
        case .explainFailure:
            String(localized: "Explain This Failure")
        case .compareWithSuccess:
            String(localized: "Compare With Successful Request")
        case .checkAuthentication:
            String(localized: "Check Authentication")
        case .prepareBugReport:
            String(localized: "Prepare Bug Report")
        }
    }

    var detail: String {
        switch self {
        case .explainRequest:
            String(localized: "Explain what the request does, its captured outcome, and anything worth checking.")
        case .explainFailure:
            String(localized: "Trace the status, response headers, timing, and nearby failures.")
        case .compareWithSuccess:
            String(localized: "Find the closest successful request and compare captured evidence.")
        case .checkAuthentication:
            String(localized: "Review credential presence and authentication response signals.")
        case .prepareBugReport:
            String(localized: "Summarize reproducible evidence without exposing captured secrets.")
        }
    }

    var systemImage: String {
        switch self {
        case .explainRequest: "doc.text.magnifyingglass"
        case .explainFailure: "exclamationmark.magnifyingglass"
        case .compareWithSuccess: "arrow.left.arrow.right"
        case .checkAuthentication: "key.horizontal"
        case .prepareBugReport: "doc.text"
        }
    }

    var prompt: String {
        switch self {
        case .explainRequest:
            String(localized: "Explain what this request does and whether anything looks unusual.")
        case .explainFailure:
            String(localized: "Why did this request fail?")
        case .compareWithSuccess:
            String(localized: "Compare this with the last successful request.")
        case .checkAuthentication:
            String(localized: "Do you see an authentication problem here?")
        case .prepareBugReport:
            String(localized: "Turn this traffic into a concise bug report.")
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
        modelResult: ModelInvestigationResult? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.investigation = investigation
        self.modelResult = modelResult
    }

    // MARK: Internal

    let id: UUID
    let role: DebugAssistantMessageRole
    let text: String
    let investigation: InvestigationResult?
    let modelResult: ModelInvestigationResult?

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

    static func assistant(_ text: String) -> DebugAssistantMessage {
        DebugAssistantMessage(role: .assistant, text: text)
    }

    static func assistant(
        _ result: ModelInvestigationResult,
        investigation: InvestigationResult? = nil
    ) -> DebugAssistantMessage {
        DebugAssistantMessage(
            role: .assistant,
            text: result.text,
            investigation: investigation,
            modelResult: result
        )
    }
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
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    // MARK: Internal

    let id: UUID
    var title: String
    var messages: [DebugAssistantMessage]
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    var preview: String {
        messages.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text
            ?? String(localized: "No messages yet")
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
        case .observed: String(localized: "Observed")
        case .derived: String(localized: "Derived")
        case .inferred: String(localized: "Inferred")
        case .unknown: String(localized: "Unknown")
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
