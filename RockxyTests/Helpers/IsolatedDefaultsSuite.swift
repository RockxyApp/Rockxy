import Darwin
import Foundation

// MARK: - IsolatedDefaultsSuite

/// Single mint point for throwaway `UserDefaults` suites used by tests.
///
/// `UserDefaults(suiteName:)` persists `<suite>.plist` in `~/Library/Preferences`, and
/// `removePersistentDomain(forName:)` only EMPTIES that domain: a 42-byte `{ }` plist stays
/// behind forever. A `defer { removePersistentDomain }` therefore does not clean up, and a
/// name containing a bare `UUID()` leaks one file per use. Every mint goes through here.
///
/// Minted names have the shape `rockxy-test.<prefix>.<pid>.<UUID>`. That shape is the whole
/// safety contract of the sweeper: it embeds the owning process id, so a parallel test
/// process is never touched while it is alive, and it carries a reserved namespace no real
/// preference domain uses, so a sweep cannot match anything that is not test-generated.
///
/// Four layers keep a run from leaving a domain behind:
/// 1. At exit the process's own files are deleted, and a detached `sh` deletes them again
///    after `deferredRemovalDelay`. The second pass is essential, not belt and braces:
///    `removePersistentDomain` makes cfprefsd write its empty plist back some seconds
///    LATER (measured at about 8 s), so a delete performed at exit is undone after the
///    process is gone.
/// 2. The first mint in a process sweeps files whose owning pid is dead. This covers a
///    process that crashed or was killed (so no exit hook ran) and a detached `sh` that was
///    reaped with its session. Worst case, one run's files wait for the next run.
/// 3. `IsolatedDefaultsSuiteTests` pins that no test source mints a bare `UUID()` suite.
/// 4. Names live in a reserved namespace, so no sweep can match a real domain.
enum IsolatedDefaultsSuite {
    // MARK: Internal

    // MARK: - Sweeper

    /// Removes stale generated-suite files, at most once per instance. It only ever matches the
    /// reserved shapes above and skips any file whose owning process is still running.
    final class Sweeper: @unchecked Sendable {
        // MARK: Lifecycle

        init(
            directory: URL,
            ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
            isProcessAlive: @escaping @Sendable (Int32) -> Bool = { IsolatedDefaultsSuite.isProcessAlive($0) }
        ) {
            self.directory = directory
            self.ownPID = ownPID
            self.isProcessAlive = isProcessAlive
        }

        // MARK: Internal

        private(set) var removedFileCount = 0

        var hasSwept: Bool {
            lock.lock()
            defer { lock.unlock() }
            return swept
        }

        func sweepOnce() {
            lock.lock()
            defer { lock.unlock() }
            guard !swept else {
                return
            }
            swept = true
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for entry in entries where entry.hasSuffix(".plist") {
                let name = String(entry.dropLast(".plist".count))
                guard let pid = IsolatedDefaultsSuite.ownerPID(ofSuiteName: name)
                    ?? IsolatedDefaultsSuite.ownerPID(ofHeaderColumnsName: name),
                    pid != ownPID,
                    !isProcessAlive(pid) else
                {
                    continue
                }
                if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry))) != nil {
                    removedFileCount += 1
                }
            }
        }

        // MARK: Private

        private let directory: URL
        private let ownPID: Int32
        private let isProcessAlive: @Sendable (Int32) -> Bool
        private let lock = NSLock()
        private var swept = false
    }

    /// Reserved first component of every minted suite name.
    static let namespace = "rockxy-test"

    /// How long the detached cleanup waits. Must exceed cfprefsd's deferred write-back.
    ///
    /// The 8 s write-back figure is EMPIRICAL: one measurement on one machine, not independently
    /// reproduced and not a documented cfprefsd guarantee. 20 s is that figure with a wide margin.
    /// If cfprefsd is slower than that somewhere, the deferred pass runs before the write-back and
    /// is merely INEFFECTIVE, not unsafe: it only `rm -f`s absolute paths containing this
    /// (by then dead) pid, so it cannot touch anything else. The leftover empty plist is then
    /// removed by the next run's sweeper, because its owning pid is dead.
    static let deferredRemovalDelay = 20

    /// A fixed per-process domain minted by `HeaderColumnStore` while tests run.
    static let headerColumnsNamePrefix = "RockxyTests.HeaderColumns."

    /// Process-wide sweeper bound to the real preferences directory.
    static let shared = Sweeper(directory: preferencesDirectory)

    static func make(prefix: String) -> UserDefaults {
        let suiteName = uniqueName(prefix: prefix)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults suite \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Mints and registers a suite name without opening it, for call sites that need the name
    /// (to reopen the suite, or to pass to `removePersistentDomain`).
    ///
    /// The name becomes a file name under the preferences directory, so a prefix that could
    /// escape it is a programming error and fails loudly instead of being sanitised into a
    /// different name than the caller asked for. See `isPathSafe(_:)`.
    static func uniqueName(prefix: String, pid: Int32 = ProcessInfo.processInfo.processIdentifier) -> String {
        guard isPathSafe(prefix) else {
            preconditionFailure("Invalid isolated defaults suite prefix (path separator, NUL or '..'): \(prefix)")
        }
        shared.sweepOnce()
        var trimmed = Substring(prefix)
        while let last = trimmed.last, last == "-" || last == "." {
            trimmed = trimmed.dropLast()
        }
        let component = trimmed.isEmpty ? "Suite" : String(trimmed)
        let name = "\(namespace).\(component).\(pid).\(UUID().uuidString)"
        register(name)
        return name
    }

    /// Records a name so the exit hook removes it. Internal so tests can register names directly.
    static func register(_ suiteName: String) {
        lock.lock()
        suiteNames.insert(suiteName)
        // `HeaderColumnStore` opens one fixed per-pid domain when it detects it is under test;
        // claim it so the exit hook removes it too.
        suiteNames.insert("\(headerColumnsNamePrefix)\(ProcessInfo.processInfo.processIdentifier)")
        if !exitHookInstalled {
            exitHookInstalled = true
            atexit {
                IsolatedDefaultsSuite.removeOwnSuites()
            }
        }
        lock.unlock()
    }

    /// The pid embedded in a name `uniqueName` could have produced, else nil. The shape is
    /// `rockxy-test.<prefix>.<pid>.<UUID>`: reserved namespace, non-empty prefix, a pid of at
    /// most 7 digits, and a real UUID. Anything else is not ours.
    static func ownerPID(ofSuiteName name: String) -> Int32? {
        guard name.hasPrefix("\(namespace)."), isPathSafe(name) else {
            return nil
        }
        let parts = name.dropFirst(namespace.count + 1).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let uuid = parts.last, uuid.count == 36, UUID(uuidString: String(uuid)) != nil,
              parts.dropLast(2).allSatisfy({ !$0.isEmpty }) else
        {
            return nil
        }
        let pidText = parts[parts.count - 2]
        guard (1 ... 7).contains(pidText.count), pidText.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        return Int32(pidText)
    }

    /// True when `text` can be used as a single file-name component: no `/`, no NUL and no `..`.
    static func isPathSafe(_ text: String) -> Bool {
        !text.contains("/") && !text.unicodeScalars.contains("\0") && !text.contains("..")
    }

    /// The pid embedded in `RockxyTests.HeaderColumns.<pid>`, else nil.
    static func ownerPID(ofHeaderColumnsName name: String) -> Int32? {
        guard name.hasPrefix(headerColumnsNamePrefix) else {
            return nil
        }
        let tail = name.dropFirst(headerColumnsNamePrefix.count)
        guard (1 ... 7).contains(tail.count), tail.allSatisfy(\.isASCII), tail.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int32(tail)
    }

    static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Deletes this process's files now and again after `deferredRemovalDelay`. Also what the
    /// exit hook runs. `only` limits it to specific names so a test can exercise cleanup
    /// without touching suites other tests in the same process are still using.
    static func removeOwnSuites(
        only: Set<String>? = nil,
        directory: URL = preferencesDirectory,
        deferredRemoval: Bool = true,
        deferredDelay: Int = deferredRemovalDelay
    ) {
        lock.lock()
        let candidates = only.map { suiteNames.intersection($0) } ?? suiteNames
        suiteNames.subtract(candidates)
        lock.unlock()

        // Re-validate every name before it becomes a path, exactly as the sweep does, so the
        // delete path has the same guarantee: anything that does not parse as one of ours is
        // dropped and never deleted.
        let names = candidates.filter {
            ownerPID(ofSuiteName: $0) != nil || ownerPID(ofHeaderColumnsName: $0) != nil
        }

        let files = names.map { directory.appendingPathComponent("\($0).plist") }
        for (name, file) in zip(names, files) {
            UserDefaults(suiteName: name)?.synchronize()
            try? FileManager.default.removeItem(at: file)
        }
        if deferredRemoval, !files.isEmpty {
            scheduleDeferredRemoval(of: files.map(\.path), delay: deferredDelay)
        }
    }

    /// Spawns a detached `sh` that deletes `paths` after `delay` seconds.
    /// Only paths this process minted are ever passed here, and each is a separate argv entry,
    /// never interpolated into the script.
    ///
    /// Returns the child's pid, or nil when it could not be spawned. A failed spawn is not an
    /// error: the deferred pass simply does not happen and the next run's sweeper removes the
    /// leftover file, so it must never fail a test. The child is reaped asynchronously once it
    /// exits, so a long-lived test host does not accumulate a zombie, and nothing waits for it.
    @discardableResult
    static func scheduleDeferredRemoval(
        of paths: [String],
        delay: Int = deferredRemovalDelay,
        executablePath: String = "/bin/sh"
    )
        -> pid_t?
    {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // New session: the cleanup must outlive the test host and its process group.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        let script = "sleep \(delay); for f in \"$@\"; do rm -f -- \"$f\"; done"
        let arguments = ["sh", "-c", script, "sh"] + paths
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        guard posix_spawn(&pid, executablePath, nil, &attributes, argv, environ) == 0 else {
            return nil
        }
        reapAsynchronously(pid)
        return pid
    }

    /// Every generated-suite file in `directory` owned by the given pid.
    static func ownFiles(in directory: URL, pid: Int32 = ProcessInfo.processInfo.processIdentifier) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return entries.filter { entry in
            guard entry.hasSuffix(".plist") else {
                return false
            }
            let name = String(entry.dropLast(".plist".count))
            return ownerPID(ofSuiteName: name) == pid || ownerPID(ofHeaderColumnsName: name) == pid
        }.sorted()
    }

    // MARK: Private

    private static let lock = NSLock()
    private static var suiteNames: Set<String> = []
    private static var exitHookInstalled = false

    private static var preferencesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
    }

    /// Collects the exit status of a spawned child without blocking the caller. The child is
    /// only our child until it exits, so an exit event is the cheapest moment to `waitpid` it.
    /// `WNOHANG` guarantees that handler can never stall even if the event were spurious.
    private static func reapAsynchronously(_ pid: pid_t) {
        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [source] in
            var status: Int32 = 0
            _ = waitpid(pid, &status, WNOHANG)
            source.cancel()
        }
        source.resume()
    }
}
