import Foundation
import os

/// Identifies GraphQL requests by inspecting the HTTP method, path, and body.
/// When detected, extracts operation metadata (name, type, query, variables)
/// so the inspector can display GraphQL-specific views instead of raw JSON.
enum GraphQLDetector {
    // MARK: Internal

    /// GraphQL documents are small; larger bodies (uploads, bulk payloads) are not parsed.
    static let maxBodyBytes = 1_048_576

    static func detect(request: HTTPRequestData) -> GraphQLInfo? {
        let fields: [String: Any]
        // The method decides first: a GET/HEAD/OPTIONS request used to pay for a lowercased
        // copy of its path before reaching this switch, on every captured request.
        switch request.method.uppercased() {
        case "POST":
            // Batched requests (a JSON array) carry several operations; they are not a
            // single operation and are left to the generic inspectors.
            guard let body = request.body, body.count <= maxBodyBytes else {
                return nil
            }
            let pathLooksGraphQL = pathSuggestsGraphQL(request.path)
            // The accept test below needs either a GraphQL-looking path or a `query` member, so
            // run its byte-level approximation before the parse: an ordinary REST payload was
            // otherwise expanded into an object graph on the event loop and thrown away.
            guard pathLooksGraphQL || bodyMayCarryGraphQLDocument(body) else {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return nil
            }
            // Endpoints such as `/api` or `/gql` are recognized by the shape of the body: a
            // string `query` that is a GraphQL document.
            guard pathLooksGraphQL || isGraphQLDocument(json["query"] as? String) else {
                return nil
            }
            fields = json
        case "GET":
            guard pathSuggestsGraphQL(request.path) else {
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

    private static let jsonWhitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]

    /// First bytes of a UTF-8 JSON value that cannot decode to an object: array, string,
    /// number, `true`, `false`, `null`.
    private static let jsonNonObjectStarts: Set<UInt8> = Set(Array("[\"-0123456789tfn".utf8))

    /// A `query` member is written as this exact key token by any JSON encoder.
    private static let queryKeyBytes = Data("\"query\"".utf8)

    /// Case-insensitive `graphql` test that allocates nothing; `lowercased().contains` paid a
    /// whole-path ICU case mapping per request.
    private static func pathSuggestsGraphQL(_ path: String) -> Bool {
        path.range(of: "graphql", options: .caseInsensitive) != nil
    }

    /// Cheap approximation of the post-parse accept test, used to skip the parse entirely. It
    /// must never reject a body the parse would have accepted: `detect` only accepts a JSON
    /// object carrying a `query` member, and that key reaches the wire as the literal bytes
    /// `"query"`, so a UTF-8 object without them can never become an operation. A first byte
    /// that rules out an object is rejected outright; anything else — notably the UTF-16/32
    /// encodings `JSONSerialization` also sniffs — still pays the parse rather than risk a miss.
    private static func bodyMayCarryGraphQLDocument(_ body: Data) -> Bool {
        guard let firstByte = body.first(where: { !jsonWhitespace.contains($0) }) else {
            return false
        }
        guard firstByte == UInt8(ascii: "{") else {
            return !jsonNonObjectStarts.contains(firstByte)
        }
        // A LITTLE-ENDIAN UTF-16/32 object also begins with the byte `{`, and its `"query"` key
        // reaches the wire with a NUL after every character, so looking for the ASCII bytes
        // would miss a document `JSONSerialization` reads perfectly well -- which is exactly
        // what the encoding test caught. UTF-8 JSON cannot carry a NUL unescaped (RFC 8259), so
        // a NUL this early proves the body is one of those encodings, and the only sound answer
        // is to pay the parse. Big-endian and BOM-prefixed forms do not start with `{` at all,
        // so they never reach here.
        if body.prefix(4).contains(0) {
            return true
        }
        return body.range(of: queryKeyBytes) != nil
    }

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
