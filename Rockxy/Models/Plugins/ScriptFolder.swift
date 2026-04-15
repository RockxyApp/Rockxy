import Foundation

// MARK: - ScriptFolder

/// One folder grouping in the Scripting List window. Folders are flat on disk —
/// each script's `plugin.json` carries an optional `folderID`, and the folder
/// metadata (name, expanded state, ordering) lives in `ScriptFolderIndex`,
/// persisted as a single JSON blob in UserDefaults.
struct ScriptFolder: Codable, Identifiable, Equatable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), name: String, expanded: Bool = true, scriptIDs: [String] = []) {
        self.id = id
        self.name = name
        self.expanded = expanded
        self.scriptIDs = scriptIDs
    }

    // MARK: Internal

    var id: UUID
    var name: String
    var expanded: Bool
    var scriptIDs: [String]
}

// MARK: - ScriptFolderIndex

/// Top-level ordering + folder definitions for the Scripting List window.
/// `rootOrder` mixes folder entries and loose-script entries so the UI can
/// render the list in user-defined order.
struct ScriptFolderIndex: Codable, Equatable {
    // MARK: Lifecycle

    init(folders: [ScriptFolder] = [], rootOrder: [Entry] = []) {
        self.folders = folders
        self.rootOrder = rootOrder
    }

    // MARK: Internal

    enum Entry: Codable, Equatable {
        case folder(UUID)
        case script(String)

        // MARK: Lifecycle

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let hasFolder = container.contains(.folder)
            let hasScript = container.contains(.script)
            if hasFolder, hasScript {
                throw DecodingError.dataCorruptedError(
                    forKey: .folder,
                    in: container,
                    debugDescription: "Payload must contain either folder or script, not both"
                )
            }
            if let folderID = try container.decodeIfPresent(UUID.self, forKey: .folder) {
                self = .folder(folderID)
                return
            }
            if let scriptID = try container.decodeIfPresent(String.self, forKey: .script) {
                self = .script(scriptID)
                return
            }
            throw DecodingError.dataCorruptedError(
                forKey: .folder,
                in: container,
                debugDescription: "ScriptFolderIndex.Entry must be either folder or script"
            )
        }

        // MARK: Internal

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .folder(id):
                try container.encode(id, forKey: .folder)
            case let .script(id):
                try container.encode(id, forKey: .script)
            }
        }

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case folder
            case script
        }
    }

    static let empty = ScriptFolderIndex()

    var folders: [ScriptFolder]
    var rootOrder: [Entry]
}
