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
/// `count` is the number of keys this wrapper holds. It is exact whenever no `store` or
/// `discard` is mid-flight: every way an entry leaves the cache (discard, replacement, count
/// limit, memory pressure) either goes through `discard` or is reported by the eviction
/// delegate, and the bookkeeping for the two writers is serialised (see "Locking" below).
///
/// ## Locking -- read before changing any `lock.withLock`
///
/// There are two locks and they are not interchangeable.
///
/// - `writerLock` serialises `store` and `discard` for their whole duration, including the
///   `NSCache` call. This is what makes "update `tracked`, then touch the cache" atomic with
///   respect to the other writer; without it a `discard` between a `store`'s two steps leaves a
///   cached entry with no tracked key (undercount) or a tracked key with no entry (leak).
/// - `trackedLock` guards only the `tracked` dictionary and is NEVER held across an `NSCache`
///   call. The eviction delegate runs synchronously on the thread that called `setObject` or
///   `removeObject`, and may also run on a memory-pressure thread. The delegate therefore takes
///   `trackedLock` only, so it can neither re-enter a lock its own caller holds (a hard
///   self-deadlock on a non-recursive `NSLock`, the first time the count limit is reached) nor
///   wait on a lock whose holder is waiting on `NSCache`'s internal lock.
///
/// Do NOT "tidy" this into one lock around both statements, and do NOT make the delegate take
/// `writerLock`. Alternatives rejected: a single `NSRecursiveLock` held across the cache calls
/// (fixes same-thread re-entry but can invert with `NSCache`'s internal lock when the delegate
/// fires from another thread, which cannot be ruled out from outside Foundation); dropping
/// `tracked` (`NSCache` cannot be counted or enumerated); accounting only in the delegate
/// (a store that evicts nothing is never reported, so `store` must record anyway).
final class TransactionEvidenceCache<Entry: TransactionCacheEntry>: NSObject, NSCacheDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init(countLimit: Int) {
        super.init()
        cache.countLimit = countLimit
        cache.delegate = self
    }

    // MARK: Internal

    /// Keys currently stored. Exact while no writer is mid-flight; see the type documentation.
    var count: Int {
        trackedLock.withLock { tracked.count }
    }

    /// Whether the cache holds nothing. Asks the tracked store directly rather than comparing
    /// `count`: the project enables SwiftFormat's `isEmpty` rule, which rewrites `count == 0`
    /// at call sites, and SwiftLint's `empty_count` rejects that inside an `isEmpty` body.
    var isEmpty: Bool {
        trackedLock.withLock { tracked.isEmpty }
    }

    func entry(for id: UUID) -> Entry? {
        cache.object(forKey: id as NSUUID)
    }

    func store(_ entry: Entry) {
        let id = entry.cacheID
        let identity = ObjectIdentifier(entry)
        writerLock.withLock {
            // Re-storing the same object would make `NSCache` report the "replaced" old value,
            // which is the live one, and the delegate would clear a key that is still cached.
            if cache.object(forKey: id as NSUUID) === entry {
                return
            }
            trackedLock.withLock { tracked[id] = identity }
            cache.setObject(entry, forKey: id as NSUUID)
        }
    }

    /// Drops the entries for `ids` and returns how many were actually held. Ids that were never
    /// cached, or were already evicted, are ignored.
    @discardableResult
    func discard(_ ids: some Sequence<UUID>) -> Int {
        var removed = 0
        writerLock.withLock {
            for id in ids {
                if trackedLock.withLock({ tracked.removeValue(forKey: id) != nil }) {
                    removed += 1
                }
                cache.removeObject(forKey: id as NSUUID)
            }
        }
        return removed
    }

    /// Runs inside `store`/`discard` on their thread, or on any thread under memory pressure.
    /// Takes `trackedLock` only -- never `writerLock`. See the type documentation.
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        guard let entry = object as? Entry else {
            return
        }
        trackedLock.withLock {
            // A replaced key evicts its old entry after the new one is tracked; only the entry
            // that is still the tracked one may clear the key.
            if tracked[entry.cacheID] == ObjectIdentifier(entry) {
                tracked.removeValue(forKey: entry.cacheID)
            }
        }
    }

    // MARK: Private

    private let cache = NSCache<NSUUID, Entry>()
    private let writerLock = NSLock()
    private let trackedLock = NSLock()
    private var tracked: [UUID: ObjectIdentifier] = [:]
}
