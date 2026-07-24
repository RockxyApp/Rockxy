import Foundation

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

    let device: Device
    let project: Project
    let icon: Data?
}

// MARK: - BabylonTrafficPackageDTO

struct BabylonTrafficPackageDTO: Codable {
    enum PackageType: String, Codable {
        case http
        case websocket
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
        let code: Int
        let message: String
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

    struct WebSocketMessage: Codable {
        enum MessageType: String, Codable {
            case pingPong
            case send
            case receive
            case sendCloseMessage
        }

        let id: String
        let createdAt: TimeInterval
        let messageType: MessageType
        let stringValue: String?
        let dataValue: Data?
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
    let websocketMessagePackage: WebSocketMessage?
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

// MARK: - BabylonCaptureMappingError

enum BabylonCaptureMappingError: LocalizedError {
    case invalidURL
    case unsupportedScheme
    case invalidMethod
    case invalidStatusCode
    case oversizedBody
    case missingWebSocketMessage

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The Babylon request URL is invalid."
        case .unsupportedScheme: "The Babylon request URL scheme is unsupported."
        case .invalidMethod: "The Babylon request method is invalid."
        case .invalidStatusCode: "The Babylon response status code is invalid."
        case .oversizedBody: "The Babylon body exceeds the capture limit."
        case .missingWebSocketMessage: "The Babylon WebSocket package has no frame."
        }
    }
}
