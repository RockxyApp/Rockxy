import Foundation

// Defines `PluginManifest`, the model for plugin manifest used by plugin discovery and
// settings.

// MARK: - PluginManifest

/// Codable representation of a plugin's `plugin.json` manifest file.
/// Describes the plugin's identity, capabilities, entry points, and user-configurable fields.
struct PluginManifest: Codable {
    let id: String
    let name: String
    let version: String
    let author: PluginAuthor
    let description: String
    var types: [PluginType]
    var entryPoints: [String: String]
    var capabilities: [String]
    var configuration: [String: PluginConfigField]?
    var minRockxyVersion: String?
    var homepage: String?
    var license: String?
    /// Optional block describing per-script matching + request/response/mock gating.
    /// Only consulted when `types` contains `.script`. Absence means defaults — see
    /// `ScriptBehavior.defaults()`.
    var scriptBehavior: ScriptBehavior?
}

// MARK: - PluginAuthor

struct PluginAuthor: Codable {
    let name: String
    let url: String?
}

// MARK: - PluginType

enum PluginType: String, Codable {
    case script
    case inspector
    case exporter
    case detector
}

// MARK: - PluginConfigField

/// Describes a single user-configurable field in the plugin's settings form.
/// The `type` string maps to a SwiftUI control: "string" → TextField, "boolean" → Toggle, "number" → TextField with
/// number format.
struct PluginConfigField: Codable {
    let type: String
    let title: String
    var secret: Bool?
    var defaultValue: AnyCodableValue?
}

// MARK: - AnyCodableValue

/// Type-erased Codable value for plugin configuration defaults.
/// Supports the primitive types needed by plugin.json configuration fields.
enum AnyCodableValue: Codable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported config value type"
                )
            )
        }
    }

    // MARK: Internal

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        }
    }
}
