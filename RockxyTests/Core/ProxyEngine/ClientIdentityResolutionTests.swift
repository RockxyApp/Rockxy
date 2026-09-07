import Darwin
import Foundation
@testable import Rockxy
import Testing

// MARK: - IntBox

private final class IntBox: @unchecked Sendable {
    // MARK: Internal

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    // MARK: Private

    private let lock = NSLock()
    private var value = 0
}

// MARK: - ProcessMapFixture

private final class ProcessMapFixture: @unchecked Sendable {
    // MARK: Internal

    func next(proxyPort: Int) -> [UInt16: String] {
        lock.lock()
        defer { lock.unlock() }
        requestedProxyPorts.append(proxyPort)
        let index = min(requestedProxyPorts.count - 1, snapshots.count - 1)
        return snapshots[index]
    }

    func requests() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return requestedProxyPorts
    }

    let snapshots: [[UInt16: String]] = [
        [51_001: "Existing App"],
        [51_001: "Existing App", 51_002: "New App"],
        [52_001: "Other Proxy App"],
    ]

    // MARK: Private

    private let lock = NSLock()
    private var requestedProxyPorts: [Int] = []
}

// MARK: - SlowProcessMapFixture

private final class SlowProcessMapFixture: @unchecked Sendable {
    // MARK: Internal

    func next(proxyPort _: Int) -> [UInt16: String] {
        lock.lock()
        requests += 1
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.1)
        return [53_001: "Burst App"]
    }

    func requestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    // MARK: Private

    private let lock = NSLock()
    private var requests = 0
}

private final class ConcurrentProxyMapFixture: @unchecked Sendable {
    func next(proxyPort: Int) -> [UInt16: String] {
        Thread.sleep(forTimeInterval: proxyPort == 8_888 ? 0.08 : 0.02)
        return proxyPort == 8_888 ? [53_101: "First Proxy App"] : [53_102: "Second Proxy App"]
    }
}

// MARK: - ClientIdentityResolutionTests

@Suite(.serialized)
struct ClientIdentityResolutionTests {
    // MARK: Internal

    // MARK: - Directional endpoint matching

    @Test("process map cache refreshes for a missing source port and a changed proxy port")
    func processMapCacheRefreshesForRequiredConnection() {
        let fixture = ProcessMapFixture()
        let resolver = ProcessResolver(
            processMapProvider: { proxyPort in
                fixture.next(proxyPort: proxyPort)
            },
            minimumRefreshInterval: 0
        )

        let initial = resolver.resolveProcesses(proxyPort: 8_888, requiring: [51_001])
        let cached = resolver.resolveProcesses(proxyPort: 8_888, requiring: [51_001])
        let refreshed = resolver.resolveProcesses(proxyPort: 8_888, requiring: [51_002])
        let otherProxy = resolver.resolveProcesses(proxyPort: 9_090, requiring: [52_001])

        #expect(initial[51_001] == "Existing App")
        #expect(cached[51_001] == "Existing App")
        #expect(refreshed[51_002] == "New App")
        #expect(otherProxy[52_001] == "Other Proxy App")
        #expect(fixture.requests() == [8_888, 8_888, 9_090])
    }

    @Test("missing process ports coalesce repeated lsof refreshes")
    func processMapCacheCoalescesMissingPorts() {
        let fixture = ProcessMapFixture()
        let resolver = ProcessResolver { proxyPort in
            fixture.next(proxyPort: proxyPort)
        }

        _ = resolver.resolveProcesses(proxyPort: 8_888, requiring: [51_001])
        let firstMiss = resolver.resolveProcesses(proxyPort: 8_888, requiring: [51_002])
        let repeatedMiss = resolver.resolveProcesses(proxyPort: 8_888, requiring: [51_003])

        #expect(firstMiss[51_002] == nil)
        #expect(repeatedMiss[51_003] == nil)
        #expect(fixture.requests() == [8_888])
    }

    @Test("first process-map burst coalesces while the initial query is in flight")
    func initialProcessMapBurstCoalesces() async {
        let fixture = SlowProcessMapFixture()
        let resolver = ProcessResolver { proxyPort in
            fixture.next(proxyPort: proxyPort)
        }

        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0 ..< 24 {
                group.addTask {
                    let result = await resolver.resolveProcessesAsync(proxyPort: 8_888, requiring: [53_001])
                    return result[53_001] == "Burst App"
                }
            }

            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(fixture.requestCount() == 1)
        #expect(results.allSatisfy { $0 })
    }

    @Test("concurrent proxy ports retain independent process maps")
    func concurrentProxyPortsDoNotOverwriteEachOther() async {
        let fixture = ConcurrentProxyMapFixture()
        let resolver = ProcessResolver(
            processMapProvider: { proxyPort in fixture.next(proxyPort: proxyPort) },
            minimumRefreshInterval: 0
        )

        async let first = resolver.resolveProcessesAsync(proxyPort: 8_888, requiring: [53_101])
        async let second = resolver.resolveProcessesAsync(proxyPort: 9_090, requiring: [53_102])
        let (firstResult, secondResult) = await (first, second)

        #expect(firstResult[53_101] == "First Proxy App")
        #expect(secondResult[53_102] == "Second Proxy App")
        #expect(resolver.resolveProcesses(proxyPort: 8_888)[53_101] == "First Proxy App")
        #expect(resolver.resolveProcesses(proxyPort: 9_090)[53_102] == "Second Proxy App")
    }

    @Test("matches a local client to its owning pid via exact source endpoint")
    func matchesLocalClient() {
        let records = [
            ProxyConnectionRecord(
                pid: 4_242, command: "curl",
                sourceHost: "127.0.0.1", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
            // Proxy's own reverse-accepted socket (source is the proxy port) — must be ignored.
            ProxyConnectionRecord(
                pid: 999, command: "Rockxy",
                sourceHost: "127.0.0.1", sourcePort: 9_090,
                destHost: "127.0.0.1", destPort: 54_321
            ),
        ]
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        let pid = ClientConnectionMatcher.matchingPID(records: records, descriptor: descriptor, excludePID: 999)
        #expect(pid == 4_242)
    }

    @Test("remote client source is never matched to an application")
    func remoteClientNotMatched() {
        let records = [
            ProxyConnectionRecord(
                pid: 4_242, command: "curl",
                sourceHost: "192.168.1.50", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
        ]
        let descriptor = makeDescriptor(clientHost: "192.168.1.50", clientPort: 54_321, proxyPort: 9_090)
        #expect(ClientConnectionMatcher.matchingPID(records: records, descriptor: descriptor, excludePID: 999) == nil)
    }

    @Test("proxy's own pid is excluded from matching")
    func excludesOwnPID() {
        let records = [
            ProxyConnectionRecord(
                pid: 999, command: "Rockxy",
                sourceHost: "127.0.0.1", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
        ]
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        #expect(ClientConnectionMatcher.matchingPID(records: records, descriptor: descriptor, excludePID: 999) == nil)
    }

    @Test("ambiguous source-port matches decline rather than guess")
    func ambiguousDeclines() {
        let records = [
            ProxyConnectionRecord(
                pid: 1, command: "a",
                sourceHost: "127.0.0.1", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
            ProxyConnectionRecord(
                pid: 2, command: "b",
                sourceHost: "127.0.0.1", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
        ]
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        #expect(ClientConnectionMatcher.matchingPID(records: records, descriptor: descriptor, excludePID: 999) == nil)
    }

    // MARK: - Snapshot freshness / coalescing

    @Test("a snapshot started after accept is reused for a later lookup with the same accept time")
    func freshSnapshotReused() async {
        let collections = IntBox()
        let nowBox = IntBox()
        let times: [UInt64] = [2_000, 4_000]
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                _ = collections.next()
                return [Self.matchingRecord]
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            now: { DispatchTime(uptimeNanoseconds: times[min(nowBox.next(), times.count - 1)]) },
            excludePID: 999
        )

        let descriptor = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 1_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        _ = await resolver.resolveIdentity(descriptor: descriptor)
        _ = await resolver.resolveIdentity(descriptor: descriptor)

        #expect(collections.count() == 1)
    }

    @Test("a stale snapshot forces a fresh collection")
    func staleSnapshotRecollected() async {
        let collections = IntBox()
        let nowBox = IntBox()
        let times: [UInt64] = [2_000, 4_000]
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                _ = collections.next()
                return [Self.matchingRecord]
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            now: { DispatchTime(uptimeNanoseconds: times[min(nowBox.next(), times.count - 1)]) },
            excludePID: 999
        )

        let first = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 1_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        _ = await resolver.resolveIdentity(descriptor: first)

        // Accepted after the first collection started (2_000) ⇒ not fresh ⇒ recollect.
        let second = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 3_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        _ = await resolver.resolveIdentity(descriptor: second)

        #expect(collections.count() == 2)
    }

    @Test("source-port reuse after a snapshot cannot inherit the previous process identity")
    func sourcePortReuseResolvesFreshIdentity() async {
        let collections = IntBox()
        let nowBox = IntBox()
        let firstIdentity = ClientApplicationIdentity.bundle(
            identifier: "com.example.First",
            displayName: "First"
        )
        let secondIdentity = ClientApplicationIdentity.bundle(
            identifier: "com.example.Second",
            displayName: "Second"
        )
        let snapshots = [
            [Self.record(pid: 101, command: "first", sourcePort: 54_321)],
            [Self.record(pid: 202, command: "second", sourcePort: 54_321)],
        ]
        let times: [UInt64] = [2_000, 4_000]
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                snapshots[min(collections.next(), snapshots.count - 1)]
            },
            identityProvider: { pid, _ in
                pid == 101 ? firstIdentity : secondIdentity
            },
            now: { DispatchTime(uptimeNanoseconds: times[min(nowBox.next(), times.count - 1)]) },
            excludePID: 999
        )

        let first = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 1_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        let second = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 3_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )

        #expect(await resolver.resolveIdentity(descriptor: first) == firstIdentity)
        #expect(await resolver.resolveIdentity(descriptor: second) == secondIdentity)
        #expect(collections.count() == 2)
    }

    @Test("concurrent accepts coalesce into one bounded connection-table collection")
    func concurrentAcceptsCoalesce() async {
        let collections = IntBox()
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                _ = collections.next()
                return [Self.matchingRecord]
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            now: { DispatchTime(uptimeNanoseconds: 10_000) },
            coalescingDelay: .milliseconds(20),
            excludePID: 999
        )
        let first = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 1_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        let second = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 2_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )

        async let firstIdentity = resolver.resolveIdentity(descriptor: first)
        async let secondIdentity = resolver.resolveIdentity(descriptor: second)
        let identities = await [firstIdentity, secondIdentity]

        #expect(identities.allSatisfy { $0 == Self.sampleIdentity })
        #expect(collections.count() == 1)
    }

    @Test("high-traffic local accepts stay identity-correct while sharing one bounded snapshot")
    func highTrafficAcceptsStayBounded() async {
        let connectionCount = 256
        let collections = IntBox()
        let records = (0 ..< connectionCount).map { index in
            Self.record(
                pid: Int32(10_000 + index),
                command: "client-\(index)",
                sourcePort: UInt16(40_000 + index)
            )
        }
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                _ = collections.next()
                return records
            },
            identityProvider: { pid, command in
                ClientApplicationIdentity.bundle(
                    identifier: "com.example.\(pid)",
                    displayName: command
                )
            },
            now: { DispatchTime(uptimeNanoseconds: 1_000_000) },
            coalescingDelay: .milliseconds(20),
            excludePID: 999
        )

        let identities = await withTaskGroup(
            of: ClientApplicationIdentity?.self,
            returning: [ClientApplicationIdentity?].self
        ) { group in
            for index in 0 ..< connectionCount {
                let descriptor = makeDescriptor(
                    acceptedAt: DispatchTime(uptimeNanoseconds: UInt64(index + 1)),
                    clientHost: "127.0.0.1",
                    clientPort: UInt16(40_000 + index),
                    proxyPort: 9_090
                )
                group.addTask {
                    await resolver.resolveIdentity(descriptor: descriptor)
                }
            }

            var resolved: [ClientApplicationIdentity?] = []
            resolved.reserveCapacity(connectionCount)
            for await identity in group {
                resolved.append(identity)
            }
            return resolved
        }

        let identifiers = Set(identities.compactMap { $0?.identifier })
        #expect(identities.count == connectionCount)
        #expect(identifiers.count == connectionCount)
        #expect(collections.count() == 1)
    }

    // MARK: - Resolution outcomes

    @Test("resolver returns the provided identity for a matched connection")
    func resolvesIdentity() async {
        let resolver = makeResolver(records: [Self.matchingRecord])
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        let identity = await resolver.resolveIdentity(descriptor: descriptor)
        #expect(identity == Self.sampleIdentity)
    }

    @Test("connection handle can resolve eagerly before a transaction is emitted")
    func handleResolvesEagerly() async throws {
        let resolver = makeResolver(records: [Self.matchingRecord])
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        let handle = ClientIdentityHandle(descriptor: descriptor, resolver: resolver)

        handle.startResolution()
        try await Task.sleep(for: .milliseconds(50))

        #expect(handle.currentIdentity == Self.sampleIdentity)
    }

    @Test("connection handle backfills an identity that resolves after the decision deadline")
    func handleBackfillsLateIdentity() async throws {
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                Thread.sleep(forTimeInterval: 1.0)
                return [Self.matchingRecord]
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            excludePID: 999
        )
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        let handle = ClientIdentityHandle(descriptor: descriptor, resolver: resolver)

        #expect(await handle.awaitIdentity() == nil)
        try await Task.sleep(for: .milliseconds(300))

        #expect(handle.currentIdentity == Self.sampleIdentity)
    }

    @Test("remote descriptor short-circuits without collecting the table")
    func remoteShortCircuits() async {
        let collections = IntBox()
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in _ = collections.next()
                return []
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            excludePID: 999
        )
        let descriptor = makeDescriptor(clientHost: "10.0.0.9", clientPort: 54_321, proxyPort: 9_090)
        let identity = await resolver.resolveIdentity(descriptor: descriptor)
        #expect(identity == nil)
        #expect(collections.count() == 0)
    }

    @Test("empty table (timeout / no match) resolves to nil")
    func timeoutResolvesNil() async {
        let resolver = makeResolver(records: [])
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        #expect(await resolver.resolveIdentity(descriptor: descriptor) == nil)
    }

    @Test("production lsof lookup resolves a real local child process")
    func resolvesRealLocalChildProcess() async throws {
        let fixture = try LocalChildConnectionFixture.start()
        defer { fixture.stop() }
        let descriptor = makeDescriptor(
            acceptedAt: DispatchTime.now(),
            clientHost: "127.0.0.1",
            clientPort: fixture.clientSourcePort,
            proxyPort: fixture.proxyPort
        )
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { proxyPort, deadline in
                ProcessResolver.runLsofConnectionTable(proxyPort: proxyPort, deadline: deadline)
            },
            identityProvider: { pid, command in
                ProcessResolver.applicationIdentity(forPID: pid, command: command)
            },
            timeout: .seconds(2),
            excludePID: getpid()
        )

        let identity = await resolver.resolveIdentity(descriptor: descriptor)

        #expect(identity != nil)
        #expect(identity?.kind == .executable)
        #expect(identity?.identifier.hasPrefix("exec:") == true)
        #expect(identity?.displayName == "nc")
    }

    // MARK: - lsof parsing

    @Test("parseConnectionTable parses IPv4 and IPv6 directional records")
    func parsesConnectionTable() {
        let output = """
        p4242
        ccurl
        n127.0.0.1:54321->127.0.0.1:9090
        p777
        cChrome
        n[::1]:60000->[::1]:9090
        """
        let records = ProcessResolver.parseConnectionTable(output)
        #expect(records.count == 2)
        #expect(records[0].pid == 4_242)
        #expect(records[0].sourcePort == 54_321)
        #expect(records[0].destPort == 9_090)
        #expect(records[1].pid == 777)
        #expect(records[1].sourceHost == "::1")
        #expect(records[1].sourcePort == 60_000)
        #expect(records[1].destPort == 9_090)
    }

    @Test("pid identity validation accepts truncated names and rejects recycled processes")
    func commandValidationRejectsPIDReuse() {
        #expect(ProcessResolver.commandMatchesExecutable(
            command: "Electron H",
            executablePath: "/Applications/Editor.app/Contents/Frameworks/Electron Helper (Renderer)"
        ))
        #expect(ProcessResolver.commandMatchesExecutable(
            command: "python3",
            executablePath: "/usr/local/bin/python3.12"
        ))
        #expect(!ProcessResolver.commandMatchesExecutable(
            command: "old-client",
            executablePath: "/Applications/NewClient.app/Contents/MacOS/new-client"
        ))
    }

    // MARK: - Transaction stamping

    @Test("stamping callback attaches identity and clientApp without overriding existing values")
    func stampingCallback() {
        let handle = ClientIdentityHandle(
            descriptor: makeDescriptor(clientHost: "127.0.0.1", clientPort: 1, proxyPort: 9_090),
            resolver: makeResolver(records: [])
        )
        // No stamping when identity is unresolved (handle currentIdentity is nil).
        let unstamped = makeTransaction()
        ProxyServer.makeIdentityStampingCallback(handle: handle, downstream: { _ in })(unstamped)
        #expect(unstamped.clientApplicationIdentity == nil)

        // A pre-set clientApp is preserved even if identity would supply one.
        let preset = makeTransaction()
        preset.clientApp = "Existing"
        ProxyServer.makeIdentityStampingCallback(handle: nil, downstream: { _ in })(preset)
        #expect(preset.clientApp == "Existing")
    }

    // MARK: Private

    private static let matchingRecord = ProxyConnectionRecord(
        pid: 4_242, command: "curl",
        sourceHost: "127.0.0.1", sourcePort: 54_321,
        destHost: "127.0.0.1", destPort: 9_090
    )

    private static let sampleIdentity = ClientApplicationIdentity.executable(
        normalizedPath: "/usr/bin/curl",
        displayName: "curl"
    )

    private static func record(pid: Int32, command: String, sourcePort: UInt16) -> ProxyConnectionRecord {
        ProxyConnectionRecord(
            pid: pid,
            command: command,
            sourceHost: "127.0.0.1",
            sourcePort: sourcePort,
            destHost: "127.0.0.1",
            destPort: 9_090
        )
    }

    private func makeResolver(records: [ProxyConnectionRecord]) -> ClientIdentityResolver {
        ClientIdentityResolver(
            connectionTableProvider: { _, _ in records },
            identityProvider: { _, _ in Self.sampleIdentity },
            excludePID: 999
        )
    }

    private func makeDescriptor(
        acceptedAt: DispatchTime = DispatchTime(uptimeNanoseconds: 1_000),
        clientHost: String?,
        clientPort: UInt16?,
        proxyPort: Int
    )
        -> ProxyConnectionDescriptor
    {
        ProxyConnectionDescriptor(
            acceptedAt: acceptedAt,
            clientHost: clientHost,
            clientPort: clientPort,
            proxyHost: "127.0.0.1",
            proxyPort: proxyPort
        )
    }

    private func makeTransaction() -> HTTPTransaction {
        HTTPTransaction(
            request: HTTPRequestData(
                method: "GET",
                url: URL(string: "https://example.com/")!,
                httpVersion: "1.1",
                headers: [],
                body: nil,
                contentType: nil
            ),
            state: .completed
        )
    }
}

// MARK: - LocalChildConnectionFixture

private struct LocalChildConnectionFixture {
    // MARK: Lifecycle

    static func start() throws -> LocalChildConnectionFixture {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw FixtureError.socket("Unable to create listener socket.")
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(listener, 1) == 0 else {
            Darwin.close(listener)
            throw FixtureError.socket("Unable to bind local listener socket.")
        }

        var listenerAddress = sockaddr_in()
        var listenerLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &listenerAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listener, $0, &listenerLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(listener)
            throw FixtureError.socket("Unable to inspect local listener port.")
        }
        let proxyPort = Int(UInt16(bigEndian: listenerAddress.sin_port))

        let input = Pipe()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        child.arguments = ["127.0.0.1", String(proxyPort)]
        child.standardInput = input
        child.standardOutput = Pipe()
        child.standardError = Pipe()
        do {
            try child.run()
        } catch {
            Darwin.close(listener)
            throw error
        }

        var listenerPoll = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard Darwin.poll(&listenerPoll, 1, 2_000) > 0 else {
            child.terminate()
            child.waitUntilExit()
            Darwin.close(listener)
            throw FixtureError.socket("Local child did not connect before the deadline.")
        }

        var peerAddress = sockaddr_in()
        var peerLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let accepted = withUnsafeMutablePointer(to: &peerAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.accept(listener, $0, &peerLength)
            }
        }
        guard accepted >= 0 else {
            child.terminate()
            Darwin.close(listener)
            throw FixtureError.socket("Unable to accept local child connection.")
        }

        return LocalChildConnectionFixture(
            listenerFD: listener,
            acceptedFD: accepted,
            child: child,
            input: input,
            clientSourcePort: UInt16(bigEndian: peerAddress.sin_port),
            proxyPort: proxyPort
        )
    }

    // MARK: Internal

    let listenerFD: Int32
    let acceptedFD: Int32
    let child: Process
    let input: Pipe
    let clientSourcePort: UInt16
    let proxyPort: Int

    func stop() {
        try? input.fileHandleForWriting.close()
        if child.isRunning {
            child.terminate()
            child.waitUntilExit()
        }
        Darwin.close(acceptedFD)
        Darwin.close(listenerFD)
    }

    // MARK: Private

    private enum FixtureError: Error {
        case socket(String)
    }
}
