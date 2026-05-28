import Foundation

enum FilterRuleEvaluator {
    static let maxTextScanBytes = 1_000_000

    static func activeRules(in rules: [FilterRule], isFilterBarVisible: Bool) -> [FilterRule] {
        guard isFilterBarVisible else {
            return []
        }
        return rules.filter { $0.isEnabled && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func matches(_ transaction: HTTPTransaction, rules: [FilterRule]) -> Bool {
        guard let first = rules.first else {
            return true
        }
        var result = matches(transaction, rule: first)
        for rule in rules.dropFirst() {
            let ruleMatches = matches(transaction, rule: rule)
            switch rule.connector {
            case .and:
                result = result && ruleMatches
            case .or:
                result = result || ruleMatches
            }
        }
        return result
    }

    static func matches(_ transaction: HTTPTransaction, rule: FilterRule) -> Bool {
        let value = fieldValue(for: rule.field, in: transaction)
        return rule.filterOperator.matches(value, against: rule.value)
    }

    static func fieldValue(for field: FilterField, in transaction: HTTPTransaction) -> String {
        switch field {
        case .url,
             .contains:
            transaction.request.url.absoluteString
        case .host,
             .domain:
            transaction.request.host
        case .path:
            transaction.request.path
        case .method:
            transaction.request.method
        case .statusCode:
            transaction.response.map { String($0.statusCode) } ?? ""
        case .requestHeader:
            joinedHeaders(transaction.request.headers)
        case .responseHeader:
            joinedHeaders(transaction.response?.headers ?? [])
        case .requestBody:
            bodyText(transaction.request.body)
        case .responseBody:
            bodyText(transaction.response?.body)
        case .queryString:
            transaction.request.url.query ?? ""
        case .cookies:
            cookieText(for: transaction)
        case .clientApp:
            transaction.clientApp ?? ""
        case .contentType:
            contentTypeText(for: transaction)
        case .comment:
            transaction.comment ?? ""
        case .color:
            transaction.highlightColor?.rawValue ?? ""
        }
    }

    private static func joinedHeaders(_ headers: [HTTPHeader]) -> String {
        headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
    }

    private static func bodyText(_ body: Data?) -> String {
        guard let body, !body.isEmpty else {
            return ""
        }
        return String(bytes: body.prefix(maxTextScanBytes), encoding: .utf8) ?? ""
    }

    private static func cookieText(for transaction: HTTPTransaction) -> String {
        let requestCookies = transaction.request.cookies
            .map { "\($0.name)=\($0.value); domain=\($0.domain); path=\($0.path)" }
        let responseCookies = (transaction.response?.setCookies ?? [])
            .map { "\($0.name)=\($0.value); domain=\($0.domain); path=\($0.path)" }
        return (requestCookies + responseCookies).joined(separator: "\n")
    }

    private static func contentTypeText(for transaction: HTTPTransaction) -> String {
        var values: [String] = []
        if let requestType = transaction.request.contentType {
            values.append(requestType.rawValue)
        }
        if let responseType = transaction.response?.contentType {
            values.append(responseType.rawValue)
        }
        values.append(contentsOf: transaction.request.headers
            .filter { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
            .map(\.value))
        values.append(contentsOf: (transaction.response?.headers ?? [])
            .filter { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
            .map(\.value))
        return values.joined(separator: "\n")
    }
}
