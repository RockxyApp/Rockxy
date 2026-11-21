import Foundation

// MARK: - SystemProxyRoutingMode

/// How Rockxy is allowed to change the macOS system proxy.
enum SystemProxyRoutingMode: String, CaseIterable, Identifiable, Sendable {
    /// Capture start and restart set the system proxy (the default).
    case automatic
    /// Capture never sets the system proxy; the explicit control stays available.
    case manual
    /// Rockxy never acquires the system proxy by any path. Restoring stays available.
    case never

    // MARK: Internal

    var id: String {
        rawValue
    }
}

// MARK: - SystemProxyRoutingOperation

enum SystemProxyRoutingOperation: Sendable {
    /// Capture start / restart taking over routing without a user request.
    case acquireAutomatically
    /// A user-facing control (toggle, retry, Welcome, CLI) taking over routing.
    case acquireExplicitly
    /// Stop, Restart, quit, switch-off, or recovery handing routing back.
    case release
}

// MARK: - SystemProxyRoutingBlocked

struct SystemProxyRoutingBlocked: LocalizedError {
    var errorDescription: String? {
        AutomaticSystemProxyRouting.neverUnavailableReason
    }
}

// MARK: - AutomaticSystemProxyRouting

enum AutomaticSystemProxyRouting {
    /// Legacy boolean key. Still read for migration and mirrored on write so older builds keep
    /// a compatible meaning (`true` only for Automatic).
    static let defaultsKey = RockxyIdentity.current.defaultsKey("automaticallySetSystemProxy")
    static let modeDefaultsKey = RockxyIdentity.current.defaultsKey("systemProxyRoutingMode")

    /// The saved mode every enforcement point reads. Tests substitute it so they never touch
    /// the preferences shared with the installed app.
    nonisolated(unsafe) static var modeProvider: () -> SystemProxyRoutingMode = { mode() }

    /// Readable reason shown wherever Never makes a system-proxy control unavailable.
    static var neverUnavailableReason: String {
        String(
            localized: "System proxy changes are turned off in Settings. Choose Automatic or Manual to use this.",
            bundle: RockxyLocalization.bundle
        )
    }

    /// Migration is read-only: no key -> Automatic, `true` -> Automatic, `false` -> Manual.
    /// An unrecognised stored mode falls back to the legacy boolean rather than guessing.
    static func mode(in defaults: UserDefaults = .standard) -> SystemProxyRoutingMode {
        if let raw = defaults.string(forKey: modeDefaultsKey),
           let mode = SystemProxyRoutingMode(rawValue: raw)
        {
            return mode
        }
        if defaults.object(forKey: defaultsKey) != nil, !defaults.bool(forKey: defaultsKey) {
            return .manual
        }
        return .automatic
    }

    static func setMode(_ mode: SystemProxyRoutingMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: modeDefaultsKey)
        defaults.set(mode == .automatic, forKey: defaultsKey)
    }

    /// True only in Automatic: capture start may set the system proxy on its own.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        mode(in: defaults) == .automatic
    }

    /// Never blocks acquiring, never blocks releasing.
    static func permits(_ operation: SystemProxyRoutingOperation, mode: SystemProxyRoutingMode) -> Bool {
        switch operation {
        case .acquireAutomatically:
            mode == .automatic
        case .acquireExplicitly:
            mode != .never
        case .release:
            true
        }
    }

    /// Why a control that would set the system proxy is unavailable, or nil when it is usable.
    /// `storedMode` is the raw `@AppStorage` value so views refresh when the setting changes.
    /// A control that switches an existing override off is a release and is never disabled.
    static func acquisitionUnavailableReason(storedMode: String, isOverrideActive: Bool) -> String? {
        guard SystemProxyRoutingMode(rawValue: storedMode) == .never, !isOverrideActive else {
            return nil
        }
        return neverUnavailableReason
    }

    static func currentMode() -> SystemProxyRoutingMode {
        modeProvider()
    }

    /// Call at the top of every path that would set the system proxy, and again inside
    /// `SystemProxyManager.enableSystemProxy` so a caller that forgets still gets refused.
    static func requireExplicitAcquisition(mode: SystemProxyRoutingMode = currentMode()) throws {
        guard permits(.acquireExplicitly, mode: mode) else {
            throw SystemProxyRoutingBlocked()
        }
    }

    /// Every listener start uses this gate, including launch and restart. Recheck the saved
    /// preference immediately before mutation so opting out during startup is respected.
    ///
    /// This is where Manual is enforced, and the only place: `requireExplicitAcquisition`, the
    /// backstop inside `SystemProxyManager.enableSystemProxy`, deliberately permits Manual
    /// because an explicit toggle has to keep working there. The default predicate asks
    /// `permits(.acquireAutomatically:)` rather than comparing the mode inline, so the rule has a
    /// single definition and an acquisition nobody asked for is refused by the same table that
    /// describes every other operation.
    @MainActor
    static func enableForCapture(
        enabledAtStart: Bool,
        currentPreference: () -> Bool = { permits(.acquireAutomatically, mode: currentMode()) },
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
