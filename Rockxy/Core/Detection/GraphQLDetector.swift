import Foundation
import os

/// Identifies GraphQL requests by inspecting the HTTP method, path, and body.
/// When detected, extracts operation metadata (name, type, query, variables)
/// so the inspector can display GraphQL-specific views instead of raw JSON.
enum GraphQLDetector {
    // MARK: Internal

    static func detect(request: HTTPRequestData) -> GraphQLInfo? {
        let pathLooksGraphQL = request.path.lowercased().contains("graphql")
        let fields: [String: Any]
        switch request.method.uppercased() {
        case "POST":
            // Batched requests (a JSON array) carry several operations; they are not a
            // single operation and are left to the generic inspectors.
            guard let body = request.body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else
            {
                return nil
            }
            // Endpoints such as `/api` or `/gql` are recognized by the shape of the body: a
            // string `query` that is a GraphQL document.
            guard pathLooksGraphQL || isGraphQLDocument(json["query"] as? String) else {
                return nil
            }
            fields = json
        case "GET":
            guard pathLooksGraphQL else {
                return nil
            }
            // GraphQL over GET carries the document (or a persisted-query hash) in the URL.
            let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            var values: [String: Any] = [:]
            for item in items {
                values[item.name] = item.value
            }
            if let extensions = values["extensions"] as? String,
               let data = extensions.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data)
            {
                values["extensions"] = object
            }
            fields = values
        default:
            return nil
        }

        let query = fields["query"] as? String
        let isPersistedQuery = (fields["extensions"] as? [String: Any])?["persistedQuery"] != nil
        let declaredName = (fields["operationName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let operationName = declaredName?.isEmpty == false ? declaredName : query.flatMap(operationName(inQuery:))
        // Automatic persisted queries send only a hash and the operation name.
        guard query != nil || (isPersistedQuery && operationName != nil) else {
            return nil
        }

        let variables: String? = if let object = fields["variables"] as? [String: Any] {
            (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
        } else {
            fields["variables"] as? String
        }

        return GraphQLInfo(
            operationName: operationName,
            operationType: query.map(parseOperationType(from:)) ?? .query,
            query: query ?? "",
            variables: variables
        )
    }

    // MARK: Private

    /// True when `text` starts like a GraphQL executable document: an anonymous selection set
    /// or a `query` / `mutation` / `subscription` keyword. Plain search strings do not.
    private static func isGraphQLDocument(_ text: String?) -> Bool {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return false
        }
        if trimmed.hasPrefix("{") {
            return true
        }
        for keyword in ["query", "mutation", "subscription"] where trimmed.hasPrefix(keyword) {
            let rest = trimmed.dropFirst(keyword.count)
            if let next = rest.first, next == " " || next == "{" || next == "(" || next == "\n" || next == "\t" {
                return true
            }
        }
        return false
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "GraphQLDetector")

    /// Name of the first operation in the document (`query GetUser { … }` → `GetUser`),
    /// used when the client omits `operationName`. Anonymous operations return `nil`.
    static func operationName(inQuery query: String) -> String? {
        let pattern = #"^\s*(?:#[^\n]*\n\s*)*(?:query|mutation|subscription)\s+([_A-Za-z][_0-9A-Za-z]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query) else
        {
            return nil
        }
        return String(query[range])
    }

    /// GraphQL defaults to `query` when no keyword prefix is present (shorthand syntax).
    private static func parseOperationType(from query: String) -> GraphQLOperationType {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("mutation") {
            return .mutation
        }
        if trimmed.hasPrefix("subscription") {
            return .subscription
        }
        return .query
    }
}
