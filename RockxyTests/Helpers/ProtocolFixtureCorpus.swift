import Foundation

// MARK: - ProtocolFixtureCorpus

enum ProtocolFixtureCorpus {
    static let fixtures: [ProtocolFixture] = [
        .httpJSONSmoke,
        .aiSSEContractSmoke,
        .aiAnthropicSSEContractSmoke,
        .aiInterruptedToolCallContractSmoke,
        .aiProviderErrorNoUsageContractSmoke,
        .aiEmbeddingContractSmoke,
        .aiRAGContractSmoke,
        .aiMalformedRetrievalContractSmoke,
        .evmJSONRPCContractSmoke,
        .evmGasReceiptAndSendRawContractSmoke,
        .evmBatchErrorAndLargeContractSmoke,
        .evmMalformedJSONRPCContractSmoke,
        .solanaHTTPRPCContractSmoke,
        .solanaWebSocketSubscriptionContractSmoke,
        .solanaLongAndMalformedSubscriptionContractSmoke,
        .x402ContractSmoke,
        .x402MalformedAndMissingProofContractSmoke,
        .x402ProviderErrorMetadataContractSmoke,
        .malformedPayloadContractSmoke,
        .hostileOversizedDeepJSONContractSmoke,
        .hostileLongStringTruncatedContractSmoke,
        .hostilePartialSSEAndBytesContractSmoke,
    ]

    static let allowedSyntheticHosts: Set<String> = [
        "api.example.com",
        "ai.example.com",
        "rpc.example.com",
        "solana.example.com",
        "vector.example.com",
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
    let webSocketMessages: [ProtocolFixtureWebSocketMessage]
    let estimatedPayloadBytes: Int

    init(
        exchanges: [ProtocolFixtureExchange] = [],
        webSocketMessages: [ProtocolFixtureWebSocketMessage] = [],
        estimatedPayloadBytes: Int = 0
    ) {
        self.exchanges = exchanges
        self.webSocketMessages = webSocketMessages
        self.estimatedPayloadBytes = estimatedPayloadBytes
    }
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

struct ProtocolFixtureWebSocketMessage: Equatable {
    let direction: ProtocolFixtureWebSocketDirection
    let url: String
    let body: String
}

enum ProtocolFixtureWebSocketDirection: String, CaseIterable {
    case clientToServer
    case serverToClient
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
        if fixture.traffic.exchanges.isEmpty && fixture.traffic.webSocketMessages.isEmpty {
            failures.append("\(fixture.id): traffic must include exchanges or WebSocket messages.")
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
        if fixture.safetyClass == .malformed && fixture.expected.ux.fallbackBehavior == nil {
            failures.append("\(fixture.id): malformed fixtures must declare fallback behavior.")
        }
        if fixture.safetyClass == .large && fixture.sizeClass != .boundedStress {
            failures.append("\(fixture.id): large fixtures must use boundedStress size class.")
        }
        if fixture.sizeClass == .boundedStress && fixture.traffic.estimatedPayloadBytes <= 0 {
            failures.append("\(fixture.id): boundedStress fixtures must declare estimatedPayloadBytes.")
        }
        if fixture.traffic.estimatedPayloadBytes > 32_000 {
            failures.append("\(fixture.id): estimatedPayloadBytes exceeds the test corpus budget.")
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
        for message in fixture.traffic.webSocketMessages {
            findings.append(contentsOf: scanHost(message.url, fixtureID: fixture.id))
            findings.append(contentsOf: scan(text: message.body, fixtureID: fixture.id, context: "websocket body"))
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
            ("seed phrase-like sample", #"\b(?:abandon|ability|able|about|above|absent|absorb|abstract|absurd|abuse)\s+(?:[a-z]+\s+){10,23}[a-z]+\b"#),
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
