import Foundation

// MARK: - TransactionCacheEntry

/// A cache value that knows which transaction it was derived from.
protocol TransactionCacheEntry: AnyObject {
    var cacheID: UUID { get }
}

// MARK: - TransactionEvidenceCache

/// An `NSCache` keyed by transaction id that can drop entries on demand and say how many it holds.
///
/// `NSCache` sheds under memory pressure and past `countLimit`, but it cannot be asked what it
/// holds and it never learns that a row left the list. An entry whose transaction is gone can
/// never hit again, so the owner of the list discards the ids it evicts instead of leaving the
/// dead entries to occupy the cap. The cache tracks live keys itself, through the eviction
/// delegate, so a test can assert what is retained.
///
/// `count` is the number of keys this wrapper believes are stored. It cannot undercount
/// discards or limit evictions (both are reported); it can only overcount if the system
/// removes an entry without telling the delegate, which makes it an upper bound.
final class TransactionEvidenceCache<Entry: TransactionCacheEntry>: NSObject, NSCacheDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init(countLimit: Int) {
        super.init()
        cache.countLimit = countLimit
        cache.delegate = self
    }

    // MARK: Internal

    /// Keys currently stored, as far as the cache has reported.
    var count: Int {
        lock.withLock { tracked.count }
    }

    /// Whether the cache holds nothing. Sound even though `count` is only an upper bound:
    /// an overcount cannot fall below the truth, so a zero count means genuinely empty,
    /// and a stale tracked key can only make this report non-empty. The project enables
    /// SwiftFormat's `isEmpty` rule, which rewrites `count == 0` at every call site, so
    /// this member is what those call sites need to resolve to.
    var isEmpty: Bool {
        lock.withLock { tracked.isEmpty }
    }

    func entry(for id: UUID) -> Entry? {
        cache.object(forKey: id as NSUUID)
    }

    func store(_ entry: Entry) {
        let id = entry.cacheID
        lock.withLock { tracked[id] = ObjectIdentifier(entry) }
        cache.setObject(entry, forKey: id as NSUUID)
    }

    /// Drops the entries for `ids` and returns how many were actually held. Ids that were never
    /// cached, or were already evicted, are ignored.
    @discardableResult
    func discard(_ ids: some Sequence<UUID>) -> Int {
        var removed = 0
        for id in ids {
            let wasTracked = lock.withLock { tracked.removeValue(forKey: id) != nil }
            if wasTracked {
                removed += 1
            }
            cache.removeObject(forKey: id as NSUUID)
        }
        return removed
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        guard let entry = object as? Entry else {
            return
        }
        lock.withLock {
            // A replaced key evicts its old entry after the new one is tracked; only the entry
            // that is still the tracked one may clear the key.
            if tracked[entry.cacheID] == ObjectIdentifier(entry) {
                tracked.removeValue(forKey: entry.cacheID)
            }
        }
    }

    // MARK: Private

    private let cache = NSCache<NSUUID, Entry>()
    private let lock = NSLock()
    private var tracked: [UUID: ObjectIdentifier] = [:]
}
