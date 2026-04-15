import Foundation

/// Defines the criteria a request must satisfy for a `ProxyRule` to fire.
/// All non-nil fields must match (AND logic). URL patterns use regex matching.
struct RuleMatchCondition: Codable, Equatable {
    var urlPattern: String?
    var method: String?
    var headerName: String?
    var headerValue: String?

    func matches(
        method requestMethod: String,
        url: URL,
        headers: [HTTPHeader],
        compiledPattern: NSRegularExpression? = nil
    )
        -> Bool
    {
        if let regex = compiledPattern {
            let urlString = String(url.absoluteString.prefix(ProxyLimits.maxURILength))
            let range = NSRange(urlString.startIndex..., in: urlString)
            guard regex.firstMatch(in: urlString, range: range) != nil else {
                return false
            }
        } else if let pattern = urlPattern {
            let urlString = String(url.absoluteString.prefix(ProxyLimits.maxURILength))
            guard urlString.range(of: pattern, options: .regularExpression) != nil else {
                return false
            }
        }
        if let requiredMethod = method {
            guard requestMethod.uppercased() == requiredMethod.uppercased() else {
                return false
            }
        }
        if let name = headerName, let value = headerValue {
            guard headers.contains(where: { $0.name.lowercased() == name.lowercased() && $0.value == value }) else {
                return false
            }
        }
        return true
    }
}
