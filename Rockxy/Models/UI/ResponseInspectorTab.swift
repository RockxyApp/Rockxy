import Foundation

/// Tabs for the response half of the split inspector panel.
enum ResponseInspectorTab: String, CaseIterable {
    case ai
    case headers
    case body
    case setCookie
    case auth
    case timeline

    // MARK: Internal

    static func availableTabs(hasAIInspection: Bool) -> [ResponseInspectorTab] {
        allCases.filter { tab in
            hasAIInspection || tab != .ai
        }
    }

    var displayName: String {
        switch self {
        case .ai: "AI"
        case .headers: "Headers"
        case .body: "Body"
        case .setCookie: "Set-Cookie"
        case .auth: "Auth"
        case .timeline: "Timeline"
        }
    }
}
