import Foundation

// MARK: - DebugAssistantEngine

/// Deterministic first layer for Debug Assistant. It only reasons over immutable captured values.
struct DebugAssistantEngine {
    // MARK: Internal

    func investigate(
        recipe: DebugAssistantRecipe,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        throws -> InvestigationResult
    {
        guard let primary = selected.first else {
            throw DebugAssistantEngineError.noSelection
        }

        return switch recipe {
        case .explainFailure:
            explainFailure(primary: primary, selected: selected, session: session)
        case .compareWithSuccess:
            compareWithSuccess(primary: primary, selected: selected, session: session)
        case .checkAuthentication:
            checkAuthentication(primary: primary, selected: selected, session: session)
        case .prepareBugReport:
            prepareBugReport(primary: primary, selected: selected, session: session)
        }
    }

    // MARK: Private

    private func explainFailure(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let related = nearbyTransactions(to: primary, in: session)
        let scope = boundedScope(primary: primary, selected: selected, related: related)
        let repeated = scope.filter {
            $0.request.host == primary.request.host
                && $0.request.method == primary.request.method
                && $0.request.path == primary.request.path
        }
        var evidence: [InvestigationEvidence] = []

        if let response = primary.response {
            evidence.append(.init(
                id: "flow:\(primary.id):response.status",
                kind: .observed,
                title: "HTTP \(response.statusCode)",
                detail: String(localized: "Captured response status \(response.statusMessage)."),
                sourceTransactionID: primary.id
            ))
        } else {
            evidence.append(.init(
                id: "flow:\(primary.id):response.unavailable",
                kind: .unknown,
                title: String(localized: "No completed response was captured"),
                detail: String(localized: "Rockxy cannot inspect response headers or payload for this request."),
                sourceTransactionID: primary.id
            ))
        }

        if let retryAfter = primary.responseHeader(named: "Retry-After")?.value {
            evidence.append(.init(
                id: "flow:\(primary.id):response.header.retry-after",
                kind: .observed,
                title: String(localized: "Retry-After: \(retryAfter)"),
                detail: String(localized: "The response explicitly supplied a retry delay."),
                sourceTransactionID: primary.id
            ))
        }

        if repeated.count > 1 {
            let interval = repeated.map(\.timestamp).max().map {
                $0.timeIntervalSince(repeated.map(\.timestamp).min() ?? $0)
            } ?? 0
            evidence.append(.init(
                id: "scope:repeated-requests",
                kind: .derived,
                title: String(localized: "\(repeated.count) similar requests in \(formatDuration(interval))"),
                detail: String(localized: "Same host, method, and path in the bounded investigation scope."),
                sourceTransactionID: primary.id
            ))
        }

        if let duration = primary.duration, duration >= 1 {
            evidence.append(.init(
                id: "flow:\(primary.id):timing.total",
                kind: .observed,
                title: String(localized: "Completed in \(formatDuration(duration))"),
                detail: String(localized: "Captured total request duration."),
                sourceTransactionID: primary.id
            ))
        }

        if primary.statusCode == 429 {
            evidence.append(.init(
                id: "flow:\(primary.id):inference.rate-limit",
                kind: .inferred,
                title: String(localized: "Rate limiting is the leading hypothesis"),
                detail: String(
                    localized: "HTTP 429 and nearby repeated requests support this hypothesis; application policy remains unknown."
                ),
                sourceTransactionID: primary.id
            ))
            evidence.append(.init(
                id: "flow:\(primary.id):unknown.retry-policy",
                kind: .unknown,
                title: String(localized: "Application retry policy is not visible"),
                detail: String(localized: "Captured traffic cannot confirm whether the client retries automatically."),
                sourceTransactionID: primary.id
            ))
        }

        if primary.response?.bodyTruncated == true {
            evidence.append(.init(
                id: "flow:\(primary.id):unknown.truncated-response",
                kind: .unknown,
                title: String(localized: "Response body is incomplete"),
                detail: String(
                    localized: "Rockxy withholds body-level conclusions because capture truncated the response."
                ),
                sourceTransactionID: primary.id
            ))
        }

        return InvestigationResult(
            recipe: .explainFailure,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: scope.map(\.id),
            scopeSummary: scopeSummary(selectedCount: selected.count, requestCount: scope.count),
            summary: failureSummary(primary, repeatedCount: repeated.count),
            evidence: evidence,
            nextStep: nextStepForFailure(primary)
        )
    }

    private func compareWithSuccess(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let explicitComparison = selected.dropFirst().first
        let nearbySuccess = nearbyTransactions(to: primary, in: session).first {
            $0.isSuccessful
                && $0.request.method == primary.request.method
                && $0.request.path == primary.request.path
        }
        guard let comparison = explicitComparison ?? nearbySuccess else {
            return InvestigationResult(
                recipe: .compareWithSuccess,
                selectedTransactionID: primary.id,
                scopeTransactionIDs: [primary.id],
                scopeSummary: String(localized: "Selected request"),
                summary: String(localized: "No comparable successful request was found in the current session."),
                evidence: [InvestigationEvidence(
                    id: "flow:\(primary.id):unknown.comparison",
                    kind: .unknown,
                    title: String(localized: "Successful baseline unavailable"),
                    detail: String(
                        localized: "Capture another request with the same method and path, or select exactly two requests."
                    ),
                    sourceTransactionID: primary.id
                )],
                nextStep: String(
                    localized: "Select a successful request with the same method and path, then run Compare again."
                )
            )
        }

        var evidence = [
            InvestigationEvidence(
                id: "flow:\(primary.id):comparison.status",
                kind: .observed,
                title: String(localized: "Selected: HTTP \(primary.statusCode.map(String.init) ?? "—")"),
                detail: primary.request.host + primary.request.path,
                sourceTransactionID: primary.id
            ),
            InvestigationEvidence(
                id: "flow:\(comparison.id):comparison.status",
                kind: .observed,
                title: String(localized: "Baseline: HTTP \(comparison.statusCode.map(String.init) ?? "—")"),
                detail: comparison.request.host + comparison.request.path,
                sourceTransactionID: comparison.id
            ),
        ]

        if let selectedDuration = primary.duration, let baselineDuration = comparison.duration {
            let difference = selectedDuration - baselineDuration
            evidence.append(.init(
                id: "scope:comparison.duration",
                kind: .derived,
                title: difference >= 0
                    ? String(localized: "Selected request was \(formatDuration(difference)) slower")
                    : String(localized: "Selected request was \(formatDuration(abs(difference))) faster"),
                detail: String(localized: "Difference between captured total durations."),
                sourceTransactionID: primary.id
            ))
        }

        let selectedHeaderNames = Set(primary.request.headers.map { $0.name.lowercased() })
        let comparisonHeaderNames = Set(comparison.request.headers.map { $0.name.lowercased() })
        let missing = comparisonHeaderNames.subtracting(selectedHeaderNames).sorted()
        if !missing.isEmpty {
            evidence.append(.init(
                id: "scope:comparison.request-headers",
                kind: .derived,
                title: String(localized: "\(missing.count) baseline request headers are absent"),
                detail: missing.prefix(4).joined(separator: ", "),
                sourceTransactionID: primary.id
            ))
        }

        return InvestigationResult(
            recipe: .compareWithSuccess,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: [primary.id, comparison.id],
            scopeSummary: String(localized: "2 compared requests"),
            summary: String(localized: "The selected request differs from a captured successful baseline."),
            evidence: evidence,
            nextStep: String(localized: "Open the selected request in Compose and review every change before sending.")
        )
    }

    private func checkAuthentication(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let scope = boundedScope(
            primary: primary,
            selected: selected,
            related: nearbyTransactions(to: primary, in: session)
        )
        let hasAuthorization = primary.requestHeader(named: "Authorization") != nil
        let hasCookie = primary.requestHeader(named: "Cookie") != nil
        var evidence: [InvestigationEvidence] = []

        if hasAuthorization {
            evidence.append(.init(
                id: "flow:\(primary.id):request.header.authorization",
                kind: .observed,
                title: String(localized: "Authorization header is present"),
                detail: String(localized: "The credential value remains hidden."),
                sourceTransactionID: primary.id
            ))
        } else if hasCookie {
            evidence.append(.init(
                id: "flow:\(primary.id):request.header.cookie",
                kind: .observed,
                title: String(localized: "Cookie-based credentials may be present"),
                detail: String(localized: "Cookie values remain hidden."),
                sourceTransactionID: primary.id
            ))
        } else {
            evidence.append(.init(
                id: "flow:\(primary.id):unknown.authentication-input",
                kind: .unknown,
                title: String(localized: "No common credential header was captured"),
                detail: String(
                    localized: "Authentication may use a query value, body field, client certificate, or external state."
                ),
                sourceTransactionID: primary.id
            ))
        }

        if let status = primary.statusCode, status == 401 || status == 403 {
            evidence.append(.init(
                id: "flow:\(primary.id):response.status.auth",
                kind: .observed,
                title: String(localized: "Server returned HTTP \(status)"),
                detail: status == 401
                    ? String(localized: "The request was not authenticated.")
                    : String(localized: "The authenticated identity may not have permission."),
                sourceTransactionID: primary.id
            ))
            if hasAuthorization || hasCookie {
                evidence.append(.init(
                    id: "flow:\(primary.id):inference.auth-rejected",
                    kind: .inferred,
                    title: String(localized: "Credential rejection or insufficient scope is likely"),
                    detail: String(
                        localized: "A credential signal was present, but captured traffic cannot verify its validity or server-side policy."
                    ),
                    sourceTransactionID: primary.id
                ))
            }
        }

        if let challenge = primary.responseHeader(named: "WWW-Authenticate")?.value {
            evidence.append(.init(
                id: "flow:\(primary.id):response.header.www-authenticate",
                kind: .observed,
                title: String(localized: "Authentication challenge captured"),
                detail: bounded(challenge, characters: 160),
                sourceTransactionID: primary.id
            ))
        }

        return InvestigationResult(
            recipe: .checkAuthentication,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: scope.map(\.id),
            scopeSummary: scopeSummary(selectedCount: selected.count, requestCount: scope.count),
            summary: authenticationSummary(primary, hasCredentialSignal: hasAuthorization || hasCookie),
            evidence: evidence,
            nextStep: String(
                localized: "Compare the credential scheme and required scope without exposing the credential value."
            )
        )
    }

    private func prepareBugReport(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        session: [InvestigationTransactionSnapshot]
    )
        -> InvestigationResult
    {
        let scope = boundedScope(
            primary: primary,
            selected: selected,
            related: nearbyTransactions(to: primary, in: session)
        )
        var evidence = [InvestigationEvidence(
            id: "flow:\(primary.id):bug-report.request",
            kind: .observed,
            title: "\(primary.request.method) \(primary.request.path)",
            detail: primary.request.host,
            sourceTransactionID: primary.id
        )]
        if let status = primary.statusCode {
            evidence.append(.init(
                id: "flow:\(primary.id):bug-report.status",
                kind: .observed,
                title: String(localized: "HTTP \(status) response"),
                detail: primary.response?.statusMessage ?? String(localized: "Captured response"),
                sourceTransactionID: primary.id
            ))
        }
        if let clientApp = primary.clientApp {
            evidence.append(.init(
                id: "flow:\(primary.id):bug-report.client",
                kind: .observed,
                title: String(localized: "Captured from \(clientApp)"),
                detail: String(localized: "Client attribution reported by Rockxy."),
                sourceTransactionID: primary.id
            ))
        }
        if let rule = primary.matchedRuleName {
            evidence.append(.init(
                id: "flow:\(primary.id):bug-report.rule",
                kind: .observed,
                title: String(localized: "Rule affected this request: \(rule)"),
                detail: primary
                    .matchedRuleActionSummary ?? String(localized: "Review the matched rule before sharing."),
                sourceTransactionID: primary.id
            ))
        }

        return InvestigationResult(
            recipe: .prepareBugReport,
            selectedTransactionID: primary.id,
            scopeTransactionIDs: scope.map(\.id),
            scopeSummary: scopeSummary(selectedCount: selected.count, requestCount: scope.count),
            summary: String(localized: "Rockxy prepared a bounded evidence package for this captured failure."),
            evidence: evidence,
            nextStep: String(localized: "Review the exact redacted payload before copying or sharing any evidence.")
        )
    }

    private func nearbyTransactions(
        to primary: InvestigationTransactionSnapshot,
        in session: [InvestigationTransactionSnapshot]
    )
        -> [InvestigationTransactionSnapshot]
    {
        session
            .filter { $0.id != primary.id && $0.request.host == primary.request.host }
            .sorted {
                abs($0.timestamp.timeIntervalSince(primary.timestamp))
                    < abs($1.timestamp.timeIntervalSince(primary.timestamp))
            }
    }

    private func boundedScope(
        primary: InvestigationTransactionSnapshot,
        selected: [InvestigationTransactionSnapshot],
        related: [InvestigationTransactionSnapshot]
    )
        -> [InvestigationTransactionSnapshot]
    {
        var values: [InvestigationTransactionSnapshot] = [primary]
        let candidates = Array(selected.dropFirst()) + related
        for candidate in candidates where !values.contains(where: { $0.id == candidate.id }) {
            values.append(candidate)
            if values.count == InvestigationContextLimits.default.maxTransactions {
                break
            }
        }
        return values
    }

    private func failureSummary(_ primary: InvestigationTransactionSnapshot, repeatedCount: Int) -> String {
        switch primary.statusCode {
        case 429:
            if repeatedCount > 1 {
                return String(localized: "Server returned HTTP 429 after repeated requests.")
            }
            return String(localized: "Server returned HTTP 429 for the selected request.")
        case let status? where status >= 500:
            return String(localized: "Server returned HTTP \(status) for the selected request.")
        case 401,
             403:
            return String(localized: "The selected request was rejected by an authentication or authorization check.")
        case let status? where status >= 400:
            return String(localized: "Server returned HTTP \(status) for the selected request.")
        case nil where primary.isFailed:
            return String(localized: "The selected request failed before a completed response was captured.")
        default:
            return String(localized: "Rockxy found no captured HTTP failure status for the selected request.")
        }
    }

    private func authenticationSummary(
        _ primary: InvestigationTransactionSnapshot,
        hasCredentialSignal: Bool
    )
        -> String
    {
        if primary.statusCode == 401 {
            return hasCredentialSignal
                ? String(localized: "A credential signal was present, but the server did not authenticate it.")
                : String(localized: "The server requested authentication and no common credential header was captured.")
        }
        if primary.statusCode == 403 {
            return String(
                localized: "The server denied access; captured traffic cannot verify the required permission policy."
            )
        }
        return String(localized: "Rockxy found no captured 401 or 403 response for this request.")
    }

    private func nextStepForFailure(_ primary: InvestigationTransactionSnapshot) -> String {
        switch primary.statusCode {
        case 429:
            String(localized: "Open an editable replay draft and verify it before sending.")
        case 401,
             403:
            String(localized: "Compare authentication evidence with a successful request.")
        case let status? where status >= 500:
            String(localized: "Capture one retry and compare server timing and response evidence.")
        default:
            String(localized: "Reveal the strongest evidence and verify it against a fresh capture.")
        }
    }

    private func scopeSummary(selectedCount: Int, requestCount: Int) -> String {
        if selectedCount > 1 {
            return String(localized: "\(selectedCount) selected requests")
        }
        let relatedCount = max(0, requestCount - 1)
        return relatedCount == 0
            ? String(localized: "Selected request")
            : String(localized: "Selected request + \(relatedCount) related requests")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1_000)
        }
        return String(format: "%.2f s", duration)
    }

    private func bounded(_ value: String, characters: Int) -> String {
        guard value.count > characters else {
            return value
        }
        return String(value.prefix(characters)) + "…"
    }
}

// MARK: - DebugAssistantEngineError

enum DebugAssistantEngineError: LocalizedError, Equatable {
    case noSelection

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noSelection:
            String(localized: "Select at least one request to investigate.")
        }
    }
}
