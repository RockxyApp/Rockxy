import Foundation
import os

nonisolated(unsafe) private let logger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "MCPFlowQueryService"
)

// MARK: - MCPFlowQueryService

struct MCPFlowQueryService {
    // MARK: Internal

    /// Reference to the server coordinator for dynamic provider resolution.
    /// The coordinator outlives the MCP server, so this is always valid.
    let serverCoordinator: MCPServerCoordinator
    let redactionPolicy: MCPRedactionPolicy

    func getRecentFlows(
        limit: Int,
        filterHost: String?,
        filterMethod: String?,
        filterStatusCode: Int?
    )
        async -> MCPToolCallResult
    {
        let capped = max(1, min(limit, MCPLimits.maxFlowResults))
        let transactions = await fetchTransactions(limit: MCPLimits.maxFlowResults)
        var filtered = transactions

        if let host = filterHost {
            let lowerHost = host.lowercased()
            filtered = filtered.filter { $0.request.host.lowercased().contains(lowerHost) }
        }

        if let method = filterMethod {
            let upperMethod = method.uppercased()
            filtered = filtered.filter { $0.request.method == upperMethod }
        }

        if let statusCode = filterStatusCode {
            filtered = filtered.filter { $0.response?.statusCode == statusCode }
        }

        let recent = Array(filtered.suffix(capped).reversed())
        let summaries = recent.map { flowSummary(for: $0) }
        return jsonResult(["flows": .array(summaries), "total_count": .int(filtered.count)])
    }

    func getFlowDetail(flowId: UUID) async -> MCPToolCallResult {
        guard let transaction = await fetchTransaction(for: flowId) else {
            return errorResult("Flow not found: \(flowId.uuidString)")
        }

        let detail = buildFlowDetail(for: transaction)
        return jsonResult(detail)
    }

    func searchFlows(
        query: String?,
        method: String?,
        statusMin: Int?,
        statusMax: Int?,
        limit: Int
    )
        async -> MCPToolCallResult
    {
        let transactions = await fetchTransactions(limit: MCPLimits.maxFlowResults)

        let capped = min(limit, MCPLimits.maxFlowResults)
        var filtered = transactions

        if let query, !query.isEmpty {
            let lowerQuery = query.lowercased()
            filtered = filtered.filter { $0.request.url.absoluteString.lowercased().contains(lowerQuery) }
        }

        if let method {
            let upperMethod = method.uppercased()
            filtered = filtered.filter { $0.request.method == upperMethod }
        }

        if let statusMin {
            filtered = filtered.filter { ($0.response?.statusCode ?? 0) >= statusMin }
        }

        if let statusMax {
            filtered = filtered.filter { ($0.response?.statusCode ?? Int.max) <= statusMax }
        }

        let results = Array(filtered.suffix(capped).reversed())
        let summaries = results.map { flowSummary(for: $0) }
        return jsonResult(["flows": .array(summaries), "total_count": .int(filtered.count)])
    }

    func filterFlows(
        filters: [[String: MCPJSONValue]],
        combination: String
    )
        async -> MCPToolCallResult
    {
        let transactions = await fetchTransactions(limit: MCPLimits.maxFlowResults)

        let useAnd = combination.lowercased() != "or"
        let predicates = filters.compactMap { buildPredicate(from: $0) }

        guard !predicates.isEmpty else {
            return errorResult("No valid filters provided")
        }

        let filtered = transactions.filter { txn in
            if useAnd {
                predicates.allSatisfy { $0(txn) }
            } else {
                predicates.contains { $0(txn) }
            }
        }

        let capped = Array(filtered.suffix(MCPLimits.maxFlowResults).reversed())
        let summaries = capped.map { flowSummary(for: $0) }
        return jsonResult(["flows": .array(summaries), "total_count": .int(filtered.count)])
    }

    func exportFlowAsCurl(flowId: UUID) async -> MCPToolCallResult {
        guard let transaction = await fetchTransaction(for: flowId) else {
            return errorResult("Flow not found: \(flowId.uuidString)")
        }

        let curl = RequestCopyFormatter.curl(for: transaction)
        let redacted = redactionPolicy.redactCurlCommand(curl)
        return MCPToolCallResult(
            content: [.text(redacted)],
            isError: nil
        )
    }

    // MARK: Private

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func extractFieldValue(field: String, from transaction: HTTPTransaction) -> String {
        switch field {
        case "host":
            transaction.request.host
        case "method":
            transaction.request.method
        case "status_code":
            transaction.response.map { "\($0.statusCode)" } ?? ""
        case "path":
            transaction.request.path
        case "client_app":
            transaction.clientApp ?? ""
        case "state":
            transaction.state.rawValue
        default:
            ""
        }
    }

    private static func applyOperator(op: String, fieldValue: String, targetValue: String) -> Bool {
        let lowerField = fieldValue.lowercased()
        let lowerTarget = targetValue.lowercased()

        switch op {
        case "equals":
            return lowerField == lowerTarget
        case "not_equals":
            return lowerField != lowerTarget
        case "contains":
            return lowerField.contains(lowerTarget)
        case "starts_with":
            return lowerField.hasPrefix(lowerTarget)
        case "gt":
            guard let fieldNum = Int(fieldValue), let targetNum = Int(targetValue) else {
                return false
            }
            return fieldNum > targetNum
        case "lt":
            guard let fieldNum = Int(fieldValue), let targetNum = Int(targetValue) else {
                return false
            }
            return fieldNum < targetNum
        default:
            return false
        }
    }

    /// Try live provider first; fall back to SessionStore for persisted data.
    private func fetchTransactions(limit: Int) async -> [HTTPTransaction] {
        // Try live in-memory data from the coordinator's flow provider
        if let live = await MainActor.run(body: { serverCoordinator.currentFlowProvider()?.liveTransactions }) {
            return live
        }

        // Fall back to persisted transactions in SQLite
        logger.debug("Live flow provider unavailable, falling back to SessionStore")
        guard let store = await MainActor.run(body: { serverCoordinator.resolveSessionStore() }) else {
            return []
        }

        do {
            let capped = min(limit, MCPLimits.maxFlowResults)
            return try await store.loadTransactions(limit: capped)
        } catch {
            logger.error("SessionStore fallback failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Try live provider first; fall back to SessionStore by ID lookup.
    private func fetchTransaction(for id: UUID) async -> HTTPTransaction? {
        // Try live in-memory lookup
        if let txn = await MainActor.run(body: { serverCoordinator.currentFlowProvider()?.liveTransaction(for: id) }) {
            return txn
        }

        // Fall back to persisted transaction lookup
        logger.debug("Live flow provider unavailable for ID lookup, falling back to SessionStore")
        guard let store = await MainActor.run(body: { serverCoordinator.resolveSessionStore() }) else {
            return nil
        }

        do {
            return try await store.loadTransaction(byID: id)
        } catch {
            logger.error("SessionStore ID lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func flowSummary(for transaction: HTTPTransaction) -> MCPJSONValue {
        let url = redactionPolicy.redactURL(transaction.request.url.absoluteString)
        var fields: [String: MCPJSONValue] = [
            "id": .string(transaction.id.uuidString),
            "method": .string(transaction.request.method),
            "url": .string(url),
            "host": .string(transaction.request.host),
            "path": .string(transaction.request.path),
            "state": .string(transaction.state.rawValue),
            "timestamp": .string(Self.dateFormatter.string(from: transaction.timestamp)),
        ]

        if let response = transaction.response {
            fields["status_code"] = .int(response.statusCode)
        }

        if let timing = transaction.timingInfo {
            fields["duration_ms"] = .double(timing.totalDuration * 1_000)
        }

        if let clientApp = transaction.clientApp {
            fields["client_app"] = .string(clientApp)
        }

        if transaction.isPinned {
            fields["is_pinned"] = .bool(true)
        }

        if let ruleName = transaction.matchedRuleName {
            fields["matched_rule"] = .string(ruleName)
        }

        return .object(fields)
    }

    private func buildFlowDetail(for transaction: HTTPTransaction) -> MCPJSONValue {
        let url = redactionPolicy.redactURL(transaction.request.url.absoluteString)

        var request: [String: MCPJSONValue] = [
            "method": .string(transaction.request.method),
            "url": .string(url),
            "http_version": .string(transaction.request.httpVersion),
            "headers": .array(redactedHeaders(transaction.request.headers)),
        ]

        if let body = transaction.request.body {
            request["body_preview"] = bodyPreview(body, contentType: transaction.request.contentType)
            request["body_size"] = .int(body.count)
        }

        var detail: [String: MCPJSONValue] = [
            "id": .string(transaction.id.uuidString),
            "timestamp": .string(Self.dateFormatter.string(from: transaction.timestamp)),
            "state": .string(transaction.state.rawValue),
            "request": .object(request),
        ]

        if let resp = transaction.response {
            var response: [String: MCPJSONValue] = [
                "status_code": .int(resp.statusCode),
                "status_message": .string(resp.statusMessage),
                "headers": .array(redactedHeaders(resp.headers)),
            ]

            if let body = resp.body {
                response["body_preview"] = bodyPreview(body, contentType: resp.contentType)
                response["body_size"] = .int(body.count)
            }

            detail["response"] = .object(response)
        }

        if let timing = transaction.timingInfo {
            detail["timing"] = .object([
                "dns_ms": .double(timing.dnsLookup * 1_000),
                "tcp_ms": .double(timing.tcpConnection * 1_000),
                "tls_ms": .double(timing.tlsHandshake * 1_000),
                "ttfb_ms": .double(timing.timeToFirstByte * 1_000),
                "transfer_ms": .double(timing.contentTransfer * 1_000),
                "total_ms": .double(timing.totalDuration * 1_000),
            ])
        }

        if let clientApp = transaction.clientApp {
            detail["client_app"] = .string(clientApp)
        }

        if transaction.isPinned {
            detail["is_pinned"] = .bool(true)
        }

        if let ruleName = transaction.matchedRuleName {
            detail["matched_rule"] = .string(ruleName)
        }

        if let graphql = transaction.graphQLInfo {
            var gqlFields: [String: MCPJSONValue] = [
                "operation_type": .string(graphql.operationType.rawValue),
                "query": .string(graphql.query),
            ]
            if let name = graphql.operationName {
                gqlFields["operation_name"] = .string(name)
            }
            detail["graphql"] = .object(gqlFields)
        }

        return .object(detail)
    }

    private func redactedHeaders(_ headers: [HTTPHeader]) -> [MCPJSONValue] {
        let tuples = headers.map { (name: $0.name, value: $0.value) }
        let redacted = redactionPolicy.redactHeaders(tuples)
        return redacted.map { header in
            .object(["name": .string(header.name), "value": .string(header.value)])
        }
    }

    private func bodyPreview(_ body: Data, contentType: ContentType?) -> MCPJSONValue {
        let previewSize = min(body.count, MCPLimits.maxBodyPreviewSize)
        let slice = body.prefix(previewSize)

        guard let text = String(data: slice, encoding: .utf8) else {
            return .string("<binary data, \(SizeFormatter.format(bytes: body.count))>")
        }

        let redacted = redactionPolicy.redactBody(text, contentType: contentType)
        if body.count > previewSize {
            return .string(redacted + "\n... [truncated, total \(SizeFormatter.format(bytes: body.count))]")
        }
        return .string(redacted)
    }

    private func buildPredicate(from filter: [String: MCPJSONValue]) -> ((HTTPTransaction) -> Bool)? {
        guard case let .string(field) = filter["field"],
              case let .string(op) = filter["operator"],
              case let .string(value) = filter["value"] else
        {
            return nil
        }

        return { transaction in
            let fieldValue = Self.extractFieldValue(field: field, from: transaction)
            return Self.applyOperator(op: op, fieldValue: fieldValue, targetValue: value)
        }
    }

    private func errorResult(_ message: String) -> MCPToolCallResult {
        logger.warning("Tool call error: \(message, privacy: .public)")
        let payload: MCPJSONValue = .object(["error": .string(message)])

        do {
            let data = try payload.encodeToData()
            let text = String(data: data, encoding: .utf8) ?? "{\"error\":\"Unknown error\"}"
            return MCPToolCallResult(
                content: [.text(text)],
                isError: true
            )
        } catch {
            logger.warning("Failed to encode MCP flow error result: \(error.localizedDescription, privacy: .public)")
            return MCPToolCallResult(
                content: [.text("{\"error\":\"Unknown error\"}")],
                isError: true
            )
        }
    }

    private func jsonResult(_ value: MCPJSONValue) -> MCPToolCallResult {
        do {
            let data = try value.encodeToData()
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return MCPToolCallResult(content: [.text(text)], isError: nil)
        } catch {
            logger.error("Failed to encode tool result: \(error.localizedDescription, privacy: .public)")
            return MCPToolCallResult(
                content: [.text("{\"error\": \"Internal encoding error\"}")],
                isError: true
            )
        }
    }
}
