import Foundation
import os

/// Identifies GraphQL requests by inspecting the HTTP method, path, and body.
/// When detected, extracts operation metadata (name, type, query, variables)
/// so the inspector can display GraphQL-specific views instead of raw JSON.
enum GraphQLDetector {
    // MARK: Internal

    static func detect(request: HTTPRequestData) -> GraphQLInfo? {
        // GraphQL mutations/queries are always POST; GET queries exist but are uncommon
        guard request.method.uppercased() == "POST" else {
            return nil
        }
        guard request.path.contains("graphql") else {
            return nil
        }
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let query = json["query"] as? String else
        {
            return nil
        }

        let operationName = json["operationName"] as? String
        let variables = (json["variables"] as? [String: Any])
            .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { String(data: $0, encoding: .utf8) }

        let operationType = parseOperationType(from: query)

        return GraphQLInfo(
            operationName: operationName,
            operationType: operationType,
            query: query,
            variables: variables
        )
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "GraphQLDetector")

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
