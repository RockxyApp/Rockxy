import Foundation
import JavaScriptCore

// Preview tabs a script publishes for one exchange (`context.previewTabs`).

// MARK: - ScriptPreviewTab

/// A titled block of text a script attached to a request or response, shown in the
/// inspector's Script tab. Scripts use it to display decoded or derived data
/// (a decrypted payload, a signature check, one field of a large body) without
/// changing what is sent on the wire.
struct ScriptPreviewTab: Codable, Equatable, Hashable, Sendable {
    // MARK: Internal

    /// Bounds keep a runaway script from bloating memory or session files.
    static let maxTabsPerPanel = 8
    static let maxTitleLength = 40
    static let maxTextBytes = 256 * 1_024

    var title: String
    var text: String
    var panel: PreviewPanel

    /// Reads `context.previewTabs`: an array of `{ title, text }`. `text` may be a string
    /// or any JSON-serializable value (pretty-printed). Malformed entries are skipped.
    static func read(from context: JSValue, panel: PreviewPanel) -> [ScriptPreviewTab] {
        guard let array = context.objectForKeyedSubscript("previewTabs"), array.isArray else {
            return []
        }
        let count = Int(array.objectForKeyedSubscript("length")?.toInt32() ?? 0)
        var tabs: [ScriptPreviewTab] = []
        for index in 0 ..< min(count, maxTabsPerPanel) {
            guard let entry = array.atIndex(index), entry.isObject else {
                continue
            }
            guard let text = text(from: entry.objectForKeyedSubscript("text")) else {
                continue
            }
            let rawTitle = entry.objectForKeyedSubscript("title")
            let title = rawTitle?.isString == true ? rawTitle?.toString() ?? "" : ""
            tabs.append(normalized(title: title, text: text, panel: panel))
        }
        return tabs
    }

    static func normalized(title: String, text: String, panel: PreviewPanel) -> ScriptPreviewTab {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedTitle = String((trimmed.isEmpty ? "Script" : trimmed).prefix(maxTitleLength))
        var boundedText = text
        if boundedText.utf8.count > maxTextBytes {
            var kept = String.UnicodeScalarView()
            var bytes = 0
            for scalar in boundedText.unicodeScalars {
                let width = UTF8.width(scalar)
                if bytes + width > maxTextBytes {
                    break
                }
                bytes += width
                kept.append(scalar)
            }
            boundedText = String(kept)
        }
        return ScriptPreviewTab(title: boundedTitle, text: boundedText, panel: panel)
    }

    // MARK: Private

    private static func text(from value: JSValue?) -> String? {
        guard let value, !value.isUndefined, !value.isNull else {
            return nil
        }
        if value.isString {
            return value.toString()
        }
        if value.isObject, let object = value.toObject(),
           JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        {
            return String(data: data, encoding: .utf8)
        }
        return value.toString()
    }
}
