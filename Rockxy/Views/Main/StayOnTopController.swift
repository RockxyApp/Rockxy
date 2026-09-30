import AppKit

// Keeps Rockxy's windows above other apps when the "Stay on Top" preference is on.

// MARK: - StayOnTopController

@MainActor
final class StayOnTopController {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = StayOnTopController()

    static let defaultsKey = RockxyIdentity.current.defaultsKey("stayOnTop")

    /// Applies the current preference and keeps it applied as windows open and the preference changes.
    func start() {
        guard observers.isEmpty else {
            return
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Every defaults write posts this; only act when the preference itself changed.
            MainActor.assumeIsolated { self?.applyIfPreferenceChanged() }
        })
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        apply()
    }

    private func applyIfPreferenceChanged() {
        let enabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        guard enabled != lastAppliedState else {
            return
        }
        apply()
    }

    func apply() {
        lastAppliedState = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        let level: NSWindow.Level = UserDefaults.standard.bool(forKey: Self.defaultsKey) ? .floating : .normal
        for window in NSApp.windows where window.styleMask.contains(.titled) && window.level != level {
            window.level = level
        }
    }

    // MARK: Private

    private var observers: [NSObjectProtocol] = []
    private var lastAppliedState = false
}
