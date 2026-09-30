import Foundation

/// Shared preset definitions for Modify Header rules.
/// Used by both RuleListView (Presets menu) and ModifyHeaderWindowView (bottom bar Presets menu).
enum HeaderModifyPresets {
    /// Response headers a browser needs to accept a cross-origin response and to pass an
    /// `OPTIONS` preflight. Each header is replaced, not appended, so an origin that already
    /// sends CORS headers never ends up with two conflicting values.
    static let corsResponseHeaders: [(name: String, value: String)] = [
        ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS"),
        ("Access-Control-Allow-Headers", "*"),
        ("Access-Control-Max-Age", "600"),
    ]

    static func corsHeaders() -> ProxyRule {
        ProxyRule(
            name: "Add CORS Headers",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .modifyHeader(operations: corsResponseHeaders.map {
                HeaderOperation(type: .replace, headerName: $0.name, headerValue: $0.value, phase: .response)
            })
        )
    }

    static func removeAuthorization() -> ProxyRule {
        ProxyRule(
            name: "Remove Authorization",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .modifyHeader(operations: [HeaderOperation(
                type: .remove,
                headerName: "Authorization",
                headerValue: nil,
                phase: .request
            )])
        )
    }

    static func stripServerHeader() -> ProxyRule {
        ProxyRule(
            name: "Strip Server Header",
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .modifyHeader(operations: [HeaderOperation(
                type: .remove,
                headerName: "Server",
                headerValue: nil,
                phase: .response
            )])
        )
    }
}
