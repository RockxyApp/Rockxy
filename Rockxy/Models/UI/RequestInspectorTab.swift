import Foundation

/// Tabs for the request half of the split inspector panel.
enum RequestInspectorTab: String, CaseIterable {
    case headers
    case query
    case body
    case multipart
    case protobuf
    case cookies
    case raw
    case synopsis
    case comments

    // MARK: Internal

    var displayName: String {
        switch self {
        case .headers: String(localized: "Headers", bundle: RockxyLocalization.bundle)
        case .query: String(localized: "Query", bundle: RockxyLocalization.bundle)
        case .body: String(localized: "Body", bundle: RockxyLocalization.bundle)
        case .multipart: String(localized: "Multipart", bundle: RockxyLocalization.bundle)
        case .protobuf: "Protobuf"
        case .cookies: String(localized: "Cookies", bundle: RockxyLocalization.bundle)
        case .raw: String(localized: "Raw", bundle: RockxyLocalization.bundle)
        case .synopsis: String(localized: "Synopsis", bundle: RockxyLocalization.bundle)
        case .comments: String(localized: "Notes", bundle: RockxyLocalization.bundle)
        }
    }
}
