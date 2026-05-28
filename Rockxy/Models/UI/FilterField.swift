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

    // MARK: Internal

    var displayName: String {
        switch self {
        case .url: "URL"
        case .contains: "Contains"
        case .host: "Host"
        case .domain: "Domain"
        case .path: "Path"
        case .method: "Method"
        case .statusCode: "Status Code"
        case .requestHeader: "Request Header"
        case .responseHeader: "Response Header"
        case .requestBody: "Request Body"
        case .responseBody: "Response Body"
        case .queryString: "Query String"
        case .cookies: "Cookies"
        case .clientApp: "Client/App"
        case .contentType: "Content Type"
        case .comment: "Comment"
        case .color: "Color"
        }
    }
}
