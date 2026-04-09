import Foundation

// Defines `RuleAction`, the model for rule used by rule editing and evaluation.

// MARK: - BreakpointRulePhase

enum BreakpointRulePhase: String, Codable {
    case request
    case response
    case both
}

// MARK: - HeaderModifyPhase

/// The phase at which a header modification is applied.
enum HeaderModifyPhase: String, Codable, CaseIterable {
    case request
    case response
    case both
}

// MARK: - RuleAction

/// The action to perform when a `ProxyRule` matches a request.
enum RuleAction {
    case breakpoint(phase: BreakpointRulePhase = .both)
    case mapLocal(filePath: String, statusCode: Int = 200, isDirectory: Bool = false)
    case mapRemote(configuration: MapRemoteConfiguration)
    case block(statusCode: Int)
    case throttle(delayMs: Int)
    case modifyHeader(operations: [HeaderOperation])
    case networkCondition(preset: NetworkConditionPreset, delayMs: Int)
}

extension RuleAction {
    var matchedRuleActionSummary: String {
        switch self {
        case let .breakpoint(phase):
            "Breakpoint (\(phase.rawValue.capitalized))"
        case let .mapLocal(filePath, _, isDirectory):
            isDirectory ? "Map Local Directory" : "Map Local (\((filePath as NSString).lastPathComponent))"
        case .mapRemote:
            "Map Remote"
        case let .block(statusCode):
            statusCode == 0 ? "Drop Connection" : "Block (\(statusCode))"
        case let .throttle(delayMs):
            "Throttle (\(delayMs) ms)"
        case let .modifyHeader(operations):
            "Modify Headers (\(operations.count))"
        case let .networkCondition(preset, delayMs):
            "Network Condition (\(preset.displayName), \(delayMs) ms)"
        }
    }
}

// MARK: Codable

extension RuleAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case filePath
        case statusCode
        case isDirectory
        case url
        case configuration
        case delayMs
        case operation
        case operations
        case phase
        case preset
    }

    private enum ActionType: String, Codable {
        case breakpoint
        case mapLocal
        case mapRemote
        case block
        case throttle
        case modifyHeader
        case networkCondition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)

        switch type {
        case .breakpoint:
            let phase = try container.decodeIfPresent(BreakpointRulePhase.self, forKey: .phase) ?? .both
            self = .breakpoint(phase: phase)
        case .mapLocal:
            let filePath = try container.decode(String.self, forKey: .filePath)
            let statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode) ?? 200
            let isDirectory = try container.decodeIfPresent(Bool.self, forKey: .isDirectory) ?? false
            self = .mapLocal(filePath: filePath, statusCode: statusCode, isDirectory: isDirectory)
        case .mapRemote:
            if let config = try container.decodeIfPresent(MapRemoteConfiguration.self, forKey: .configuration) {
                self = .mapRemote(configuration: config)
            } else if let url = try container.decodeIfPresent(String.self, forKey: .url) {
                self = .mapRemote(configuration: MapRemoteConfiguration(fromLegacyURL: url))
            } else {
                self = .mapRemote(configuration: MapRemoteConfiguration())
            }
        case .block:
            let statusCode = try container.decode(Int.self, forKey: .statusCode)
            self = .block(statusCode: statusCode)
        case .throttle:
            let delayMs = try container.decode(Int.self, forKey: .delayMs)
            self = .throttle(delayMs: delayMs)
        case .modifyHeader:
            if let operations = try container.decodeIfPresent([HeaderOperation].self, forKey: .operations) {
                self = .modifyHeader(operations: operations)
            } else if let operation = try container.decodeIfPresent(HeaderOperation.self, forKey: .operation) {
                self = .modifyHeader(operations: [operation])
            } else {
                self = .modifyHeader(operations: [])
            }
        case .networkCondition:
            let preset = try container.decode(NetworkConditionPreset.self, forKey: .preset)
            let delayMs = try container.decode(Int.self, forKey: .delayMs)
            self = .networkCondition(preset: preset, delayMs: delayMs)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .breakpoint(phase):
            try container.encode(ActionType.breakpoint, forKey: .type)
            try container.encode(phase, forKey: .phase)
        case let .mapLocal(filePath, statusCode, isDirectory):
            try container.encode(ActionType.mapLocal, forKey: .type)
            try container.encode(filePath, forKey: .filePath)
            try container.encode(statusCode, forKey: .statusCode)
            if isDirectory {
                try container.encode(isDirectory, forKey: .isDirectory)
            }
        case let .mapRemote(configuration):
            try container.encode(ActionType.mapRemote, forKey: .type)
            try container.encode(configuration, forKey: .configuration)
        case let .block(statusCode):
            try container.encode(ActionType.block, forKey: .type)
            try container.encode(statusCode, forKey: .statusCode)
        case let .throttle(delayMs):
            try container.encode(ActionType.throttle, forKey: .type)
            try container.encode(delayMs, forKey: .delayMs)
        case let .modifyHeader(operations):
            try container.encode(ActionType.modifyHeader, forKey: .type)
            try container.encode(operations, forKey: .operations)
        case let .networkCondition(preset, delayMs):
            try container.encode(ActionType.networkCondition, forKey: .type)
            try container.encode(preset, forKey: .preset)
            try container.encode(delayMs, forKey: .delayMs)
        }
    }
}

// MARK: - HeaderOperation

/// Describes a single header modification (add, remove, or replace) applied by a rule.
struct HeaderOperation: Codable {
    // MARK: Lifecycle

    init(
        type: HeaderOperationType,
        headerName: String,
        headerValue: String?,
        phase: HeaderModifyPhase = .request
    ) {
        self.type = type
        self.headerName = headerName
        self.headerValue = headerValue
        self.phase = phase
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(HeaderOperationType.self, forKey: .type)
        headerName = try container.decode(String.self, forKey: .headerName)
        headerValue = try container.decodeIfPresent(String.self, forKey: .headerValue)
        phase = try container.decodeIfPresent(HeaderModifyPhase.self, forKey: .phase) ?? .request
    }

    // MARK: Internal

    let type: HeaderOperationType
    let headerName: String
    let headerValue: String?
    let phase: HeaderModifyPhase
}

// MARK: - HeaderOperation + Phase Filtering

extension HeaderOperation {
    static func requestPhase(from operations: [HeaderOperation]) -> [HeaderOperation] {
        operations.filter { $0.phase == .request || $0.phase == .both }
    }

    static func responsePhase(from operations: [HeaderOperation]) -> [HeaderOperation] {
        operations.filter { $0.phase == .response || $0.phase == .both }
    }
}

// MARK: - HeaderOperationType

/// The type of modification to apply to an HTTP header.
enum HeaderOperationType: String, Codable, CaseIterable {
    case add
    case remove
    case replace
}
