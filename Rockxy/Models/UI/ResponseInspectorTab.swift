import Foundation

/// Tabs for the response half of the split inspector panel.
enum ResponseInspectorTab: String, CaseIterable {
    case ai
    case headers
    case body
    case events
    case protobuf
    case multipart
    case script
    case setCookie
    case auth
    case timeline

    // MARK: Internal

    /// The Events and Protobuf tabs are conditional: pass `includesEvents` for
    /// text/event-stream responses and `includesProtobuf` for decodable Protobuf bodies.
    static func availableTabs(
        includesEvents: Bool = false,
        includesProtobuf: Bool = false,
        includesMultipart: Bool = false,
        includesScript: Bool = false
    ) -> [ResponseInspectorTab] {
        allCases.filter { tab in
            tab != .ai && (tab != .events || includesEvents) && (tab != .protobuf || includesProtobuf)
                && (tab != .multipart || includesMultipart) && (tab != .script || includesScript)
        }
    }

    var displayName: String {
        switch self {
        // "AI" is a product/acronym token; "Set-Cookie" is an HTTP header name — both verbatim.
        case .ai: "AI"
        case .headers: String(localized: "Headers", bundle: RockxyLocalization.bundle)
        case .body: String(localized: "Body", bundle: RockxyLocalization.bundle)
        case .events: String(localized: "Events", bundle: RockxyLocalization.bundle)
        case .protobuf: "Protobuf"
        case .multipart: String(localized: "Multipart", bundle: RockxyLocalization.bundle)
        case .script: String(localized: "Script", bundle: RockxyLocalization.bundle)
        case .setCookie: "Set-Cookie"
        case .auth: String(localized: "Auth", bundle: RockxyLocalization.bundle)
        case .timeline: String(localized: "Timeline", bundle: RockxyLocalization.bundle)
        }
    }
}
