import Foundation

/// Persists the user's explicit workspace inspector choices.
/// A missing bottom-inspector value keeps the app in automatic reveal mode.
struct WorkspaceLayoutPreferences {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Internal

    var preferredBottomInspectorVisibility: Bool? {
        guard defaults.object(forKey: Self.bottomInspectorVisibilityKey) != nil else {
            return nil
        }
        return defaults.bool(forKey: Self.bottomInspectorVisibilityKey)
    }

    var preferredContextDockVisibility: Bool {
        guard defaults.object(forKey: Self.contextDockVisibilityKey) != nil else {
            return false
        }
        return defaults.bool(forKey: Self.contextDockVisibilityKey)
    }

    func rememberBottomInspectorVisibility(_ isVisible: Bool) {
        defaults.set(isVisible, forKey: Self.bottomInspectorVisibilityKey)
    }

    func rememberContextDockVisibility(_ isVisible: Bool) {
        defaults.set(isVisible, forKey: Self.contextDockVisibilityKey)
    }

    // MARK: Private

    private static let bottomInspectorVisibilityKey = RockxyIdentity.current
        .defaultsKey("workspace.bottomInspectorVisible")
    private static let contextDockVisibilityKey = RockxyIdentity.current
        .defaultsKey("workspace.contextDockVisible")

    private let defaults: UserDefaults
}
