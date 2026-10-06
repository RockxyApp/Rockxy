import Foundation

// MARK: - FormURLEncodedBody

/// Reads and writes `application/x-www-form-urlencoded` bodies as ordered name/value fields,
/// so Compose can edit a form body as a table instead of escaped text.
enum FormURLEncodedBody {
    struct Field: Equatable {
        var name: String
        var value: String
    }

    static func isFormContentType(_ headers: [EditableReplayHeader]) -> Bool {
        headers.contains {
            $0.isEnabled && $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
                && $0.value.lowercased().contains("application/x-www-form-urlencoded")
        }
    }

    static func fields(from body: String) -> [Field] {
        body.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return Field(
                name: decode(parts.first.map(String.init) ?? ""),
                value: parts.count > 1 ? decode(String(parts[1])) : ""
            )
        }
    }

    static func body(from fields: [Field]) -> String {
        fields.map { "\(encode($0.name))=\(encode($0.value))" }.joined(separator: "&")
    }

    // MARK: Private

    /// Unreserved characters stay literal; a space becomes `+` as HTML forms send it.
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._*")
        return set
    }()

    private static func encode(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "+")
    }

    private static func decode(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
