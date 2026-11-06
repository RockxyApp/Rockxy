import Darwin
import Foundation
import Testing

@Suite("IsolatedDefaultsSuite")
struct IsolatedDefaultsSuiteTests {
    // MARK: Naming

    @Test("Minted names carry the namespace, the owning pid and a UUID")
    func mintedNameShape() {
        let name = IsolatedDefaultsSuite.uniqueName(prefix: "Some.Prefix-", pid: 4_242)
        defer { IsolatedDefaultsSuite.removeOwnSuites(only: [name]) }

        #expect(name.hasPrefix("rockxy-test.Some.Prefix.4242."))
        #expect(IsolatedDefaultsSuite.ownerPID(ofSuiteName: name) == 4_242)
    }

    @Test("Names that merely resemble a generated suite are never recognised")
    func lookAlikesAreRejected() {
        let uuid = UUID().uuidString
        let notOurs = [
            "com.amunx.rockxy.community",
            "com.amunx.Rockxy",
            "com.rockxy.qa.soak3.community",
            "rockxy-test",
            "rockxy-test.\(uuid)",
            "rockxy-test.Prefix.\(uuid)",
            "rockxy-test.Prefix.12345678.\(uuid)",
            "rockxy-test.Prefix.12.not-a-uuid",
            "rockxy-test..12.\(uuid)",
            "other-test.Prefix.12.\(uuid)",
            "AppLanguagePreferenceTests.\(uuid)",
            "com.amunx.tracexy.tests.\(uuid)",
        ]
        for name in notOurs {
            #expect(IsolatedDefaultsSuite.ownerPID(ofSuiteName: name) == nil, "\(name)")
        }
        #expect(IsolatedDefaultsSuite.ownerPID(ofHeaderColumnsName: "RockxyTests.HeaderColumns.12345678") == nil)
        #expect(IsolatedDefaultsSuite.ownerPID(ofHeaderColumnsName: "RockxyTests.HeaderColumns.abc") == nil)
        #expect(IsolatedDefaultsSuite.ownerPID(ofHeaderColumnsName: "RockxyTests.HeaderColumns.4242") == 4_242)
    }

    // MARK: Sweep

    @Test("The sweep removes only generated files owned by a dead process")
    func sweepIsScopedToDeadOwners() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsolatedDefaultsSuiteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let deadPID: Int32 = 91_001
        let livePID: Int32 = 91_002
        let ownPID: Int32 = 91_003
        let uuid = UUID().uuidString
        let stale = [
            "rockxy-test.Foo.\(deadPID).\(uuid)",
            "rockxy-test.Foo.Bar.\(deadPID).\(UUID().uuidString)",
            "RockxyTests.HeaderColumns.\(deadPID)",
        ]
        let keep = [
            "rockxy-test.Foo.\(livePID).\(uuid)",
            "rockxy-test.Foo.\(ownPID).\(uuid)",
            "RockxyTests.HeaderColumns.\(livePID)",
            // Real or unrelated domains, and every legacy shape: never matched.
            "com.amunx.rockxy.community",
            "com.amunx.Rockxy",
            "com.rockxy.qa.soak3.community",
            "com.apple.Safari",
            "AppLanguagePreferenceTests.\(uuid)",
            "com.amunx.tracexy.tests.\(uuid)",
            "rockxy-test.Foo.12345678.\(uuid)",
            "rockxy-test.Foo.\(deadPID).not-a-uuid",
        ]
        for name in stale + keep {
            try Data("x".utf8).write(to: directory.appendingPathComponent("\(name).plist"))
        }
        try Data("x".utf8).write(to: directory.appendingPathComponent("rockxy-test.Foo.\(deadPID).\(uuid).txt"))

        let sweeper = IsolatedDefaultsSuite.Sweeper(
            directory: directory,
            ownPID: ownPID,
            isProcessAlive: { $0 == livePID || $0 == ownPID }
        )
        sweeper.sweepOnce()

        #expect(sweeper.removedFileCount == stale.count)
        for name in stale {
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(name).plist").path))
        }
        for name in keep {
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(name).plist").path))
        }
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("rockxy-test.Foo.\(deadPID).\(uuid).txt").path
        ))

        // A second call, even with a new stale file, does nothing: the sweep never runs mid-process.
        let late = directory.appendingPathComponent("rockxy-test.Late.\(deadPID).\(UUID().uuidString).plist")
        try Data("x".utf8).write(to: late)
        sweeper.sweepOnce()
        #expect(FileManager.default.fileExists(atPath: late.path))
    }

    @Test("A process that was killed leaves a file that the next run's sweep removes")
    func killedProcessFileIsSweptByNextRun() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsolatedDefaultsSuiteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A real child that has already exited gives a pid that is genuinely dead.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        let deadPID = child.processIdentifier
        #expect(!IsolatedDefaultsSuite.isProcessAlive(deadPID))

        let name = "rockxy-test.Crashed.\(deadPID).\(UUID().uuidString)"
        let file = directory.appendingPathComponent("\(name).plist")
        try Data("x".utf8).write(to: file)

        IsolatedDefaultsSuite.Sweeper(directory: directory).sweepOnce()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: Simulated run

    @Test("The deferred cleanup deletes the files it is given after its delay")
    func deferredRemovalDeletesFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsolatedDefaultsSuiteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rockxy-test.Deferred.1.\(UUID().uuidString).plist")
        try Data("x".utf8).write(to: file)

        IsolatedDefaultsSuite.scheduleDeferredRemoval(of: [file.path], delay: 1)
        #expect(FileManager.default.fileExists(atPath: file.path))

        let deadline = Date().addingTimeInterval(10)
        while FileManager.default.fileExists(atPath: file.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// `removePersistentDomain` leaves a 42-byte plist, and cfprefsd rewrites it about 8 s after
    /// a delete, so an immediate delete alone is undone. This is the real sequence every test
    /// that ends with `defer { removePersistentDomain }` produces, followed through until the
    /// write-back has had time to happen.
    @Test("A simulated run leaves no persistent domain behind in the real preferences directory")
    func simulatedRunLeavesNoDomain() async throws {
        let preferences = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let suites = (0 ..< 5).map { IsolatedDefaultsSuite.uniqueName(prefix: "IsolatedDefaultsSuiteTests-Run\($0)-") }
        for name in suites {
            let defaults = try #require(UserDefaults(suiteName: name))
            defaults.set("value", forKey: "key")
            defaults.synchronize()
            defaults.removePersistentDomain(forName: name)
        }

        // Emptying a domain is not removing it: the plist is still there.
        let present = IsolatedDefaultsSuite.ownFiles(in: preferences, pid: ownPID)
        for name in suites {
            #expect(present.contains("\(name).plist"))
        }

        let delay = 12
        IsolatedDefaultsSuite.removeOwnSuites(only: Set(suites), deferredDelay: delay)
        let immediately = IsolatedDefaultsSuite.ownFiles(in: preferences, pid: ownPID)
        for name in suites {
            #expect(!immediately.contains("\(name).plist"))
        }

        // Wait past the delayed cleanup, then require the files to be gone for good.
        try await Task.sleep(for: .seconds(delay + 4))
        let remaining = IsolatedDefaultsSuite.ownFiles(in: preferences, pid: ownPID)
        for name in suites {
            #expect(!remaining.contains("\(name).plist"), "\(name) survived the run")
        }
    }

    // MARK: Path safety

    @Test("A prefix that could escape the preferences directory is refused")
    func unsafePrefixesAreRefused() {
        let unsafe = [
            "a/b",
            "/abs",
            "a/../../../../tmp/x",
            "..",
            "a..b",
            "a..",
            "Name\u{0}Tail",
        ]
        for prefix in unsafe {
            #expect(!IsolatedDefaultsSuite.isPathSafe(prefix), "\(prefix.debugDescription)")
        }
        for prefix in ["Some.Prefix-", "IsolatedDefaultsSuiteTests-Run1-", "a.b", "Suite"] {
            #expect(IsolatedDefaultsSuite.isPathSafe(prefix), "\(prefix)")
        }
        // A name carrying a separator never parses as ours, even when the rest has our shape.
        let uuid = UUID().uuidString
        #expect(IsolatedDefaultsSuite.ownerPID(ofSuiteName: "rockxy-test.a/b.12.\(uuid)") == nil)
        #expect(IsolatedDefaultsSuite.ownerPID(ofSuiteName: "rockxy-test.a/../b.12.\(uuid)") == nil)
        #expect(IsolatedDefaultsSuite.ownerPID(ofSuiteName: "rockxy-test.a\u{0}b.12.\(uuid)") == nil)
    }

    @Test("removeOwnSuites ignores a registered name that does not parse as one of ours")
    func removeOwnSuitesIgnoresForeignNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsolatedDefaultsSuiteTests-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("prefs", isDirectory: true)
        let nested = directory.appendingPathComponent("rockxy-test.a", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Files a path built from a bad name would reach: one above `directory`, one below it.
        let outside = root.appendingPathComponent("sentinel.plist")
        let inside = nested.appendingPathComponent("b.12.\(UUID().uuidString).plist")
        try Data("x".utf8).write(to: outside)
        try Data("x".utf8).write(to: inside)

        let ours = IsolatedDefaultsSuite.uniqueName(prefix: "IsolatedDefaultsSuiteTests-Ours-")
        let ourFile = directory.appendingPathComponent("\(ours).plist")
        try Data("x".utf8).write(to: ourFile)

        let insideName = "rockxy-test.a/" + inside.deletingPathExtension().lastPathComponent
        let foreign = ["../sentinel", "sentinel", insideName, "com.apple.Safari"]
        for name in foreign {
            IsolatedDefaultsSuite.register(name)
        }

        IsolatedDefaultsSuite.removeOwnSuites(
            only: Set(foreign + [ours]),
            directory: directory,
            deferredRemoval: false
        )

        #expect(!FileManager.default.fileExists(atPath: ourFile.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(FileManager.default.fileExists(atPath: inside.path))
    }

    // MARK: Deferred child

    @Test("The deferred cleanup child is reaped rather than left as a zombie")
    func deferredChildIsReaped() async throws {
        let pid = try #require(IsolatedDefaultsSuite.scheduleDeferredRemoval(of: [], delay: 1))
        // A zombie still answers `kill(pid, 0)`; only a reaped child reports ESRCH.
        let deadline = Date().addingTimeInterval(10)
        while kill(pid, 0) == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    @Test("A failed spawn is reported as nil instead of crashing")
    func failedSpawnReturnsNil() {
        let pid = IsolatedDefaultsSuite.scheduleDeferredRemoval(
            of: [],
            delay: 1,
            executablePath: "/nonexistent/\(UUID().uuidString)"
        )
        #expect(pid == nil)
    }

    // MARK: Source guard

    @Test("No test mints a defaults suite from a bare UUID")
    func noBareUUIDSuiteNames() throws {
        let testsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let enumerator = try #require(FileManager.default.enumerator(at: testsRoot, includingPropertiesForKeys: nil))
        let literal = try NSRegularExpression(pattern: #""[^"\n]*\\\(UUID\(\)\.uuidString\)[^"\n]*""#)
        let context = try NSRegularExpression(pattern: #"[Ss]uite|[Dd]efaults|\bname\s*="#)

        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if ["IsolatedDefaultsSuite.swift", "IsolatedDefaultsSuiteTests.swift"].contains(url.lastPathComponent) {
                continue
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard literal.firstMatch(in: line, range: range) != nil,
                      context.firstMatch(in: line, range: range) != nil,
                      !line.contains("CommonName"), !line.contains("tmpName"), !line.contains("no-such-service") else
                {
                    continue
                }
                violations.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        #expect(
            violations.isEmpty,
            "Mint suite names with IsolatedDefaultsSuite.uniqueName(prefix:): \(violations.joined(separator: ", "))"
        )
    }
}
