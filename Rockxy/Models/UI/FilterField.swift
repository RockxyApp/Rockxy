import Foundation

/// The request property that a search filter targets in the traffic list toolbar.
enum FilterField: String, CaseIterable, Codable, Hashable {
    case url
    case contains
    case host
    case domain
    case path
    case method
    case statusCode
    case requestHeader
    case responseHeader
    case requestBody
    case responseBody
    case queryString
    case cookies
    case clientApp
    case contentType
    case comment
    case color
    case graphQLOperation
    case all

    // MARK: Internal

    var displayName: String {
        switch self {
        case .url: "URL"
        case .contains: String(localized: "Contains", bundle: RockxyLocalization.bundle)
        case .host: String(localized: "Host", bundle: RockxyLocalization.bundle)
        case .domain: String(localized: "Domain", bundle: RockxyLocalization.bundle)
        case .path: String(localized: "Path", bundle: RockxyLocalization.bundle)
        case .method: String(localized: "Method", bundle: RockxyLocalization.bundle)
        case .statusCode: String(localized: "Status Code", bundle: RockxyLocalization.bundle)
        case .requestHeader: String(localized: "Request Header", bundle: RockxyLocalization.bundle)
        case .responseHeader: String(localized: "Response Header", bundle: RockxyLocalization.bundle)
        case .requestBody: String(localized: "Request Body", bundle: RockxyLocalization.bundle)
        case .responseBody: String(localized: "Response Body", bundle: RockxyLocalization.bundle)
        case .queryString: String(localized: "Query String", bundle: RockxyLocalization.bundle)
        case .cookies: String(localized: "Cookies", bundle: RockxyLocalization.bundle)
        case .clientApp: String(localized: "Client/App", bundle: RockxyLocalization.bundle)
        case .contentType: String(localized: "Content Type", bundle: RockxyLocalization.bundle)
        case .comment: String(localized: "Note", bundle: RockxyLocalization.bundle)
        case .color: String(localized: "Color", bundle: RockxyLocalization.bundle)
        case .graphQLOperation: String(localized: "GraphQL Operation", bundle: RockxyLocalization.bundle)
        case .all: String(localized: "All Fields", bundle: RockxyLocalization.bundle)
        }
    }
}
