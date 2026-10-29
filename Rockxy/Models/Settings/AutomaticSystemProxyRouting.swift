import Foundation

// MARK: - AutomaticSystemProxyRouting

enum AutomaticSystemProxyRouting {
    static let defaultsKey = RockxyIdentity.current.defaultsKey("automaticallySetSystemProxy")

    /// Existing installations keep one-click capture until the user selects manual routing.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) == nil || defaults.bool(forKey: defaultsKey)
    }

    /// Every listener start uses this gate, including launch and restart. Recheck the saved
    /// preference immediately before mutation so opting out during startup is respected.
    @MainActor
    static func enableForCapture(
        enabledAtStart: Bool,
        currentPreference: () -> Bool = { isEnabled() },
        enable: () async throws -> Void
    )
        async throws -> Bool
    {
        guard enabledAtStart, currentPreference() else {
            return false
        }
        try await enable()
        return true
    }
}
