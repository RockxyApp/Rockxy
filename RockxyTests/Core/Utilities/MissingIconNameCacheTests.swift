import Foundation
@testable import Rockxy
import Testing

// Regression tests for the bounded negative icon-name cache shared by the three icon surfaces.

@Suite("Missing icon name cache")
struct MissingIconNameCacheTests {
    @Test("A flood of distinct client-controlled names stays inside the cap")
    func floodStaysBounded() {
        var cache = MissingIconNameCache()
        // A name the length of a User-Agent header with no `/` in it, which is what
        // `extractAppFromUserAgent` returns verbatim.
        let longName = String(repeating: "A", count: 4_096)
        for index in 0 ..< 5_000 {
            cache.insert("\(index)-\(longName)")
        }

        #expect(cache.count == MissingIconNameCache.maximumNames)
    }

    @Test("Eviction is FIFO, so the newest name is remembered and the oldest is forgotten")
    func evictsOldestFirst() {
        var cache = MissingIconNameCache()
        for index in 0 ... MissingIconNameCache.maximumNames {
            cache.insert("app-\(index)")
        }

        #expect(!cache.contains("app-0"))
        #expect(cache.contains("app-\(MissingIconNameCache.maximumNames)"))
        #expect(cache.count == MissingIconNameCache.maximumNames)
    }

    @Test("The stored key is truncated, so one absurd name cannot cost more than the cap allows")
    func truncatesStoredKeys() {
        var cache = MissingIconNameCache()
        let name = String(repeating: "B", count: 10_000)
        cache.insert(name)

        #expect(cache.contains(name))
        #expect(cache.contains(String(name.prefix(MissingIconNameCache.maximumNameLength))))
        #expect(cache.count == 1)
    }

    @Test("Re-inserting a known name neither grows the cache nor reorders eviction")
    func repeatedInsertIsIdempotent() {
        var cache = MissingIconNameCache()
        cache.insert("Chrome Helper")
        cache.insert("Chrome Helper")
        for index in 1 ..< MissingIconNameCache.maximumNames {
            cache.insert("app-\(index)")
        }

        #expect(cache.count == MissingIconNameCache.maximumNames)
        #expect(cache.contains("Chrome Helper"))

        cache.insert("one-too-many")

        #expect(!cache.contains("Chrome Helper"))
        #expect(cache.count == MissingIconNameCache.maximumNames)
    }
}
