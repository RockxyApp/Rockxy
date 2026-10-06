import Foundation

// Helper types for OpenAPI export: path inference, schema inference, YAML, and HTML rendering.

// MARK: - OpenAPIParameter

struct OpenAPIParameter {
    let name: String
    let location: String
    let required: Bool
    let schema: [String: Any]

    func toDictionary() -> [String: Any] {
        [
            "name": name,
            "in": location,
            "required": required,
            "schema": schema
        ]
    }
}

// MARK: - OpenAPIPathTemplate

private struct OpenAPIPathTemplate {
    let template: String
    let parameters: [OpenAPIParameter]
}

// MARK: - OpenAPIPathTemplateInferer

enum OpenAPIPathTemplateInferer {
    static func infer(from url: URL) -> (template: String, parameters: [OpenAPIParameter]) {
        let rawSegments = url.path()
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !rawSegments.isEmpty else {
            return ("/", [])
        }

        var renderedSegments: [String] = []
        var parameters: [OpenAPIParameter] = []
        var usedNames: [String: Int] = [:]

        for segment in rawSegments {
            let decoded = segment.removingPercentEncoding ?? segment
            let kind = dynamicSegmentKind(decoded)
            if let kind {
                let baseName = parameterBaseName(from: renderedSegments.last) ?? "id"
                let name = uniqueName(baseName, usedNames: &usedNames)
                renderedSegments.append("{\(name)}")
                parameters.append(OpenAPIParameter(
                    name: name,
                    location: "path",
                    required: true,
                    schema: kind.schema
                ))
            } else {
                renderedSegments.append(segment)
            }
        }

        return ("/" + renderedSegments.joined(separator: "/"), parameters)
    }

    private static func dynamicSegmentKind(_ segment: String) -> PathSegmentKind? {
        if segment.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return .integer
        }
        if UUID(uuidString: segment) != nil {
            return .uuid
        }
        if segment.count >= 16,
           segment.range(of: #"^[0-9a-fA-F]+$"#, options: .regularExpression) != nil
        {
            return .hash
        }
        return nil
    }

    private static func parameterBaseName(from previousSegment: String?) -> String? {
        guard let previousSegment,
              !previousSegment.hasPrefix("{"),
              // A version prefix (`v1`, `v2`) says nothing about the resource.
              previousSegment.range(of: #"^v\d+$"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return nil
        }
        let cleaned = previousSegment
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "-")
            .map(String.init)
            .joined(separator: " ")
        let words = cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard let first = words.first else {
            return nil
        }
        // Only plain plurals lose the "s": `users` -> `user`, but `status`, `class` and `analysis`
        // are already singular.
        let word = String(first).lowercased()
        let isPlural = word.hasSuffix("s") && word.count > 3
            && !["ss", "us", "is"].contains(where: { word.hasSuffix($0) })
        let singular = isPlural ? String(first.dropLast()) : String(first)
        let rest = words.dropFirst().map { word in
            let lower = word.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
        return ([singular.lowercased()] + rest).joined() + "Id"
    }

    private static func uniqueName(_ base: String, usedNames: inout [String: Int]) -> String {
        let count = usedNames[base, default: 0] + 1
        usedNames[base] = count
        return count == 1 ? base : "\(base)\(count)"
    }
}

// MARK: - PathSegmentKind

private enum PathSegmentKind {
    case integer
    case uuid
    case hash

    var schema: [String: Any] {
        switch self {
        case .integer:
            ["type": "integer"]
        case .uuid:
            ["type": "string", "format": "uuid"]
        case .hash:
            ["type": "string"]
        }
    }
}

// MARK: - OpenAPISchemaInferer

enum OpenAPISchemaInferer {
    static let binarySchema: [String: Any] = [
        "type": "string",
        "format": "binary"
    ]

    static func schema(forScalars values: [String]) -> [String: Any] {
        let schemas = values.map { schema(forScalar: $0) }
        return schemas.dropFirst().reduce(schemas.first ?? ["type": "string"]) { partial, next in
            merge(partial, next)
        }
    }

    static func schema(forJSONSamples samples: [Any]) -> [String: Any] {
        let schemas = samples.map { schema(forJSONValue: $0) }
        return schemas.dropFirst().reduce(schemas.first ?? [:]) { partial, next in
            merge(partial, next)
        }
    }

    private static func schema(forScalar value: String) -> [String: Any] {
        if value.localizedCaseInsensitiveCompare("true") == .orderedSame
            || value.localizedCaseInsensitiveCompare("false") == .orderedSame
        {
            return ["type": "boolean"]
        }
        if Int(value) != nil {
            return ["type": "integer"]
        }
        if Double(value) != nil {
            return ["type": "number"]
        }
        if UUID(uuidString: value) != nil {
            return ["type": "string", "format": "uuid"]
        }
        if isDateTime(value) {
            return ["type": "string", "format": "date-time"]
        }
        if isDate(value) {
            return ["type": "string", "format": "date"]
        }
        return ["type": "string"]
    }

    private static func schema(forJSONValue value: Any) -> [String: Any] {
        if value is NSNull {
            return ["nullable": true]
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return ["type": "boolean"]
            }
            let doubleValue = number.doubleValue
            return floor(doubleValue) == doubleValue ? ["type": "integer"] : ["type": "number"]
        }
        if let string = value as? String {
            return schema(forScalar: string)
        }
        if let array = value as? [Any] {
            let itemSchema = array.isEmpty ? [:] : schema(forJSONSamples: array)
            return [
                "type": "array",
                "items": itemSchema
            ]
        }
        if let dictionary = value as? [String: Any] {
            var properties: [String: Any] = [:]
            for key in dictionary.keys.sorted() {
                properties[key] = schema(forJSONValue: dictionary[key] as Any)
            }
            var schema: [String: Any] = [
                "type": "object",
                "properties": properties
            ]
            if !dictionary.isEmpty {
                schema["required"] = dictionary.keys.sorted()
            }
            return schema
        }
        return ["type": "string"]
    }

    private static func merge(_ lhs: [String: Any], _ rhs: [String: Any]) -> [String: Any] {
        let lhsNullable = lhs["nullable"] as? Bool == true
        let rhsNullable = rhs["nullable"] as? Bool == true
        if Array(lhs.keys) == ["nullable"] {
            return rhs.settingNullable()
        }
        if Array(rhs.keys) == ["nullable"] {
            return lhs.settingNullable()
        }

        guard let lhsType = lhs["type"] as? String,
              let rhsType = rhs["type"] as? String else {
            return oneOf(lhs, rhs).settingNullable(lhsNullable || rhsNullable)
        }

        if lhsType == "integer", rhsType == "number" {
            return ["type": "number"].settingNullable(lhsNullable || rhsNullable)
        }
        if lhsType == "number", rhsType == "integer" {
            return ["type": "number"].settingNullable(lhsNullable || rhsNullable)
        }

        guard lhsType == rhsType else {
            return oneOf(lhs.removingNullable(), rhs.removingNullable())
                .settingNullable(lhsNullable || rhsNullable)
        }

        var merged = lhs.removingNullable()
        switch lhsType {
        case "object":
            let lhsProperties = lhs["properties"] as? [String: Any] ?? [:]
            let rhsProperties = rhs["properties"] as? [String: Any] ?? [:]
            var properties: [String: Any] = [:]
            for key in Set(lhsProperties.keys).union(rhsProperties.keys).sorted() {
                if let left = lhsProperties[key] as? [String: Any],
                   let right = rhsProperties[key] as? [String: Any]
                {
                    properties[key] = merge(left, right)
                } else {
                    properties[key] = lhsProperties[key] ?? rhsProperties[key]
                }
            }
            let lhsRequired = Set(lhs["required"] as? [String] ?? [])
            let rhsRequired = Set(rhs["required"] as? [String] ?? [])
            let required = lhsRequired.intersection(rhsRequired).sorted()
            merged["properties"] = properties
            if required.isEmpty {
                merged.removeValue(forKey: "required")
            } else {
                merged["required"] = required
            }
        case "array":
            if let lhsItems = lhs["items"] as? [String: Any],
               let rhsItems = rhs["items"] as? [String: Any]
            {
                merged["items"] = merge(lhsItems, rhsItems)
            }
        case "string":
            if lhs["format"] as? String != rhs["format"] as? String {
                merged.removeValue(forKey: "format")
            }
        default:
            break
        }
        return merged.settingNullable(lhsNullable || rhsNullable)
    }

    private static func oneOf(_ lhs: [String: Any], _ rhs: [String: Any]) -> [String: Any] {
        let values = flattenedOneOf(lhs) + flattenedOneOf(rhs)
        var seen: Set<String> = []
        let unique = values.compactMap { schema -> [String: Any]? in
            guard let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]),
                  let key = String(data: data, encoding: .utf8),
                  !seen.contains(key) else {
                return nil
            }
            seen.insert(key)
            return schema
        }
        return ["oneOf": unique]
    }

    private static func flattenedOneOf(_ schema: [String: Any]) -> [[String: Any]] {
        schema["oneOf"] as? [[String: Any]] ?? [schema]
    }

    private static func isDateTime(_ value: String) -> Bool {
        ISO8601DateFormatter().date(from: value) != nil
    }

    private static func isDate(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}

// MARK: - Dictionary Helpers

private extension Dictionary where Key == String, Value == Any {
    func settingNullable(_ nullable: Bool = true) -> [String: Any] {
        guard nullable else {
            return self
        }
        var copy = self
        copy["nullable"] = true
        return copy
    }

    func removingNullable() -> [String: Any] {
        var copy = self
        copy.removeValue(forKey: "nullable")
        return copy
    }
}

// MARK: - OpenAPIYAMLWriter

struct OpenAPIYAMLWriter {
    func string(from object: Any) -> String {
        render(object, indent: 0) + "\n"
    }

    private func render(_ object: Any, indent: Int) -> String {
        if let dictionary = object as? [String: Any] {
            return renderDictionary(dictionary, indent: indent)
        }
        if let array = object as? [Any] {
            return renderArray(array, indent: indent)
        }
        return renderScalar(object)
    }

    private func renderDictionary(_ dictionary: [String: Any], indent: Int) -> String {
        guard !dictionary.isEmpty else {
            return "{}"
        }
        let prefix = String(repeating: " ", count: indent)
        return orderedKeys(for: dictionary).map { key in
            let value = dictionary[key] as Any
            if isCollection(value) {
                return "\(prefix)\(quoted(key)):\n\(render(value, indent: indent + 2))"
            }
            return "\(prefix)\(quoted(key)): \(renderScalar(value))"
        }.joined(separator: "\n")
    }

    private func renderArray(_ array: [Any], indent: Int) -> String {
        guard !array.isEmpty else {
            return "[]"
        }
        let prefix = String(repeating: " ", count: indent)
        return array.map { value in
            if isCollection(value) {
                return "\(prefix)-\n\(render(value, indent: indent + 2))"
            }
            return "\(prefix)- \(renderScalar(value))"
        }.joined(separator: "\n")
    }

    private func renderScalar(_ value: Any) -> String {
        switch value {
        case let string as String:
            quoted(string)
        case let bool as Bool:
            bool ? "true" : "false"
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                number.boolValue ? "true" : "false"
            } else {
                "\(number)"
            }
        case _ as NSNull:
            "null"
        default:
            quoted("\(value)")
        }
    }

    private func isCollection(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            return !dictionary.isEmpty
        }
        if let array = value as? [Any] {
            return !array.isEmpty
        }
        return false
    }

    private func orderedKeys(for dictionary: [String: Any]) -> [String] {
        let priority = [
            "openapi", "info", "title", "version", "description", "servers", "url", "paths", "components",
            "securitySchemes", "type", "scheme", "operationId", "tags", "parameters", "name", "in", "required",
            "schema", "requestBody", "content", "responses", "properties", "items", "format", "nullable", "oneOf"
        ]
        return dictionary.keys.sorted { lhs, rhs in
            let lhsIndex = priority.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = priority.firstIndex(of: rhs) ?? Int.max
            if lhsIndex == rhsIndex {
                return lhs < rhs
            }
            return lhsIndex < rhsIndex
        }
    }

    private func quoted(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

// MARK: - OpenAPIHTMLRenderer

struct OpenAPIHTMLRenderer {
    func data(for document: [String: Any]) throws -> Data {
        let specData = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        let spec = String(data: specData, encoding: .utf8)?
            .replacingOccurrences(of: "</", with: "<\\/")
            ?? "{}"
        let css = resource(named: "swagger-ui", extension: "css") ?? fallbackCSS
        let script = resource(named: "swagger-ui-bundle", extension: "js") ?? fallbackScript
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Rockxy OpenAPI Export</title>
          <style>\(css)</style>
        </head>
        <body>
          <div id="swagger-ui"></div>
          <script>\(script)</script>
          <script>
          window.addEventListener("load", function() {
            const spec = \(spec);
            SwaggerUIBundle({
              spec: spec,
              dom_id: "#swagger-ui",
              validatorUrl: null,
              supportedSubmitMethods: [],
              withCredentials: false,
              persistAuthorization: false
            });
          });
          </script>
        </body>
        </html>
        """
        return Data(html.utf8)
    }

    private func resource(named name: String, extension ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "SwaggerUI") ??
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/SwaggerUI") ??
            Bundle.main.url(forResource: name, withExtension: ext)
        else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private var fallbackCSS: String {
        "body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0}#swagger-ui{padding:24px}"
    }

    private var fallbackScript: String {
        """
        function SwaggerUIBundle(config){
          var el=document.querySelector(config.dom_id);
          el.innerHTML="<pre>"+JSON.stringify(config.spec,null,2)+"</pre>";
        }
        """
    }
}
