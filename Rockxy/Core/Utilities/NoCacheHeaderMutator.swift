import Foundation
import NIOHTTP1
import os

// Applies anti-cache header mutations when the global no-caching mode is enabled.

// MARK: - NoCacheHeaderMutator

/// Applies anti-cache header mutations when the global "No Caching" toggle is active.
///
/// Requests gain `Cache-Control` and `Pragma` directives and lose their conditional
/// validators (`If-Modified-Since`, `If-None-Match`) so origin servers return fresh
/// responses. Relayed responses lose their freshness/validator headers (`Expires`,
/// `Last-Modified`, `ETag`) and are marked uncacheable, so the client does not serve
/// the next load from its own cache and skip the proxy entirely.
enum NoCacheHeaderMutator {
    /// The UserDefaults key matching the `@AppStorage` toggle in ToolsSettingsTab.
    static let userDefaultsKey = RockxyIdentity.current.defaultsKey("noCaching")

    /// Returns `true` when the user has enabled the No Caching toggle.
    ///
    /// Answered from a cached snapshot. `HTTPProxyHandler` and `HTTPSProxyRelayHandler` ask
    /// once per request from several NIO event-loop threads at a time; `UserDefaults` serves
    /// from the in-process CFPreferences cache, so that was never a disk read, but it is a
    /// lock acquisition plus a keyed lookup taken concurrently on the per-request path.
    ///
    /// The toggle is live, so the snapshot is invalidated on `UserDefaults.didChangeNotification`
    /// rather than read once at launch — reading once would stop the toggle taking effect
    /// until relaunch. This is `ScriptPluginManager.scriptingToolEnabledCache`'s shape and it
    /// carries the same residual: the notification orders the flip against later reads, not
    /// against a request already past this call, and a write from another process (the CLI)
    /// is delivered when that process's change is noticed rather than at the write. The cost
    /// of that window is one request served from the client's own cache, or one needlessly
    /// revalidated; the next request is correct.
    static var isEnabled: Bool {
        if let cached = enabledCache.withLock({ $0 }) {
            return cached
        }
        let value = UserDefaults.standard.bool(forKey: userDefaultsKey)
        enabledCache.withLock { $0 = value }
        return value
    }

    /// Mutates an array of `HTTPHeader` values by injecting anti-cache directives
    /// and removing conditional request headers. Returns the modified array.
    static func apply(to headers: [HTTPHeader]) -> [HTTPHeader] {
        var result = headers.filter {
            $0.name.caseInsensitiveCompare("If-Modified-Since") != .orderedSame
                && $0.name.caseInsensitiveCompare("If-None-Match") != .orderedSame
        }

        result.removeAll { $0.name.caseInsensitiveCompare("Cache-Control") == .orderedSame }
        result.append(HTTPHeader(name: "Cache-Control", value: "no-cache, no-store, must-revalidate"))

        result.removeAll { $0.name.caseInsensitiveCompare("Pragma") == .orderedSame }
        result.append(HTTPHeader(name: "Pragma", value: "no-cache"))

        return result
    }

    /// Response-side counterpart of `apply(to:)`: strips freshness and validator headers
    /// the client would otherwise use to reuse or revalidate the response, then marks it
    /// uncacheable. Applied to the relayed head only, never to WebSocket upgrades.
    static func applyToResponse(_ headers: inout HTTPHeaders) {
        for name in ["Expires", "Last-Modified", "ETag", "Cache-Control", "Pragma"] {
            headers.remove(name: name)
        }
        headers.add(name: "Cache-Control", value: "no-cache, no-store, must-revalidate")
        headers.add(name: "Pragma", value: "no-cache")
        headers.add(name: "Expires", value: "0")
    }

    // MARK: Private

    /// The toggle as the request path last read it; `nil` means it has to be read again.
    /// The box and its observer live for the process, so the observer is never removed --
    /// unlike `ScriptPluginManager`, which has one observer per instance and has to.
    private static let enabledCache: OSAllocatedUnfairLock<Bool?> = {
        let cache = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        _ = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            cache.withLock { $0 = nil }
        }
        return cache
    }()
}
