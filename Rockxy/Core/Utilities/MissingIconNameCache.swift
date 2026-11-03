import Foundation

// Bounded negative cache shared by the three surfaces that resolve an app name to an icon.

// MARK: - MissingIconNameCache

/// Remembers app names that no icon lookup could resolve, so a redraw does not repeat the
/// `NSWorkspace` and filesystem walk that already came back empty.
///
/// The memory has to stay bounded because the name is client-controlled in content and in
/// length: `UpstreamResponseHandler.extractAppFromUserAgent` takes the text before the first
/// `/` of the User-Agent, and returns the entire header when it contains no `/` at all. So a
/// client picks both the key and its size, while the capture history these names come from is
/// capped at 1,000-10,000 rows. Unbounded, the cache outlived every row it was built for and
/// grew for the life of the process -- the long-capture lag in issue #416.
///
/// Same shape as `ProxyHandlerShared.warned`: a cap plus a stored key truncated to the length
/// a real app name needs. The one difference is FIFO eviction instead of cap-and-stop, because
/// this cache sits on a redraw path. Stopping at the cap would leave every later unresolved
/// name walking the filesystem on every redraw, which is the cost the cache exists to avoid.
struct MissingIconNameCache {
    // MARK: Internal

    /// 256 distinct unresolved names is far beyond what one capture's clients produce, and
    /// bounds the whole cache at roughly 256 x 64 bytes of name text.
    static let maximumNames = 256

    /// Matches `ProxyHandlerShared.maximumWarnedDetailLength`. An app bundle name this long is
    /// already pathological; the only cost of truncation is that two names sharing their first
    /// 64 characters share one negative entry, and for names that long the monogram fallback is
    /// the right answer for both. The positive icon caches stay keyed by the full name, so a
    /// truncated key can never return the wrong icon.
    static let maximumNameLength = 64

    /// Exposed so a test can assert the bound holds under a flood of distinct names.
    var count: Int {
        names.count
    }

    func contains(_ name: String) -> Bool {
        names.contains(Self.key(for: name))
    }

    mutating func insert(_ name: String) {
        let key = Self.key(for: name)
        guard names.insert(key).inserted else {
            return
        }
        insertionOrder.append(key)
        // A `Set`'s own iteration order is bucket order, so it cannot answer which entry is
        // the oldest; the parallel array is what makes the eviction FIFO rather than arbitrary.
        if insertionOrder.count > Self.maximumNames {
            names.remove(insertionOrder.removeFirst())
        }
    }

    // MARK: Private

    private var names: Set<String> = []
    private var insertionOrder: [String] = []

    private static func key(for name: String) -> String {
        String(name.prefix(maximumNameLength))
    }
}
