import Foundation

// MARK: - ScriptEditorIntent

/// Description of what the Script Editor window should open with when
/// consumed via `ScriptEditorSession.shared`. Mirrors the rule-editor
/// context-store pattern used elsewhere in the app.
enum ScriptEditorIntent: Equatable {
    /// Open an empty editor ready to create a brand-new script from the default
    /// template. Fields pre-filled with "Untitled Script N", URL empty, method
    /// Any, run on Request + Response, not mock.
    case createNew

    /// Open the editor for an existing plugin identified by its manifest id.
    case edit(pluginID: String)
}

// MARK: - ScriptEditorSession

/// Singleton cross-window store that the Scripting List uses to hand off an
/// intent to the Script Editor window before posting `.openScriptEditorWindow`.
@MainActor @Observable
final class ScriptEditorSession {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = ScriptEditorSession()

    private(set) var pendingIntent: ScriptEditorIntent?
    /// Monotonically incremented on every `setPending(_:)` so that a SwiftUI
    /// `.onChange(of: contextVersion)` handler in the editor window can fire
    /// even when the same plugin id is set again.
    var contextVersion: UInt64 = 0

    func setPending(_ intent: ScriptEditorIntent) {
        pendingIntent = intent
        contextVersion &+= 1
    }

    func consumePending() -> ScriptEditorIntent? {
        guard let intent = pendingIntent else {
            return nil
        }
        pendingIntent = nil
        return intent
    }
}
