import Foundation

func boundedBabylonString(_ value: String, bytes: Int) -> String {
    var truncatedBytes = Array(value.utf8.prefix(bytes))
    while !truncatedBytes.isEmpty {
        if let decoded = String(bytes: truncatedBytes, encoding: .utf8) {
            return decoded
        }
        truncatedBytes.removeLast()
    }
    return ""
}

private func boundedBabylonDuration(_ value: TimeInterval?) -> TimeInterval? {
    guard let value, value.isFinite, value >= 0, value <= 86_400 else {
        return nil
    }
    return value
}

// MARK: - BabylonConnectionPackageDTO

struct BabylonConnectionPackageDTO: Codable {
    struct Device: Codable {
        let name: String
        let model: String
    }

    struct Project: Codable {
        let name: String
        let bundleIdentifier: String
    }

    struct Capabilities: Codable {
        let sdkVersion: String
        let platform: String
        let payloadSchemaVersions: [String: Int]
        let supportedMessageTypes: [String]
        let supportedTrafficTypes: [String]?
        let maximumBodyBytes: Int
        let maximumWebSocketFrameBytes: Int
        let maximumCaptureMemoryBytes: Int
    }

    let device: Device
    let project: Project
    let icon: Data?
    let capabilities: Capabilities?
}

// MARK: - BabylonTrafficPackageDTO

struct BabylonTrafficPackageDTO: Codable {
    /// Unknown values from a newer SDK decode as `.unknown` instead of failing the whole frame.
    enum PackageType: String, Codable {
        case http
        case websocket
        case grpc
        case unknown

        // MARK: Lifecycle

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = PackageType(rawValue: raw) ?? .unknown
        }
    }

    struct Header: Codable {
        let key: String
        let value: String
    }

    struct Request: Codable {
        let url: String
        let method: String
        let headers: [Header]
        let body: Data?
    }

    struct Response: Codable {
        let statusCode: Int
        let headers: [Header]
    }

    struct CapturedError: Codable {
        // MARK: Lifecycle

        init(code: Int, message: String, domain: String? = nil, phase: String? = nil) {
            self.code = code
            self.message = boundedBabylonString(message, bytes: 1_024)
            self.domain = domain.map { boundedBabylonString($0, bytes: 256) }
            self.phase = phase.map { boundedBabylonString($0, bytes: 64) }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(Int.self, forKey: .code)
            message = try boundedBabylonString(container.decode(String.self, forKey: .message), bytes: 1_024)
            domain = try container.decodeIfPresent(String.self, forKey: .domain).map {
                boundedBabylonString($0, bytes: 256)
            }
            phase = try container.decodeIfPresent(String.self, forKey: .phase).map {
                boundedBabylonString($0, bytes: 64)
            }
        }

        // MARK: Internal

        let code: Int
        let message: String
        let domain: String?
        let phase: String?

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case code
            case message
            case domain
            case phase
        }
    }

    struct BodyOmission: Codable {
        let reason: String
        let observedBytes: Int
        let originalBytes: Int?
    }

    struct CorrelationContext: Codable {
        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case traceID = "trace_id"
            case stepID = "step_id"
            case createdAt = "created_at"
        }

        let sessionID: String
        let traceID: String
        let stepID: String
        let createdAt: TimeInterval
    }

    struct URLSessionTiming: Codable {
        struct Transaction: Codable {
            let index: Int
            let fetchDuration: TimeInterval?
            let dnsDuration: TimeInterval?
            let connectDuration: TimeInterval?
            let secureConnectDuration: TimeInterval?
            let requestDuration: TimeInterval?
            let serverWaitDuration: TimeInterval?
            let responseTransferDuration: TimeInterval?
            let networkProtocolName: String?
            let reusedConnection: Bool
            let proxyConnection: Bool
            let resourceFetchType: String
        }

        let schemaVersion: Int
        let taskDuration: TimeInterval?
        let redirectCount: Int
        let reportedTransactionCount: Int
        let omittedTransactionCount: Int
        let transactions: [Transaction]
    }

    struct WebSocketMessage: Codable {
        // MARK: Lifecycle

        init(
            id: String,
            createdAt: TimeInterval,
            messageType: MessageType,
            stringValue: String?,
            dataValue: Data?,
            closeCode: Int? = nil,
            closeReason: String? = nil,
            closeOrigin: String? = nil,
            abnormal: Bool? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.messageType = messageType
            self.stringValue = stringValue
            self.dataValue = dataValue
            self.closeCode = closeCode
            self.closeReason = closeReason
            self.closeOrigin = closeOrigin
            self.abnormal = abnormal
        }

        // MARK: Internal

        /// `ping`, `pong`, and `receiveCloseMessage` come from newer SDKs that tell the control
        /// frames apart; older SDKs send `pingPong`. Unknown values decode as `.unknown`.
        enum MessageType: String, Codable {
            case pingPong
            case ping
            case pong
            case send
            case receive
            case sendCloseMessage
            case receiveCloseMessage
            case abnormalTermination
            case unknown

            // MARK: Lifecycle

            init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = MessageType(rawValue: raw) ?? .unknown
            }
        }

        let id: String
        let createdAt: TimeInterval
        let messageType: MessageType
        let stringValue: String?
        let dataValue: Data?
        /// Close frame status code and reason, sent by SDKs that report them separately.
        let closeCode: Int?
        let closeReason: String?
        let closeOrigin: String?
        let abnormal: Bool?
    }

    struct GRPCCapture: Codable {
        enum CallType: String, Codable { case unary, clientStreaming, serverStreaming, bidirectionalStreaming }
        enum Direction: String, Codable { case request, response }
        struct Message: Codable {
            let sequence: Int
            let direction: Direction
            let data: Data?
            let observedBytes: Int
            let omitted: Bool
            let compressed: Bool
            let timestamp: TimeInterval
        }

        let schemaVersion: Int
        let endpoint: String
        let authority: String?
        let service: String
        let method: String
        let callType: CallType
        let requestMetadata: [Header]
        let responseMetadata: [Header]
        let trailers: [Header]
        let statusCode: Int?
        let statusMessage: String?
        let requestCompression: String?
        let responseCompression: String?
        let messages: [Message]
    }

    let id: String
    let startAt: TimeInterval
    let request: Request
    let response: Response?
    let error: CapturedError?
    let responseBodyData: Data
    let endAt: TimeInterval?
    let packageType: PackageType
    let correlationContext: CorrelationContext?
    let urlSessionTiming: URLSessionTiming?
    let websocketMessagePackage: WebSocketMessage?
    let grpcCapture: GRPCCapture?
    var requestBodyOmission: BodyOmission?
    var responseBodyOmission: BodyOmission?
}

// MARK: - BabylonRuntimePackageDTO

struct BabylonRuntimePackageDTO: Codable {
    enum Kind: String, Codable {
        case sessionStarted
        case sessionFinished
        case traceStarted
        case stepStarted
        case stepFinished
        case traceFinished
        case mark
        case event
        case error
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case sessionID = "session_id"
        case traceID = "trace_id"
        case stepID = "step_id"
        case parentStepID = "parent_step_id"
        case name
        case createdAt = "created_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case duration
        case metadata
        case error
    }

    let id: String
    let kind: Kind
    let sessionID: String
    let traceID: String?
    let stepID: String?
    let parentStepID: String?
    let name: String
    let createdAt: TimeInterval
    let startedAt: TimeInterval?
    let endedAt: TimeInterval?
    let duration: TimeInterval?
    let metadata: [String: String]
    let error: BabylonTrafficPackageDTO.CapturedError?
}

// MARK: - BabylonCaptureIdentity

struct BabylonCaptureIdentity: Equatable {
    let clientID: String
    let sessionID: String
    let projectName: String
    let bundleIdentifier: String
    let deviceName: String
    let deviceModel: String

    var displayName: String {
        "\(projectName) • \(deviceName)"
    }
}

// MARK: - BabylonCaptureMetadata

/// Bounded producer and source facts retained with a transaction. Capability values are
/// descriptive only: they never change Rockxy's own capture limits.
struct BabylonCaptureMetadata: Codable, Equatable {
    // MARK: Lifecycle

    init(
        identity: BabylonCaptureIdentity,
        capabilities: BabylonConnectionPackageDTO.Capabilities?,
        correlation: BabylonTrafficPackageDTO.CorrelationContext?,
        urlSessionTiming: BabylonTrafficPackageDTO.URLSessionTiming? = nil,
        error: BabylonTrafficPackageDTO.CapturedError?,
        compatibilityDiagnostics: [String]
    ) {
        clientID = boundedBabylonString(identity.clientID, bytes: 512)
        packageName = boundedBabylonString(identity.projectName, bytes: 120)
        bundleIdentifier = boundedBabylonString(identity.bundleIdentifier, bytes: 255)
        deviceName = boundedBabylonString(identity.deviceName, bytes: 120)
        deviceModel = boundedBabylonString(identity.deviceModel, bytes: 255)
        transportSessionID = boundedBabylonString(identity.sessionID, bytes: 128)
        runtimeSessionID = correlation.map { boundedBabylonString($0.sessionID, bytes: 128) }
        traceID = correlation.map { boundedBabylonString($0.traceID, bytes: 128) }
        stepID = correlation.map { boundedBabylonString($0.stepID, bytes: 128) }
        self.urlSessionTiming = urlSessionTiming.flatMap(BabylonURLSessionTimingMetadata.init)
        sdkVersion = capabilities.map { boundedBabylonString($0.sdkVersion, bytes: 64) }
        platform = capabilities.map { boundedBabylonString($0.platform, bytes: 64) }
        let schemas = capabilities?.payloadSchemaVersions ?? [:]
        payloadSchemaVersions = Dictionary(
            schemas.sorted(by: { $0.key < $1.key }).prefix(16)
                .map { (boundedBabylonString($0.key, bytes: 64), min(max($0.value, 0), 1_000_000)) },
            uniquingKeysWith: { first, _ in first }
        )
        supportedMessageTypes = (capabilities?.supportedMessageTypes ?? []).prefix(32).map {
            boundedBabylonString($0, bytes: 64)
        }
        supportedTrafficTypes = (capabilities?.supportedTrafficTypes ?? []).prefix(16).map {
            boundedBabylonString($0, bytes: 64)
        }
        maximumBodyBytes = capabilities.map { min(max($0.maximumBodyBytes, 0), 1_073_741_824) }
        maximumWebSocketFrameBytes = capabilities.map { min(max($0.maximumWebSocketFrameBytes, 0), 1_073_741_824) }
        maximumCaptureMemoryBytes = capabilities.map { min(max($0.maximumCaptureMemoryBytes, 0), 2_147_483_648) }
        self.compatibilityDiagnostics = compatibilityDiagnostics.prefix(16).map {
            boundedBabylonString($0, bytes: 512)
        }
        errorCode = error?.code
        errorDomain = error?.domain.map { boundedBabylonString($0, bytes: 256) }
        errorMessage = error.map { boundedBabylonString($0.message, bytes: 1_024) }
        failurePhase = error?.phase.map { boundedBabylonString($0, bytes: 64) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try boundedBabylonString(container.decodeIfPresent(String.self, forKey: .clientID) ?? "", bytes: 512)
        packageName = try boundedBabylonString(
            container.decodeIfPresent(String.self, forKey: .packageName) ?? "",
            bytes: 120
        )
        bundleIdentifier = try boundedBabylonString(
            container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? "", bytes: 255
        )
        deviceName = try boundedBabylonString(
            container.decodeIfPresent(String.self, forKey: .deviceName) ?? "",
            bytes: 120
        )
        deviceModel = try boundedBabylonString(
            container.decodeIfPresent(String.self, forKey: .deviceModel) ?? "",
            bytes: 255
        )
        transportSessionID = try boundedBabylonString(
            container.decodeIfPresent(String.self, forKey: .transportSessionID) ?? "", bytes: 128
        )
        runtimeSessionID = try container.decodeIfPresent(String.self, forKey: .runtimeSessionID)
            .map { boundedBabylonString($0, bytes: 128) }
        traceID = try container.decodeIfPresent(String.self, forKey: .traceID)
            .map { boundedBabylonString($0, bytes: 128) }
        stepID = try container.decodeIfPresent(String.self, forKey: .stepID)
            .map { boundedBabylonString($0, bytes: 128) }
        urlSessionTiming = try container.decodeIfPresent(
            BabylonURLSessionTimingMetadata.self,
            forKey: .urlSessionTiming
        )
        sdkVersion = try container.decodeIfPresent(String.self, forKey: .sdkVersion)
            .map { boundedBabylonString($0, bytes: 64) }
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
            .map { boundedBabylonString($0, bytes: 64) }
        let schemas = try container.decodeIfPresent([String: Int].self, forKey: .payloadSchemaVersions) ?? [:]
        payloadSchemaVersions = Dictionary(
            schemas.sorted(by: { $0.key < $1.key }).prefix(16)
                .map { (boundedBabylonString($0.key, bytes: 64), min(max($0.value, 0), 1_000_000)) },
            uniquingKeysWith: { first, _ in first }
        )
        supportedMessageTypes = try (container.decodeIfPresent([String].self, forKey: .supportedMessageTypes) ?? [])
            .prefix(32).map { boundedBabylonString($0, bytes: 64) }
        supportedTrafficTypes = try (container.decodeIfPresent([String].self, forKey: .supportedTrafficTypes) ?? [])
            .prefix(16).map { boundedBabylonString($0, bytes: 64) }
        maximumBodyBytes = try container.decodeIfPresent(Int.self, forKey: .maximumBodyBytes)
            .map { min(max($0, 0), 1_073_741_824) }
        maximumWebSocketFrameBytes = try container.decodeIfPresent(Int.self, forKey: .maximumWebSocketFrameBytes)
            .map { min(max($0, 0), 1_073_741_824) }
        maximumCaptureMemoryBytes = try container.decodeIfPresent(Int.self, forKey: .maximumCaptureMemoryBytes)
            .map { min(max($0, 0), 2_147_483_648) }
        compatibilityDiagnostics = try (container
            .decodeIfPresent([String].self, forKey: .compatibilityDiagnostics) ?? [])
            .prefix(16).map { boundedBabylonString($0, bytes: 512) }
        errorCode = try container.decodeIfPresent(Int.self, forKey: .errorCode)
        errorDomain = try container.decodeIfPresent(String.self, forKey: .errorDomain)
            .map { boundedBabylonString($0, bytes: 256) }
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
            .map { boundedBabylonString($0, bytes: 1_024) }
        failurePhase = try container.decodeIfPresent(String.self, forKey: .failurePhase)
            .map { boundedBabylonString($0, bytes: 64) }
    }

    // MARK: Internal

    let clientID: String
    let packageName: String
    let bundleIdentifier: String
    let deviceName: String
    let deviceModel: String
    let transportSessionID: String
    let runtimeSessionID: String?
    let traceID: String?
    let stepID: String?
    let urlSessionTiming: BabylonURLSessionTimingMetadata?
    let sdkVersion: String?
    let platform: String?
    let payloadSchemaVersions: [String: Int]
    let supportedMessageTypes: [String]
    let supportedTrafficTypes: [String]
    let maximumBodyBytes: Int?
    let maximumWebSocketFrameBytes: Int?
    let maximumCaptureMemoryBytes: Int?
    let compatibilityDiagnostics: [String]
    let errorCode: Int?
    let errorDomain: String?
    let errorMessage: String?
    let failurePhase: String?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case clientID
        case packageName
        case bundleIdentifier
        case deviceName
        case deviceModel
        case transportSessionID
        case runtimeSessionID
        case traceID
        case stepID
        case urlSessionTiming
        case sdkVersion
        case platform
        case payloadSchemaVersions
        case supportedMessageTypes
        case supportedTrafficTypes
        case maximumBodyBytes
        case maximumWebSocketFrameBytes
        case maximumCaptureMemoryBytes
        case compatibilityDiagnostics
        case errorCode
        case errorDomain
        case errorMessage
        case failurePhase
    }
}

// MARK: - BabylonURLSessionTimingMetadata

/// A bounded, versioned copy of producer-observed URLSession phases. Missing phases stay nil.
struct BabylonURLSessionTimingMetadata: Codable, Equatable {
    // MARK: Lifecycle

    init?(_ value: BabylonTrafficPackageDTO.URLSessionTiming) {
        guard value.schemaVersion == 1 else {
            return nil
        }
        schemaVersion = value.schemaVersion
        taskDuration = boundedBabylonDuration(value.taskDuration)
        redirectCount = min(max(value.redirectCount, 0), 1_000_000)
        reportedTransactionCount = min(max(value.reportedTransactionCount, 0), 1_000_000)
        omittedTransactionCount = min(max(value.omittedTransactionCount, 0), 1_000_000)
        transactions = value.transactions.prefix(16).map(Transaction.init)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try min(max(container.decode(Int.self, forKey: .schemaVersion), 0), 1_000_000)
        taskDuration = try boundedBabylonDuration(container.decodeIfPresent(Double.self, forKey: .taskDuration))
        redirectCount = try min(max(container.decode(Int.self, forKey: .redirectCount), 0), 1_000_000)
        reportedTransactionCount = try min(
            max(container.decode(Int.self, forKey: .reportedTransactionCount), 0),
            1_000_000
        )
        omittedTransactionCount = try min(
            max(container.decode(Int.self, forKey: .omittedTransactionCount), 0),
            1_000_000
        )
        transactions = try container.decodeIfPresent([Transaction].self, forKey: .transactions)?.prefix(16)
            .map { $0 } ?? []
    }

    // MARK: Internal

    struct Transaction: Codable, Equatable {
        // MARK: Lifecycle

        init(_ value: BabylonTrafficPackageDTO.URLSessionTiming.Transaction) {
            index = min(max(value.index, 0), 1_000_000)
            fetchDuration = boundedBabylonDuration(value.fetchDuration)
            dnsDuration = boundedBabylonDuration(value.dnsDuration)
            connectDuration = boundedBabylonDuration(value.connectDuration)
            secureConnectDuration = boundedBabylonDuration(value.secureConnectDuration)
            requestDuration = boundedBabylonDuration(value.requestDuration)
            serverWaitDuration = boundedBabylonDuration(value.serverWaitDuration)
            responseTransferDuration = boundedBabylonDuration(value.responseTransferDuration)
            networkProtocolName = value.networkProtocolName.map { boundedBabylonString($0, bytes: 64) }
            reusedConnection = value.reusedConnection
            proxyConnection = value.proxyConnection
            resourceFetchType = boundedBabylonString(value.resourceFetchType, bytes: 64)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            index = try min(max(container.decode(Int.self, forKey: .index), 0), 1_000_000)
            fetchDuration = try boundedBabylonDuration(container.decodeIfPresent(Double.self, forKey: .fetchDuration))
            dnsDuration = try boundedBabylonDuration(container.decodeIfPresent(Double.self, forKey: .dnsDuration))
            connectDuration = try boundedBabylonDuration(container.decodeIfPresent(
                Double.self,
                forKey: .connectDuration
            ))
            secureConnectDuration = try boundedBabylonDuration(
                container.decodeIfPresent(Double.self, forKey: .secureConnectDuration)
            )
            requestDuration = try boundedBabylonDuration(
                container.decodeIfPresent(Double.self, forKey: .requestDuration)
            )
            serverWaitDuration = try boundedBabylonDuration(
                container.decodeIfPresent(Double.self, forKey: .serverWaitDuration)
            )
            responseTransferDuration = try boundedBabylonDuration(
                container.decodeIfPresent(Double.self, forKey: .responseTransferDuration)
            )
            networkProtocolName = try container.decodeIfPresent(String.self, forKey: .networkProtocolName)
                .map { boundedBabylonString($0, bytes: 64) }
            reusedConnection = try container.decode(Bool.self, forKey: .reusedConnection)
            proxyConnection = try container.decode(Bool.self, forKey: .proxyConnection)
            resourceFetchType = try boundedBabylonString(
                container.decode(String.self, forKey: .resourceFetchType), bytes: 64
            )
        }

        // MARK: Internal

        let index: Int
        let fetchDuration: TimeInterval?
        let dnsDuration: TimeInterval?
        let connectDuration: TimeInterval?
        let secureConnectDuration: TimeInterval?
        let requestDuration: TimeInterval?
        let serverWaitDuration: TimeInterval?
        let responseTransferDuration: TimeInterval?
        let networkProtocolName: String?
        let reusedConnection: Bool
        let proxyConnection: Bool
        let resourceFetchType: String

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case index
            case fetchDuration
            case dnsDuration
            case connectDuration
            case secureConnectDuration
            case requestDuration
            case serverWaitDuration
            case responseTransferDuration
            case networkProtocolName
            case reusedConnection
            case proxyConnection
            case resourceFetchType
        }
    }

    let schemaVersion: Int
    let taskDuration: TimeInterval?
    let redirectCount: Int
    let reportedTransactionCount: Int
    let omittedTransactionCount: Int
    let transactions: [Transaction]

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case taskDuration
        case redirectCount
        case reportedTransactionCount
        case omittedTransactionCount
        case transactions
    }
}

// MARK: - BabylonCaptureMappingError

enum BabylonCaptureMappingError: LocalizedError {
    case invalidURL
    case unsupportedScheme
    case invalidMethod
    case invalidStatusCode
    case oversizedBody
    case missingWebSocketMessage
    case unsupportedPackage

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The Babylon request URL is invalid."
        case .unsupportedScheme: "The Babylon request URL scheme is unsupported."
        case .invalidMethod: "The Babylon request method is invalid."
        case .invalidStatusCode: "The Babylon response status code is invalid."
        case .oversizedBody: "The Babylon body exceeds the capture limit."
        case .missingWebSocketMessage: "The Babylon WebSocket package has no frame."
        case .unsupportedPackage: "The Babylon package type is not supported by this Rockxy version."
        }
    }
}
