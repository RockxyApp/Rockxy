import AppKit
import Darwin
import Foundation

/// Single mint point for AppKit autosave identifiers used by tests.
///
/// AppKit persists `NSSplitView Subview Frames <name>` and
/// `NSToolbar Configuration <id>` into `UserDefaults.standard`, which in the
/// test host is the installed app's real preferences domain. A UUID-suffixed
/// name per test therefore leaks one key per use, forever. Every mint goes
/// through here, and the first mint in a process sweeps the stale keys that
/// earlier runs left, so a run inherits nothing and leaves at most its own.
///
/// Minted names embed the owning process id (`<Suite>-<pid>-<uuid>`). The sweep
/// skips keys whose pid is still running, so a parallel test process never has
/// a live key deleted. Keys without a pid (the older `<Suite>-<uuid>` shape)
/// predate this helper and are always stale.
enum AppKitAutosaveTestKeys {
    /// Suites that mint identifiers. Includes suites that no longer exist
    /// but whose keys are still present in preferences from older runs.
    enum Suite: String, CaseIterable {
        case workspaceSplitView = "NativeWorkspaceSplitViewTests"
        case bottomInspectorSplitView = "NativeBottomInspectorSplitViewTests"
        case contextDockSplitView = "NativeContextDockSplitViewTests"
        case inspectorSplitView = "NativeInspectorSplitViewTests"
    }

    // MARK: - Sweeper

    /// Removes stale keys carrying a test prefix, at most once per instance.
    /// It never runs again mid-process, so a key a running test relies on is
    /// never deleted, and it skips keys owned by a still-running process.
    final class Sweeper: @unchecked Sendable {
        // MARK: Lifecycle

        init(defaults: UserDefaults) {
            self.defaults = defaults
        }

        // MARK: Internal

        private(set) var removedKeyCount = 0

        var hasSwept: Bool {
            lock.lock()
            defer { lock.unlock() }
            return swept
        }

        /// Number of keys in this sweeper's domain that carry a test prefix.
        func prefixedKeyCount() -> Int {
            Self.prefixedKeys(in: defaults).count
        }

        func sweepOnce() {
            lock.lock()
            defer { lock.unlock() }
            guard !swept else {
                return
            }
            swept = true
            let stale = Self.prefixedKeys(in: defaults).filter { key in
                guard let pid = AppKitAutosaveTestKeys.ownerPID(ofKey: key) else {
                    return true
                }
                return !AppKitAutosaveTestKeys.isProcessAlive(pid)
            }
            for key in stale {
                defaults.removeObject(forKey: key)
            }
            removedKeyCount = stale.count
        }

        // MARK: Private

        private let defaults: UserDefaults
        private let lock = NSLock()
        private var swept = false

        private static func prefixedKeys(in defaults: UserDefaults) -> [String] {
            let prefixes = AppKitAutosaveTestKeys.sweptKeyPrefixes
            return defaults.dictionaryRepresentation().keys.filter { key in
                prefixes.contains { key.hasPrefix($0) }
            }
        }
    }

    static let splitViewKeyPrefix = "NSSplitView Subview Frames "
    static let toolbarKeyPrefix = "NSToolbar Configuration "

    /// Process-wide sweeper bound to the real defaults domain.
    static let shared = Sweeper(defaults: .standard)

    /// Every key prefix a mint can produce, for sweeping and for counting.
    static var sweptKeyPrefixes: [String] {
        Suite.allCases.flatMap { suite in
            [
                splitViewKeyPrefix + splitViewNamePrefix(suite),
                toolbarKeyPrefix + toolbarIdentifierPrefix(suite),
            ]
        }
    }

    static func splitViewNamePrefix(_ suite: Suite) -> String {
        "\(suite.rawValue)-"
    }

    static func toolbarIdentifierPrefix(_ suite: Suite) -> String {
        "\(suite.rawValue).Toolbar."
    }

    static func uniqueSplitViewAutosaveName(for suite: Suite, sweeper: Sweeper = shared) -> String {
        sweeper.sweepOnce()
        return splitViewNamePrefix(suite) + ownerToken()
    }

    static func uniqueToolbarIdentifier(for suite: Suite, sweeper: Sweeper = shared) -> NSToolbar.Identifier {
        sweeper.sweepOnce()
        return NSToolbar.Identifier(toolbarIdentifierPrefix(suite) + ownerToken())
    }

    static func ownerToken(pid: Int32 = ProcessInfo.processInfo.processIdentifier) -> String {
        "\(pid)-\(UUID().uuidString)"
    }

    /// The pid embedded in a minted name, or nil for the older pid-less shape.
    static func ownerPID(ofKey key: String) -> Int32? {
        guard let prefix = sweptKeyPrefixes.first(where: { key.hasPrefix($0) }) else {
            return nil
        }
        let component = key.dropFirst(prefix.count).prefix { $0 != "-" }
        // A UUID's first group is 8 characters; a pid is at most 7 digits.
        guard (1 ... 7).contains(component.count) else {
            return nil
        }
        return Int32(component)
    }

    static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func removeSplitViewAutosaveDefaults(_ name: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: splitViewKeyPrefix + name)
    }

    static func removeToolbarConfigurationDefaults(
        _ identifier: NSToolbar.Identifier,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: toolbarKeyPrefix + identifier)
    }
}
