import Foundation

// Defines Codable wrappers for persisting captured sessions and transactions.

// MARK: - BodyEncoding

private enum BodyEncoding {
    static let maxInlineSize = 10 * 1_024 * 1_024 // 10 MB

    static func encode(_ data: Data?) -> (base64: String?, truncated: Bool, originalSize: Int?) {
        guard let data else {
            return (nil, false, nil)
        }
        if data.count > maxInlineSize {
            return (nil, true, data.count)
        }
        return (data.base64EncodedString(), false, nil)
    }

    static func decode(base64: String?, truncated: Bool) -> Data? {
        guard !truncated, let base64 else {
            return nil
        }
        return Data(base64Encoded: base64)
    }
}

// MARK: - CodableSession

/// Top-level container for a serialized Rockxy capture session.
struct CodableSession: Codable {
    let metadata: SessionMetadata
    let transactions: [CodableTransaction]
    let logEntries: [CodableLogEntry]?
}

// MARK: - SessionMetadata

struct SessionMetadata: Codable {
    let rockxyVersion: String
    let formatVersion: Int
    let captureStartDate: Date?
    let captureEndDate: Date?
    let transactionCount: Int
}

// MARK: - CodableTransaction

struct CodableTransaction: Codable {
    // MARK: Lifecycle

    init(from transaction: HTTPTransaction) {
        self.id = transaction.id
        self.timestamp = transaction.timestamp
        self.state = transaction.state.rawValue
        self.request = CodableRequest(from: transaction.request)
        self.response = transaction.response.map { CodableResponse(from: $0) }
        self.timingInfo = transaction.timingInfo.map { CodableTiming(from: $0) }
        self.webSocketConnection = transaction.webSocketConnection
            .map { CodableWebSocketConnection(from: $0) }
        self.graphQLInfo = transaction.graphQLInfo
            .map { CodableGraphQLInfo(from: $0) }
        self.sourcePort = transaction.sourcePort
        self.clientApp = transaction.clientApp
        self.comment = transaction.comment
        self.highlightColor = transaction.highlightColor?.rawValue
        self.isPinned = transaction.isPinned
        self.isSaved = transaction.isSaved
        self.isTLSFailure = transaction.isTLSFailure
        self.matchedRuleID = transaction.matchedRuleID
        self.matchedRuleName = transaction.matchedRuleName
        self.matchedRuleActionSummary = transaction.matchedRuleActionSummary
        self.matchedRulePattern = transaction.matchedRulePattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        state = try container.decode(String.self, forKey: .state)
        request = try container.decode(CodableRequest.self, forKey: .request)
        response = try container.decodeIfPresent(CodableResponse.self, forKey: .response)
        timingInfo = try container.decodeIfPresent(CodableTiming.self, forKey: .timingInfo)
        webSocketConnection = try container.decodeIfPresent(
            CodableWebSocketConnection.self, forKey: .webSocketConnection
        )
        graphQLInfo = try container.decodeIfPresent(CodableGraphQLInfo.self, forKey: .graphQLInfo)
        sourcePort = try container.decodeIfPresent(UInt16.self, forKey: .sourcePort)
        clientApp = try container.decodeIfPresent(String.self, forKey: .clientApp)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        highlightColor = try container.decodeIfPresent(String.self, forKey: .highlightColor)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        isTLSFailure = try container.decodeIfPresent(Bool.self, forKey: .isTLSFailure) ?? false
        matchedRuleID = try container.decodeIfPresent(UUID.self, forKey: .matchedRuleID)
        matchedRuleName = try container.decodeIfPresent(String.self, forKey: .matchedRuleName)
        matchedRuleActionSummary = try container.decodeIfPresent(String.self, forKey: .matchedRuleActionSummary)
        matchedRulePattern = try container.decodeIfPresent(String.self, forKey: .matchedRulePattern)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case state
        case request
        case response
        case timingInfo
        case webSocketConnection
        case graphQLInfo
        case sourcePort
        case clientApp
        case comment
        case highlightColor
        case isPinned
        case isSaved
        case isTLSFailure
        case matchedRuleID
        case matchedRuleName
        case matchedRuleActionSummary
        case matchedRulePattern
    }

    let id: UUID
    let timestamp: Date
    let state: String
    let request: CodableRequest
    let response: CodableResponse?
    let timingInfo: CodableTiming?
    let webSocketConnection: CodableWebSocketConnection?
    let graphQLInfo: CodableGraphQLInfo?
    let sourcePort: UInt16?
    let clientApp: String?
    let comment: String?
    let highlightColor: String?
    let isPinned: Bool
    let isSaved: Bool
    let isTLSFailure: Bool
    let matchedRuleID: UUID?
    let matchedRuleName: String?
    let matchedRuleActionSummary: String?
    let matchedRulePattern: String?

    func toLiveModel() -> HTTPTransaction {
        let transaction = HTTPTransaction(
            id: id,
            timestamp: timestamp,
            request: request.toLiveModel(),
            response: response?.toLiveModel(),
            state: TransactionState(rawValue: state) ?? .pending,
            timingInfo: timingInfo?.toLiveModel(),
            webSocketConnection: webSocketConnection?.toLiveModel(),
            graphQLInfo: graphQLInfo?.toLiveModel()
        )
        transaction.clientApp = clientApp
        transaction.sourcePort = sourcePort
        transaction.comment = comment
        transaction.highlightColor = highlightColor.flatMap { HighlightColor(rawValue: $0) }
        transaction.isPinned = isPinned
        transaction.isSaved = isSaved
        transaction.isTLSFailure = isTLSFailure
        transaction.matchedRuleID = matchedRuleID
        transaction.matchedRuleName = matchedRuleName
        transaction.matchedRuleActionSummary = matchedRuleActionSummary
        transaction.matchedRulePattern = matchedRulePattern
        return transaction
    }
}

// MARK: - CodableRequest

struct CodableRequest: Codable {
    // MARK: Lifecycle

    init(from request: HTTPRequestData) {
        self.method = request.method
        self.url = request.url.absoluteString
        self.httpVersion = request.httpVersion
        self.headers = request.headers.map { CodableHeader(from: $0) }
        let encoded = BodyEncoding.encode(request.body)
        self.bodyBase64 = encoded.base64
        self.bodyTruncated = encoded.truncated
        self.originalBodySize = encoded.originalSize
        self.contentType = request.contentType?.rawValue
    }

    // MARK: Internal

    let method: String
    let url: String
    let httpVersion: String
    let headers: [CodableHeader]
    let bodyBase64: String?
    let bodyTruncated: Bool
    let originalBodySize: Int?
    let contentType: String?

    func toLiveModel() -> HTTPRequestData {
        HTTPRequestData(
            method: method,
            url: URL(string: url) ?? URL(string: "about:blank")!, // swiftlint:disable:this force_unwrapping
            httpVersion: httpVersion,
            headers: headers.map { $0.toLiveModel() },
            body: BodyEncoding.decode(base64: bodyBase64, truncated: bodyTruncated),
            contentType: contentType.flatMap { ContentType(rawValue: $0) }
        )
    }
}

// MARK: - CodableResponse

struct CodableResponse: Codable {
    // MARK: Lifecycle

    init(from response: HTTPResponseData) {
        self.statusCode = response.statusCode
        self.statusMessage = response.statusMessage
        self.headers = response.headers.map { CodableHeader(from: $0) }
        let encoded = BodyEncoding.encode(response.body)
        self.bodyBase64 = encoded.base64
        self.bodyTruncated = encoded.truncated
        self.originalBodySize = encoded.originalSize
        self.contentType = response.contentType?.rawValue
    }

    // MARK: Internal

    let statusCode: Int
    let statusMessage: String
    let headers: [CodableHeader]
    let bodyBase64: String?
    let bodyTruncated: Bool
    let originalBodySize: Int?
    let contentType: String?

    func toLiveModel() -> HTTPResponseData {
        HTTPResponseData(
            statusCode: statusCode,
            statusMessage: statusMessage,
            headers: headers.map { $0.toLiveModel() },
            body: BodyEncoding.decode(base64: bodyBase64, truncated: bodyTruncated),
            contentType: contentType.flatMap { ContentType(rawValue: $0) }
        )
    }
}

// MARK: - CodableHeader

struct CodableHeader: Codable {
    // MARK: Lifecycle

    init(from header: HTTPHeader) {
        self.name = header.name
        self.value = header.value
    }

    // MARK: Internal

    let name: String
    let value: String

    func toLiveModel() -> HTTPHeader {
        HTTPHeader(name: name, value: value)
    }
}

// MARK: - CodableTiming

struct CodableTiming: Codable {
    // MARK: Lifecycle

    init(from timing: TimingInfo) {
        self.dnsLookup = timing.dnsLookup
        self.tcpConnection = timing.tcpConnection
        self.tlsHandshake = timing.tlsHandshake
        self.timeToFirstByte = timing.timeToFirstByte
        self.contentTransfer = timing.contentTransfer
    }

    // MARK: Internal

    let dnsLookup: TimeInterval
    let tcpConnection: TimeInterval
    let tlsHandshake: TimeInterval
    let timeToFirstByte: TimeInterval
    let contentTransfer: TimeInterval

    func toLiveModel() -> TimingInfo {
        TimingInfo(
            dnsLookup: dnsLookup,
            tcpConnection: tcpConnection,
            tlsHandshake: tlsHandshake,
            timeToFirstByte: timeToFirstByte,
            contentTransfer: contentTransfer
        )
    }
}

// MARK: - CodableWebSocketConnection

struct CodableWebSocketConnection: Codable {
    // MARK: Lifecycle

    init(from connection: WebSocketConnection) {
        self.upgradeRequest = CodableRequest(from: connection.upgradeRequest)
        self.frames = connection.frames.map { CodableWebSocketFrame(from: $0) }
    }

    // MARK: Internal

    let upgradeRequest: CodableRequest
    let frames: [CodableWebSocketFrame]

    func toLiveModel() -> WebSocketConnection {
        WebSocketConnection(
            upgradeRequest: upgradeRequest.toLiveModel(),
            frames: frames.map { $0.toLiveModel() }
        )
    }
}

// MARK: - CodableWebSocketFrame

struct CodableWebSocketFrame: Codable {
    // MARK: Lifecycle

    init(from frame: WebSocketFrameData) {
        self.id = frame.id
        self.timestamp = frame.timestamp
        self.direction = frame.direction.rawValue
        self.opcode = frame.opcode.rawValue
        self.payloadBase64 = frame.payload.base64EncodedString()
        self.isFinal = frame.isFinal
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let direction: String
    let opcode: UInt8
    let payloadBase64: String
    let isFinal: Bool

    func toLiveModel() -> WebSocketFrameData {
        WebSocketFrameData(
            id: id,
            timestamp: timestamp,
            direction: FrameDirection(rawValue: direction) ?? .received,
            opcode: FrameOpcode(rawValue: opcode) ?? .text,
            payload: Data(base64Encoded: payloadBase64) ?? Data(),
            isFinal: isFinal
        )
    }
}

// MARK: - CodableGraphQLInfo

struct CodableGraphQLInfo: Codable {
    // MARK: Lifecycle

    init(from info: GraphQLInfo) {
        self.operationName = info.operationName
        self.operationType = info.operationType.rawValue
        self.query = info.query
        self.variables = info.variables
    }

    // MARK: Internal

    let operationName: String?
    let operationType: String
    let query: String
    let variables: String?

    func toLiveModel() -> GraphQLInfo {
        GraphQLInfo(
            operationName: operationName,
            operationType: GraphQLOperationType(rawValue: operationType) ?? .query,
            query: query,
            variables: variables
        )
    }
}

// MARK: - CodableLogEntry

struct CodableLogEntry: Codable {
    // MARK: Lifecycle

    init(from entry: LogEntry) {
        self.id = entry.id
        self.timestamp = entry.timestamp
        self.level = entry.level.rawValue
        self.message = entry.message
        let (type, value) = Self.encodeSource(entry.source)
        self.sourceType = type
        self.sourceValue = value
        self.processName = entry.processName
        self.subsystem = entry.subsystem
        self.category = entry.category
        self.metadata = entry.metadata.isEmpty ? nil : entry.metadata
        self.correlatedTransactionId = entry.correlatedTransactionId
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let level: Int
    let message: String
    let sourceType: String
    let sourceValue: String
    let processName: String?
    let subsystem: String?
    let category: String?
    let metadata: [String: String]?
    let correlatedTransactionId: UUID?

    func toLiveModel() -> LogEntry {
        LogEntry(
            id: id,
            timestamp: timestamp,
            level: LogLevel(rawValue: level) ?? .info,
            message: message,
            source: Self.decodeSource(type: sourceType, value: sourceValue),
            processName: processName,
            subsystem: subsystem,
            category: category,
            metadata: metadata ?? [:],
            correlatedTransactionId: correlatedTransactionId
        )
    }

    // MARK: Private

    private static func encodeSource(_ source: LogSource) -> (type: String, value: String) {
        switch source {
        case let .oslog(subsystem):
            ("oslog", subsystem)
        case let .processStdout(pid):
            ("processStdout", String(pid))
        case let .processStderr(pid):
            ("processStderr", String(pid))
        case let .custom(name):
            ("custom", name)
        }
    }

    private static func decodeSource(type: String, value: String) -> LogSource {
        switch type {
        case "oslog":
            .oslog(subsystem: value)
        case "processStdout":
            .processStdout(pid: Int32(value) ?? 0)
        case "processStderr":
            .processStderr(pid: Int32(value) ?? 0)
        case "custom":
            .custom(name: value)
        default:
            .custom(name: "\(type):\(value)")
        }
    }
}
