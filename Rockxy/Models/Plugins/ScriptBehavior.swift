import Foundation

/// Optional per-script behavior block on `PluginManifest` describing how the
/// plugin participates in the proxy pipeline. Absence means the plugin has not
/// opted into per-script matching — see `ScriptBehavior.defaults()` for the
/// values used in that case.
struct ScriptBehavior: Codable, Equatable {
    // MARK: Lifecycle

    init(
        matchCondition: RuleMatchCondition? = nil,
        runOnRequest: Bool = true,
        runOnResponse: Bool = true,
        runAsMock: Bool = false
    ) {
        self.matchCondition = matchCondition
        self.runOnRequest = runOnRequest
        self.runOnResponse = runOnResponse
        self.runAsMock = runAsMock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.matchCondition = try container.decodeIfPresent(RuleMatchCondition.self, forKey: .matchCondition)
        self.runOnRequest = try container.decodeIfPresent(Bool.self, forKey: .runOnRequest) ?? true
        self.runOnResponse = try container.decodeIfPresent(Bool.self, forKey: .runOnResponse) ?? true
        self.runAsMock = try container.decodeIfPresent(Bool.self, forKey: .runAsMock) ?? false
    }

    // MARK: Internal

    var matchCondition: RuleMatchCondition?
    var runOnRequest: Bool
    var runOnResponse: Bool
    var runAsMock: Bool

    /// Defaults applied when a script manifest omits `scriptBehavior` entirely.
    /// Keeps historical scripts running on every request and response.
    static func defaults() -> ScriptBehavior {
        ScriptBehavior()
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case matchCondition
        case runOnRequest
        case runOnResponse
        case runAsMock
    }
}
