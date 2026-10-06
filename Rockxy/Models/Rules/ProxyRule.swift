import Foundation

/// A user-defined rule evaluated by the `RuleEngine` against each proxied request.
/// Rules are persisted as JSON and evaluated in priority order. Each rule pairs
/// a `RuleMatchCondition` (URL pattern, method, header) with a `RuleAction`
/// (block, map local/remote, breakpoint, throttle, modify header).
struct ProxyRule: Identifiable, Codable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        matchCondition: RuleMatchCondition,
        action: RuleAction,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.matchCondition = matchCondition
        self.action = action
        self.priority = priority
    }

    // MARK: Internal

    let id: UUID
    var name: String
    var isEnabled: Bool
    var matchCondition: RuleMatchCondition
    var action: RuleAction
    var priority: Int
    /// Block List only: requests this rule blocks are not added to the traffic list.
    var hidesMatchedTraffic = false
}

// MARK: Codable

extension ProxyRule {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case matchCondition
        case action
        case priority
        case hidesMatchedTraffic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        matchCondition = try container.decode(RuleMatchCondition.self, forKey: .matchCondition)
        action = try container.decode(RuleAction.self, forKey: .action)
        priority = try container.decode(Int.self, forKey: .priority)
        hidesMatchedTraffic = try container.decodeIfPresent(Bool.self, forKey: .hidesMatchedTraffic) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(matchCondition, forKey: .matchCondition)
        try container.encode(action, forKey: .action)
        try container.encode(priority, forKey: .priority)
        // Omitted when off so existing rule files stay byte-identical after a save.
        if hidesMatchedTraffic {
            try container.encode(hidesMatchedTraffic, forKey: .hidesMatchedTraffic)
        }
    }
}
