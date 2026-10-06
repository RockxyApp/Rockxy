import SwiftUI

// MARK: - MapLocalHTTPMethod

enum MapLocalHTTPMethod: String, CaseIterable, Identifiable {
    case any = "ANY"
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"
    case query = "QUERY"

    // MARK: Lifecycle

    init(ruleMethod: String?) {
        guard let ruleMethod,
              let method = Self(rawValue: ruleMethod.uppercased()) else
        {
            self = .any
            return
        }
        self = method
    }

    // MARK: Internal

    var id: String {
        rawValue
    }

    var ruleValue: String? {
        self == .any ? nil : rawValue
    }
}

// MARK: - MapLocalMatchType

enum MapLocalMatchType: String, CaseIterable, Identifiable {
    case wildcard
    case regex

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .wildcard: "Use Wildcard"
        case .regex: "Use Regex"
        }
    }
}

// MARK: - MapLocalRuleTestResult

enum MapLocalRuleTestResult: Equatable {
    case matched
    case notMatched
    case invalidURL
    case invalidPattern(String)
}

// MARK: - MapLocalTargetMode

enum MapLocalTargetMode: String, CaseIterable, Identifiable {
    case localFile
    case localDirectory

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .localFile: "Local File"
        case .localDirectory: "Local Directory"
        }
    }
}

// MARK: - MapLocalDelayPreset

enum MapLocalDelayPreset: String, CaseIterable, Identifiable {
    case none
    case oneSecond
    case twoSeconds
    case threeSeconds
    case fiveSeconds
    case tenSeconds
    case thirtySeconds
    case sixtySeconds
    case random
    case custom

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .none: "No Delay"
        case .oneSecond: "1 second"
        case .twoSeconds: "2 seconds"
        case .threeSeconds: "3 seconds"
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        case .thirtySeconds: "30 seconds"
        case .sixtySeconds: "60 seconds"
        case .random: "Random (1-15s)"
        case .custom: "Custom"
        }
    }

    var delayMs: Int {
        switch self {
        case .none: 0
        case .oneSecond: 1_000
        case .twoSeconds: 2_000
        case .threeSeconds: 3_000
        case .fiveSeconds: 5_000
        case .tenSeconds: 10_000
        case .thirtySeconds: 30_000
        case .sixtySeconds: 60_000
        case .random: -1
        case .custom: 0
        }
    }

    static func from(delayMs: Int) -> Self {
        switch delayMs {
        case 0: .none
        case 1_000: .oneSecond
        case 2_000: .twoSeconds
        case 3_000: .threeSeconds
        case 5_000: .fiveSeconds
        case 10_000: .tenSeconds
        case 30_000: .thirtySeconds
        case 60_000: .sixtySeconds
        case -1: .random
        default: .custom
        }
    }
}

// MARK: - MapLocalEditorContext

struct MapLocalEditorContext {
    static let blank = MapLocalEditorContext()

    var existingRule: ProxyRule?
    var draft: MapLocalDraft?
}

// MARK: - MapLocalEditorStore

@MainActor @Observable
final class MapLocalEditorStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = MapLocalEditorStore()

    private(set) var context = MapLocalEditorContext.blank
    var draftVersion: UInt64 = 0

    func openNew(draft: MapLocalDraft? = nil) {
        context = MapLocalEditorContext(existingRule: nil, draft: draft)
        draftVersion &+= 1
    }

    func openExisting(_ rule: ProxyRule) {
        context = MapLocalEditorContext(existingRule: rule, draft: nil)
        draftVersion &+= 1
    }
}
