import Foundation
@testable import Rockxy
import Testing

// MARK: - ScriptHookQueueAutoreleaseTests

// Regression tests for issue #416: a plugin's hooks hand JavaScriptCore wrappers back as
// autoreleased objects, each pinning a JS object graph. The plugin queue has to pop an
// autorelease pool per work item, or a busy plugin accumulates them for as long as its
// queue never runs dry.

@Suite(.serialized)
struct ScriptHookQueueAutoreleaseTests {
    @Test("Hook queue releases autoreleased objects after each work item, not when it drains")
    func hookQueueReleasesPerWorkItem() {
        let queue = ScriptRuntime.makeHookQueue(label: "test.hook.queue.autorelease")
        let counter = AutoreleaseCanary.Counter()
        let itemCount = 64
        let gate = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let aliveAtStart = LockedIntLog()

        // Hold the queue on its first item so every other item is already queued behind
        // it: the queue cannot run dry between them, which is the sustained-traffic case.
        queue.async { gate.wait() }
        for _ in 0 ..< itemCount {
            queue.async {
                aliveAtStart.append(counter.alive)
                AutoreleaseCanary.makeAutoreleased(counter: counter)
                done.signal()
            }
        }
        gate.signal()
        for _ in 0 ..< itemCount {
            done.wait()
        }
        queue.sync {}

        // With a pool per item, the previous item's canary is gone before the next starts.
        #expect(aliveAtStart.values.max() ?? .max <= 1)
        #expect(counter.alive == 0)
    }
}

// MARK: - AutoreleaseCanary

private final class AutoreleaseCanary: NSObject {
    // MARK: Lifecycle

    init(counter: Counter) {
        self.counter = counter
        super.init()
        counter.increment()
    }

    deinit {
        counter.decrement()
    }

    // MARK: Internal

    final class Counter: @unchecked Sendable {
        // MARK: Internal

        var alive: Int {
            lock.withLock { value }
        }

        func increment() {
            lock.withLock { value += 1 }
        }

        func decrement() {
            lock.withLock { value -= 1 }
        }

        // MARK: Private

        private let lock = NSLock()
        private var value = 0
    }

    /// Leaves one extra retain balanced by an autorelease, the way an Objective-C API
    /// returning a wrapper does, so the object lives until the enclosing pool pops.
    static func makeAutoreleased(counter: Counter) {
        let canary = AutoreleaseCanary(counter: counter)
        _ = Unmanaged.passUnretained(canary).retain().autorelease()
    }

    // MARK: Private

    private let counter: Counter
}

// MARK: - LockedIntLog

private final class LockedIntLog: @unchecked Sendable {
    // MARK: Internal

    var values: [Int] {
        lock.withLock { storage }
    }

    func append(_ value: Int) {
        lock.withLock { storage.append(value) }
    }

    // MARK: Private

    private let lock = NSLock()
    private var storage: [Int] = []
}
