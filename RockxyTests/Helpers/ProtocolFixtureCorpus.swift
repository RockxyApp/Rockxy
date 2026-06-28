import Foundation

// MARK: - ProtocolFixtureCorpus

enum ProtocolFixtureCorpus {
    static let fixtures: [ProtocolFixture] = [
        .httpJSONSmoke,
        .aiSSEContractSmoke,
        .evmJSONRPCContractSmoke,
        .x402ContractSmoke,
        .malformedPayloadContractSmoke,
    ]

    static let allowedSyntheticHosts: Set<String> = [
        "api.example.com",
        "ai.example.com",
        "rpc.example.com",
        "payments.example.com",
        "test.invalid",
    ]
}

// MARK: - Protocol Fixture Schema

struct ProtocolFixture: Equatable, Identifiable {
    let id: String
    let title: String
    let family: ProtocolFixtureFamily
    let scenarioTags: Set<String>
    let traffic: ProtocolFixtureTraffic
    let expected: ProtocolFixtureExpectations
    let safetyClass: ProtocolFixtureSafetyClass
    let sizeClass: ProtocolFixtureSizeClass
    let traceability: ProtocolFixtureTraceability
}

enum ProtocolFixtureFamily: String, CaseIterable {
    case ordinaryHTTP = "ordinary-http"
    case ai = "ai"
    case web3RPC = "web3-rpc"
    case x402 = "x402"
    case unknown = "unknown"
}

enum ProtocolFixtureSafetyClass: String, CaseIterable {
    case ordinary
    case containsSyntheticSensitiveData
    case malformed
    case hostile
    case large
}

enum ProtocolFixtureSizeClass: String, CaseIterable {
    case small
    case medium
    case boundedStress
}

struct ProtocolFixtureTraffic: Equatable {
    let exchanges: [ProtocolFixtureExchange]
}

struct ProtocolFixtureExchange: Equatable {
    let request: ProtocolFixtureMessage
    let response: ProtocolFixtureMessage?
    let streamEvents: [ProtocolFixtureStreamEvent]

    init(
        request: ProtocolFixtureMessage,
        response: ProtocolFixtureMessage? = nil,
        streamEvents: [ProtocolFixtureStreamEvent] = []
    ) {
        self.request = request
        self.response = response
        self.streamEvents = streamEvents
    }
}

struct ProtocolFixtureMessage: Equatable {
    let method: String
    let url: String
    let statusCode: Int?
    let headers: [ProtocolFixtureHeader]
    let body: String?

    init(
        method: String,
        url: String,
        statusCode: Int? = nil,
        headers: [ProtocolFixtureHeader] = [],
        body: String? = nil
    ) {
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

struct ProtocolFixtureHeader: Equatable {
    let name: String
    let value: String
}

struct ProtocolFixtureStreamEvent: Equatable {
    let event: String?
    let data: String
}

struct ProtocolFixtureExpectations: Equatable {
    let metadataHints: Set<String>
    let redaction: ProtocolFixtureRedactionExpectation
    let ux: ProtocolFixtureUXExpectation
}

struct ProtocolFixtureRedactionExpectation: Equatable {
    let sensitiveFields: Set<String>
    let redactedMarkers: Set<String>
    let safeFields: Set<String>
}

struct ProtocolFixtureUXExpectation: Equatable {
    let requestListBadges: [String]
    let optionalColumns: [String: String]
    let inspectorTabs: [String]
    let warningStates: [String]
    let exportSummaryFields: [String]
    let mcpSummaryFields: [String]
    let fallbackBehavior: String?
}

struct ProtocolFixtureTraceability: Equatable {
    let parentIssue: Int
    let childIssues: Set<Int>
    let futureIssues: Set<Int>
}

// MARK: - Corpus Smoke Fixtures

private extension ProtocolFixture {
    static let commonTraceability = ProtocolFixtureTraceability(
        parentIssue: 176,
        childIssues: [186, 187, 194, 195],
        futureIssues: [143, 144, 145, 146, 177, 178, 179, 180]
    )

    static let httpJSONSmoke = ProtocolFixture(
        id: "foundation.http-json.redaction-smoke",
        title: "Ordinary JSON request with synthetic redaction candidate",
        family: .ordinaryHTTP,
        scenarioTags: ["http", "json", "redaction-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://api.example.com/v1/debug-smoke",
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"request_id":"fixture-request","api_key":"synthetic-api-key"}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://api.example.com/v1/debug-smoke",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"ok":true,"request_id":"fixture-request"}"#
                )
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["http", "json"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["api_key"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["request_id", "ok"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["JSON"],
                optionalColumns: ["content": "JSON"],
                inspectorTabs: ["Headers", "JSON", "Raw"],
                warningStates: [],
                exportSummaryFields: ["method", "host", "status", "redacted_fields"],
                mcpSummaryFields: ["method", "url", "status", "redacted"],
                fallbackBehavior: nil
            )
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let aiSSEContractSmoke = ProtocolFixture(
        id: "foundation.ai-sse.contract-smoke",
        title: "AI streaming response with synthetic tool call",
        family: .ai,
        scenarioTags: ["ai", "sse", "streaming", "tool-call", "contract-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://ai.example.com/v1/responses",
                    headers: [
                        .init(name: "Content-Type", value: "application/json"),
                        .init(name: "Authorization", value: "Bearer synthetic-ai-token"),
                    ],
                    body: #"{"model":"synthetic-model","input":"[SYNTHETIC_PROMPT]","tool_choice":"auto"}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://ai.example.com/v1/responses",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "text/event-stream")],
                    body: nil
                ),
                streamEvents: [
                    .init(event: "response.created", data: #"{"id":"resp_fixture","model":"synthetic-model"}"#),
                    .init(event: "response.tool_call.delta", data: #"{"name":"lookup_order","arguments":"{\"order_id\":\"fixture-order\"}"}"#),
                    .init(event: "response.completed", data: #"{"id":"resp_fixture","status":"completed"}"#),
                ]
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["ai", "streaming", "tool_call", "model_request"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["Authorization", "input", "tool_choice", "arguments"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["model", "status"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["AI", "Stream"],
                optionalColumns: ["protocol": "AI", "streaming": "true"],
                inspectorTabs: ["AI", "Stream", "Tool Calls", "Raw"],
                warningStates: ["prompt_redaction_candidate", "tool_payload_redaction_candidate"],
                exportSummaryFields: ["model", "stream_event_count", "tool_call_count", "redacted_fields"],
                mcpSummaryFields: ["model", "status", "streaming", "redacted"],
                fallbackBehavior: nil
            )
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let evmJSONRPCContractSmoke = ProtocolFixture(
        id: "foundation.evm-json-rpc.contract-smoke",
        title: "EVM JSON-RPC request with synthetic method summary",
        family: .web3RPC,
        scenarioTags: ["web3", "evm", "json-rpc", "contract-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://rpc.example.com/evm",
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"jsonrpc":"2.0","id":"fixture-1","method":"eth_call","params":[{"to":"0xSyntheticContract","data":"0xsyntheticCallData"},"latest"]}"#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://rpc.example.com/evm",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"jsonrpc":"2.0","id":"fixture-1","result":"0xsyntheticResult"}"#
                )
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["web3", "json_rpc", "evm", "eth_call"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["params.data"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["jsonrpc", "method", "id"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["RPC", "EVM"],
                optionalColumns: ["rpc_method": "eth_call"],
                inspectorTabs: ["RPC", "JSON", "Raw"],
                warningStates: [],
                exportSummaryFields: ["rpc_method", "chain_hint", "redacted_fields"],
                mcpSummaryFields: ["rpc_method", "status", "redacted"],
                fallbackBehavior: nil
            )
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let x402ContractSmoke = ProtocolFixture(
        id: "foundation.x402.contract-smoke",
        title: "x402-style payment-required retry flow",
        family: .x402,
        scenarioTags: ["x402", "payment-required", "retry", "contract-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "GET",
                    url: "https://payments.example.com/protected/report",
                    headers: [.init(name: "Accept", value: "application/json")]
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://payments.example.com/protected/report",
                    statusCode: 402,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"x402Version":1,"paymentRequired":true,"challenge":"synthetic-payment-challenge"}"#
                )
            ),
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "GET",
                    url: "https://payments.example.com/protected/report",
                    headers: [
                        .init(name: "Accept", value: "application/json"),
                        .init(name: "X-Payment", value: "synthetic-payment-proof"),
                    ]
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://payments.example.com/protected/report",
                    statusCode: 200,
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"ok":true,"receipt":"synthetic-receipt"}"#
                )
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["x402", "payment_required", "retry_flow"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: ["X-Payment", "challenge", "receipt"],
                redactedMarkers: ["[REDACTED]"],
                safeFields: ["x402Version", "paymentRequired", "ok"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["x402", "402"],
                optionalColumns: ["payment_flow": "required_then_success"],
                inspectorTabs: ["Payment", "Headers", "Raw"],
                warningStates: ["payment_metadata_redaction_candidate"],
                exportSummaryFields: ["payment_required", "retry_count", "redacted_fields"],
                mcpSummaryFields: ["payment_flow", "status", "redacted"],
                fallbackBehavior: nil
            )
        ),
        safetyClass: .containsSyntheticSensitiveData,
        sizeClass: .small,
        traceability: commonTraceability
    )

    static let malformedPayloadContractSmoke = ProtocolFixture(
        id: "foundation.malformed-json.contract-smoke",
        title: "Malformed JSON payload with bounded fallback contract",
        family: .unknown,
        scenarioTags: ["malformed", "json", "fallback", "contract-smoke"],
        traffic: ProtocolFixtureTraffic(exchanges: [
            ProtocolFixtureExchange(
                request: ProtocolFixtureMessage(
                    method: "POST",
                    url: "https://test.invalid/malformed",
                    headers: [.init(name: "Content-Type", value: "application/json")],
                    body: #"{"message":"unterminated""#
                ),
                response: ProtocolFixtureMessage(
                    method: "HTTP",
                    url: "https://test.invalid/malformed",
                    statusCode: 400,
                    headers: [.init(name: "Content-Type", value: "text/plain")],
                    body: "Malformed synthetic payload"
                )
            )
        ]),
        expected: ProtocolFixtureExpectations(
            metadataHints: ["malformed", "fallback"],
            redaction: ProtocolFixtureRedactionExpectation(
                sensitiveFields: [],
                redactedMarkers: [],
                safeFields: ["message"]
            ),
            ux: ProtocolFixtureUXExpectation(
                requestListBadges: ["Malformed"],
                optionalColumns: ["parse_state": "failed"],
                inspectorTabs: ["Raw"],
                warningStates: ["malformed_payload"],
                exportSummaryFields: ["parse_state", "omitted_protocol_summary"],
                mcpSummaryFields: ["parse_state"],
                fallbackBehavior: "Show bounded raw fallback without protocol-specific inspector content."
            )
        ),
        safetyClass: .malformed,
        sizeClass: .small,
        traceability: commonTraceability
    )
}

// MARK: - Validation

enum ProtocolFixtureValidation {
    static func validate(_ fixture: ProtocolFixture) -> [String] {
        var failures: [String] = []

        if fixture.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append("Fixture ID is empty.")
        }
        if fixture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append("\(fixture.id): title is empty.")
        }
        if fixture.scenarioTags.isEmpty {
            failures.append("\(fixture.id): scenarioTags must not be empty.")
        }
        if fixture.traffic.exchanges.isEmpty {
            failures.append("\(fixture.id): traffic.exchanges must not be empty.")
        }
        if fixture.expected.metadataHints.isEmpty {
            failures.append("\(fixture.id): expected.metadataHints must not be empty.")
        }
        if fixture.expected.ux.requestListBadges.isEmpty {
            failures.append("\(fixture.id): expected.ux.requestListBadges must not be empty.")
        }
        if fixture.expected.ux.inspectorTabs.isEmpty {
            failures.append("\(fixture.id): expected.ux.inspectorTabs must not be empty.")
        }
        if fixture.expected.ux.exportSummaryFields.isEmpty {
            failures.append("\(fixture.id): expected.ux.exportSummaryFields must not be empty.")
        }
        if fixture.expected.ux.mcpSummaryFields.isEmpty {
            failures.append("\(fixture.id): expected.ux.mcpSummaryFields must not be empty.")
        }
        if fixture.traceability.parentIssue != 176 {
            failures.append("\(fixture.id): traceability.parentIssue must be #176.")
        }
        if !fixture.traceability.childIssues.isSuperset(of: [186, 187, 194, 195]) {
            failures.append("\(fixture.id): traceability.childIssues must include Group A child issues.")
        }

        return failures
    }
}

// MARK: - Safety Scanner

enum ProtocolFixtureSafetyScanner {
    struct Finding: Equatable {
        let fixtureID: String
        let reason: String
        let excerpt: String
    }

    static func scan(_ fixture: ProtocolFixture) -> [Finding] {
        var findings: [Finding] = []

        for exchange in fixture.traffic.exchanges {
            findings.append(contentsOf: scan(message: exchange.request, fixtureID: fixture.id))
            if let response = exchange.response {
                findings.append(contentsOf: scan(message: response, fixtureID: fixture.id))
            }
            for event in exchange.streamEvents {
                findings.append(contentsOf: scan(text: event.event ?? "", fixtureID: fixture.id, context: "stream event"))
                findings.append(contentsOf: scan(text: event.data, fixtureID: fixture.id, context: "stream data"))
            }
        }

        return findings
    }

    static func scan(text: String, fixtureID: String = "manual-scan", context: String = "text") -> [Finding] {
        let patterns: [(reason: String, regex: String)] = [
            ("local filesystem path", #"(?:/Users/|/private/var/|/Volumes/|[A-Za-z]:\\Users\\)"#),
            ("private key PEM block", #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
            ("OpenAI-style production token", #"\bsk-[A-Za-z0-9_-]{16,}"#),
            ("GitHub production token", #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{16,}"#),
            ("Slack production token", #"\bxox[baprs]-[A-Za-z0-9-]{16,}"#),
            ("AWS access key", #"\bAKIA[0-9A-Z]{16}\b"#),
            ("Ethereum private-key-like value", #"\b0x[0-9a-fA-F]{64}\b"#),
            ("realistic bearer token", #"Bearer\s+(?!(?:synthetic|fake|example)[A-Za-z0-9._~+/-]*\b)[A-Za-z0-9._~+/-]{20,}"#),
        ]

        var findings: [Finding] = []
        for pattern in patterns {
            if let match = firstMatch(pattern.regex, in: text) {
                findings.append(Finding(fixtureID: fixtureID, reason: "\(context): \(pattern.reason)", excerpt: match))
            }
        }

        findings.append(contentsOf: scanEmails(text: text, fixtureID: fixtureID, context: context))
        return findings
    }

    private static func scan(message: ProtocolFixtureMessage, fixtureID: String) -> [Finding] {
        var findings = scanHost(message.url, fixtureID: fixtureID)
        findings.append(contentsOf: scan(text: message.url, fixtureID: fixtureID, context: "url"))
        findings.append(contentsOf: message.headers.flatMap { header in
            scan(text: "\(header.name): \(header.value)", fixtureID: fixtureID, context: "header")
        })
        if let body = message.body {
            findings.append(contentsOf: scan(text: body, fixtureID: fixtureID, context: "body"))
        }
        return findings
    }

    private static func scanHost(_ urlString: String, fixtureID: String) -> [Finding] {
        guard let url = URL(string: urlString), let host = url.host else {
            return [Finding(fixtureID: fixtureID, reason: "url: invalid URL", excerpt: urlString)]
        }

        if ProtocolFixtureCorpus.allowedSyntheticHosts.contains(host) {
            return []
        }

        return [Finding(fixtureID: fixtureID, reason: "url: non-synthetic host", excerpt: host)]
    }

    private static func scanEmails(text: String, fixtureID: String, context: String) -> [Finding] {
        let emailRegex = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        return matches(emailRegex, in: text).compactMap { match in
            if match.lowercased().hasSuffix("@example.com") {
                return nil
            }
            return Finding(fixtureID: fixtureID, reason: "\(context): personal email-like value", excerpt: match)
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else {
                return nil
            }
            return String(text[swiftRange])
        }
    }
}
