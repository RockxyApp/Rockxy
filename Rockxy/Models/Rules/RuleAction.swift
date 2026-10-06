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
    case mapLocal(
        filePath: String,
        statusCode: Int = 200,
        isDirectory: Bool = false,
        delayMs: Int = 0,
        responseHeaders: [HTTPHeader] = []
    )
    case mapRemote(configuration: MapRemoteConfiguration)
    case block(statusCode: Int)
    case throttle(delayMs: Int)
    case modifyHeader(operations: [HeaderOperation])
    /// `custom` carries bandwidth and loss for the Custom preset; presets ignore it.
    case networkCondition(preset: NetworkConditionPreset, delayMs: Int, custom: NetworkCustomProfile? = nil)
}

extension RuleAction {
    var responseBreakpointPhase: BreakpointRulePhase? {
        guard case let .breakpoint(phase) = self,
              phase == .response || phase == .both else
        {
            return nil
        }
        return phase
    }

    var toolCategory: String {
        switch self {
        case .breakpoint: "breakpoint"
        case .mapLocal: "mapLocal"
        case .mapRemote: "mapRemote"
        case .block: "block"
        case .throttle: "throttle"
        case .modifyHeader: "modifyHeader"
        case .networkCondition: "networkCondition"
        }
    }

    var matchedRuleActionSummary: String {
        switch self {
        case let .breakpoint(phase):
            "Breakpoint (\(phase.rawValue.capitalized))"
        case let .mapLocal(filePath, _, isDirectory, _, _):
            isDirectory ? "Map Local Directory" : "Map Local (\((filePath as NSString).lastPathComponent))"
        case .mapRemote:
            "Map Remote"
        case let .block(statusCode):
            statusCode == 0 ? "Drop Connection" : "Block (\(statusCode))"
        case let .throttle(delayMs):
            "Throttle (\(delayMs) ms)"
        case let .modifyHeader(operations):
            "Modify Headers (\(operations.count))"
        case let .networkCondition(preset, delayMs, _):
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
        case responseHeaders
        case downloadKbps
        case uploadKbps
        case packetLossPercent
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
            let delayMs = try container.decodeIfPresent(Int.self, forKey: .delayMs) ?? 0
            let responseHeaders = try container
                .decodeIfPresent([HTTPHeader].self, forKey: .responseHeaders) ?? []
            self = .mapLocal(
                filePath: filePath,
                statusCode: statusCode,
                isDirectory: isDirectory,
                delayMs: delayMs,
                responseHeaders: responseHeaders
            )
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
            let downloadKbps = try container.decodeIfPresent(Int.self, forKey: .downloadKbps)
            let uploadKbps = try container.decodeIfPresent(Int.self, forKey: .uploadKbps)
            let packetLossPercent = try container.decodeIfPresent(Double.self, forKey: .packetLossPercent)
            let custom = NetworkCustomProfile(
                downloadKbps: downloadKbps,
                uploadKbps: uploadKbps,
                packetLossPercent: packetLossPercent ?? 0
            )
            self = .networkCondition(
                preset: preset,
                delayMs: delayMs,
                custom: preset == .custom && !custom.isUnlimited ? custom : nil
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .breakpoint(phase):
            try container.encode(ActionType.breakpoint, forKey: .type)
            try container.encode(phase, forKey: .phase)
        case let .mapLocal(filePath, statusCode, isDirectory, delayMs, responseHeaders):
            try container.encode(ActionType.mapLocal, forKey: .type)
            try container.encode(filePath, forKey: .filePath)
            try container.encode(statusCode, forKey: .statusCode)
            if isDirectory {
                try container.encode(isDirectory, forKey: .isDirectory)
            }
            // Encode any non-zero delay so the random-delay sentinel (-1) survives the
            // round-trip. Zero stays omitted for backward compatibility with older rules.
            if delayMs != 0 {
                try container.encode(delayMs, forKey: .delayMs)
            }
            // Omit an empty header list so pre-existing rules stay byte-identical after a
            // load/save cycle and older builds keep decoding these rules unchanged.
            if !responseHeaders.isEmpty {
                try container.encode(responseHeaders, forKey: .responseHeaders)
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
        case let .networkCondition(preset, delayMs, custom):
            try container.encode(ActionType.networkCondition, forKey: .type)
            try container.encode(preset, forKey: .preset)
            try container.encode(delayMs, forKey: .delayMs)
            // Unlimited or preset profiles stay byte-identical to rules saved before
            // custom limits existed; older builds ignore the extra keys.
            if preset == .custom, let custom, !custom.isUnlimited {
                try container.encodeIfPresent(custom.effectiveDownloadKbps, forKey: .downloadKbps)
                try container.encodeIfPresent(custom.effectiveUploadKbps, forKey: .uploadKbps)
                if custom.packetLossRate > 0 {
                    try container.encode(custom.packetLossPercent, forKey: .packetLossPercent)
                }
            }
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
