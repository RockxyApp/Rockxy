import Foundation

// MARK: - GraphQLResponseError

/// One entry from a GraphQL response's top-level `errors` array.
struct GraphQLResponseError: Equatable, Sendable {
    let message: String
    /// The response path the error applies to, joined with dots (for example `user.posts.0.title`).
    let path: String?
    /// `extensions.code` when the server provides one (for example `UNAUTHENTICATED`).
    let code: String?
}

// MARK: - GraphQLResponseErrorSummary

/// GraphQL servers usually answer with HTTP 200 even when an operation fails, and report the
/// failure in the body's `errors` array. This summary makes those failures visible without
/// reading the raw JSON.
struct GraphQLResponseErrorSummary: Equatable, Sendable {
    // MARK: Internal

    static let maxPayloadBytes = 512 * 1_024
    static let maxErrors = 50

    let errors: [GraphQLResponseError]
    /// Total entries in `errors`, which can exceed `errors.count` when the list was capped.
    let totalCount: Int
    /// Whether the response also carried non-null `data`, meaning the operation partly succeeded.
    let hasPartialData: Bool

    /// Returns `nil` when the body is not a GraphQL response with errors.
    static func parse(_ body: Data?) -> GraphQLResponseErrorSummary? {
        guard let body, !body.isEmpty, body.count <= maxPayloadBytes,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let rawErrors = object["errors"] as? [Any],
              !rawErrors.isEmpty else
        {
            return nil
        }

        let errors = rawErrors.prefix(maxErrors).map(error(from:))
        let data = object["data"]
        let hasPartialData = data != nil && !(data is NSNull)
        return GraphQLResponseErrorSummary(
            errors: errors,
            totalCount: rawErrors.count,
            hasPartialData: hasPartialData
        )
    }

    // MARK: Private

    private static let maxMessageLength = 2_000

    private static func error(from value: Any) -> GraphQLResponseError {
        guard let entry = value as? [String: Any] else {
            return GraphQLResponseError(
                message: String(describing: value).truncated(maxMessageLength),
                path: nil,
                code: nil
            )
        }
        let message = (entry["message"] as? String) ?? ""
        let path = (entry["path"] as? [Any])?
            .map { component in
                if let number = component as? NSNumber {
                    return number.stringValue
                }
                return component as? String ?? String(describing: component)
            }
            .joined(separator: ".")
        let code = (entry["extensions"] as? [String: Any])?["code"] as? String
        return GraphQLResponseError(
            message: message.truncated(maxMessageLength),
            path: path?.isEmpty == true ? nil : path,
            code: code
        )
    }
}

private extension String {
    func truncated(_ limit: Int) -> String {
        count > limit ? String(prefix(limit)) + "…" : self
    }
}
