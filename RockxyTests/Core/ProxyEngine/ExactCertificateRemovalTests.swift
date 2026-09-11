import Foundation
@testable import Rockxy
import Testing

// Drives the real `HelperConnection.removeRootCertificate(matching:)` wrapper — its capability
// probe, its capability gate, its cancellation check, its send gate, and its connection teardown —
// against a fake helper. Nothing here reaches a privileged helper, the System keychain, or a trust
// setting: the session the wrapper runs on is injected, so no NSXPCConnection is ever created.

// MARK: - ExactCertificateRemovalTests

@MainActor
struct ExactCertificateRemovalTests {
    // MARK: Internal

    @Test("a protocol 1 helper is never sent the exact-removal selector, whatever its build")
    func protocolOneNeverReceivesTheSelector() async {
        let fake = FakeHelperProxy()
        // A shipped copy of Rockxy embeds a helper at this build that still speaks protocol 1.
        fake.info = HelperInfo(binaryVersion: "9.9.9", buildNumber: 999_999, protocolVersion: 1)
        let teardowns = TeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])

        let failure = await #expect(throws: HelperConnectionError.self) {
            try await connection.removeRootCertificate(matching: Self.sampleDER)
        }

        #expect(failure?.errorDescription == HelperConnectionError.certRemovalUnsupported.errorDescription)
        #expect(fake.removalPayloads.isEmpty)
        #expect(fake.legacyRemovalCount == 0)
        #expect(teardowns.count == 1)
    }

    @Test("a protocol 2 helper receives exactly the supplied bytes, once")
    func protocolTwoReceivesTheExactBytes() async throws {
        let fake = FakeHelperProxy()
        let teardowns = TeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])

        try await connection.removeRootCertificate(matching: Self.sampleDER)

        #expect(fake.removalPayloads == [Self.sampleDER])
        #expect(fake.infoRequestCount == 1)
        #expect(fake.legacyRemovalCount == 0)
        #expect(teardowns.count == 1)
    }

    @Test("cancelling during the capability probe sends no removal")
    func cancellationDuringProbeSendsNothing() async {
        let fake = FakeHelperProxy()
        fake.defersInfoReply = true
        let teardowns = TeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])

        let task = Task { try await connection.removeRootCertificate(matching: Self.sampleDER) }
        let probeStarted = await waitUntil { fake.hasPendingInfoReply }
        #expect(probeStarted)

        task.cancel()
        // The helper answers the probe anyway: the wrapper must still stop at its own check.
        #expect(fake.answerPendingInfo())

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(fake.removalPayloads.isEmpty)
        #expect(teardowns.count == 1)
    }

    @Test("a transport failure between the probe and the send prevents the removal")
    func failureBetweenProbeAndSendSendsNothing() async {
        let fake = FakeHelperProxy()
        fake.defersInfoReply = true
        let teardowns = TeardownCounter()
        let session = HelperCertificateSession(proxy: fake) { teardowns.record() }
        let connection = Self.connection(returning: [session])

        let task = Task { try await connection.removeRootCertificate(matching: Self.sampleDER) }
        let probeStarted = await waitUntil { fake.hasPendingInfoReply }
        #expect(probeStarted)

        // The probe is answered, then the connection drops before the wrapper resumes. Both run
        // on the main actor without an await in between, so the ordering is exact.
        #expect(fake.answerPendingInfo())
        session.router.deliver(SessionFailure())

        let failure = await #expect(throws: HelperConnectionError.self) {
            try await task.value
        }
        #expect(failure?.errorDescription?.contains("remove root certificate") == true)
        #expect(fake.removalPayloads.isEmpty)
        #expect(teardowns.count == 1)
    }

    @Test("a reply that arrives after the timeout completes the call only once")
    func lateReplyAfterTimeoutCompletesOnce() async {
        let fake = FakeHelperProxy()
        fake.defersRemovalReply = true
        let teardowns = TeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])
        connection.certificateRequestTimeout = .milliseconds(100)

        let failure = await #expect(throws: HelperConnectionError.self) {
            try await connection.removeRootCertificate(matching: Self.sampleDER)
        }

        #expect(failure?.errorDescription == HelperConnectionError.xpcTimeout.errorDescription)
        // The message was committed before the timer fired, so it is honestly still in flight —
        // the timeout reports that the app stopped waiting, not that nothing was sent.
        #expect(fake.removalPayloads == [Self.sampleDER])
        #expect(teardowns.count == 1)

        // Resuming the continuation twice would trap, so surviving this line is the assertion.
        #expect(fake.answerPendingRemoval(success: true, message: nil))
    }

    @Test("a poisoned session does not poison the next call")
    func poisonIsScopedToOneSession() async throws {
        let fake = FakeHelperProxy()
        let teardowns = TeardownCounter()
        let poisoned = HelperCertificateSession(proxy: fake) { teardowns.record() }
        poisoned.router.deliver(SessionFailure())
        let healthy = HelperCertificateSession(proxy: fake) { teardowns.record() }
        let connection = Self.connection(returning: [poisoned, healthy])

        await #expect(throws: HelperConnectionError.self) {
            try await connection.removeRootCertificate(matching: Self.sampleDER)
        }
        #expect(fake.infoRequestCount == 0)
        #expect(fake.removalPayloads.isEmpty)

        try await connection.removeRootCertificate(matching: Self.sampleDER)

        #expect(fake.infoRequestCount == 1)
        #expect(fake.removalPayloads == [Self.sampleDER])
        #expect(teardowns.count == 2)
    }

    @Test("a helper that reports a failure ends the call and still tears the session down")
    func helperFailureTearsDownTheSession() async {
        let fake = FakeHelperProxy()
        fake.removalSucceeds = false
        fake.removalMessage = "keychain is locked"
        let teardowns = TeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])

        let failure = await #expect(throws: HelperConnectionError.self) {
            try await connection.removeRootCertificate(matching: Self.sampleDER)
        }

        #expect(failure?.errorDescription?.contains("keychain is locked") == true)
        #expect(teardowns.count == 1)
    }

    // MARK: Private

    private static let sampleDER = Data([0x30, 0x82, 0x01, 0x02, 0xAB, 0xCD])

    /// A connection whose removal sessions come from `sessions`, in order.
    private static func connection(returning sessions: [HelperCertificateSession]) -> HelperConnection {
        let queue = SessionQueue(sessions)
        let connection = HelperConnection()
        connection.certificateSessionProvider = { try queue.next() }
        // Bounded, but far longer than any parked reply in these tests needs: a test that drives a
        // timeout shortens the timer it is testing itself.
        connection.certificateProbeTimeout = .seconds(5)
        connection.certificateRequestTimeout = .seconds(5)
        return connection
    }

    /// Yields until `condition` holds, so the wrapper's own main-actor work can make progress.
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 5_000 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

// MARK: - SessionQueue

/// Hands out the prepared sessions in order and fails loudly if the wrapper asks for one more.
private final class SessionQueue: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ sessions: [HelperCertificateSession]) {
        remaining = sessions
    }

    // MARK: Internal

    func next() throws -> HelperCertificateSession {
        try lock.withLock {
            guard !remaining.isEmpty else {
                throw SessionFailure()
            }
            return remaining.removeFirst()
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var remaining: [HelperCertificateSession]
}

// MARK: - SessionFailure

private struct SessionFailure: Error {}

// MARK: - TeardownCounter

private final class TeardownCounter: @unchecked Sendable {
    // MARK: Internal

    var count: Int {
        lock.withLock { value }
    }

    func record() {
        lock.withLock { value += 1 }
    }

    // MARK: Private

    private let lock = NSLock()
    private var value = 0
}

// MARK: - FakeHelperProxy

/// A stand-in for the privileged helper.
///
/// It records what the wrapper actually sent and lets a test decide when — or whether — a reply
/// arrives. Configuration is set before a call starts; the recorded traffic is lock-guarded because
/// a reply may be answered from any thread.
private final class FakeHelperProxy: NSObject, RockxyHelperProtocol, @unchecked Sendable {
    // MARK: Internal

    /// What this helper answers `getHelperInfo` with.
    var info = HelperInfo(binaryVersion: "1.0.0", buildNumber: 1, protocolVersion: 2)

    /// Parks the probe's reply instead of answering it inline.
    var defersInfoReply = false

    /// Parks the removal's reply instead of answering it inline.
    var defersRemovalReply = false

    var removalSucceeds = true
    var removalMessage: String?

    var removalPayloads: [Data] {
        lock.withLock { sentRemovals }
    }

    var infoRequestCount: Int {
        lock.withLock { infoRequests }
    }

    var legacyRemovalCount: Int {
        lock.withLock { legacyRemovals }
    }

    var hasPendingInfoReply: Bool {
        lock.withLock { parkedInfoReply != nil }
    }

    /// Answers a parked probe. Returns false when nothing was waiting.
    @discardableResult
    func answerPendingInfo() -> Bool {
        let parked = lock.withLock { () -> ((String, Int, Int) -> Void)? in
            let reply = parkedInfoReply
            parkedInfoReply = nil
            return reply
        }
        guard let parked else {
            return false
        }
        parked(info.binaryVersion, info.buildNumber, info.protocolVersion)
        return true
    }

    /// Answers a parked removal. Returns false when nothing was waiting.
    @discardableResult
    func answerPendingRemoval(success: Bool, message: String?) -> Bool {
        let parked = lock.withLock { () -> ((Bool, String?) -> Void)? in
            let reply = parkedRemovalReply
            parkedRemovalReply = nil
            return reply
        }
        guard let parked else {
            return false
        }
        parked(success, message)
        return true
    }

    func getHelperInfo(withReply reply: @escaping (String, Int, Int) -> Void) {
        let deferred: Bool = lock.withLock {
            infoRequests += 1
            if defersInfoReply {
                parkedInfoReply = reply
                return true
            }
            return false
        }
        guard !deferred else {
            return
        }
        reply(info.binaryVersion, info.buildNumber, info.protocolVersion)
    }

    func removeRootCertificateMatching(_ derData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        let deferred: Bool = lock.withLock {
            sentRemovals.append(derData)
            if defersRemovalReply {
                parkedRemovalReply = reply
                return true
            }
            return false
        }
        guard !deferred else {
            return
        }
        reply(removalSucceeds, removalMessage)
    }

    func removeRootCertificate(withReply reply: @escaping (Bool, String?) -> Void) {
        lock.withLock { legacyRemovals += 1 }
        Issue.record("The wrapper must never send the label-based removal selector")
        reply(false, "unexpected")
    }

    func overrideSystemProxy(port _: Int, ownerPID _: Int32, withReply reply: @escaping (Bool, String?) -> Void) {
        Self.recordUnexpected("overrideSystemProxy")
        reply(false, "unexpected")
    }

    func restoreSystemProxy(withReply reply: @escaping (Bool, String?) -> Void) {
        Self.recordUnexpected("restoreSystemProxy")
        reply(false, "unexpected")
    }

    func getProxyStatus(withReply reply: @escaping (Bool, Int) -> Void) {
        Self.recordUnexpected("getProxyStatus")
        reply(false, 0)
    }

    func prepareForUninstall(withReply reply: @escaping (Bool) -> Void) {
        Self.recordUnexpected("prepareForUninstall")
        reply(false)
    }

    func prepareForExecutableRefresh(withReply reply: @escaping (Bool) -> Void) {
        Self.recordUnexpected("prepareForExecutableRefresh")
        reply(false)
    }

    func getExecutableIdentity(
        withReply reply: @escaping (String, String, Int32, String, Int, Int) -> Void
    ) {
        Self.recordUnexpected("getExecutableIdentity")
        reply("", "", 0, "", 0, 0)
    }

    func installRootCertificate(_: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        Self.recordUnexpected("installRootCertificate")
        reply(false, "unexpected")
    }

    func verifyRootCertificateTrusted(_: String, withReply reply: @escaping (Bool) -> Void) {
        Self.recordUnexpected("verifyRootCertificateTrusted")
        reply(false)
    }

    func cleanupStaleCertificates(_: String, withReply reply: @escaping (Int, String?) -> Void) {
        Self.recordUnexpected("cleanupStaleCertificates")
        reply(0, "unexpected")
    }

    func setBypassDomains(_: [String], withReply reply: @escaping (Bool, String?) -> Void) {
        Self.recordUnexpected("setBypassDomains")
        reply(false, "unexpected")
    }

    // MARK: Private

    private let lock = NSLock()
    private var sentRemovals: [Data] = []
    private var infoRequests = 0
    private var legacyRemovals = 0
    private var parkedInfoReply: ((String, Int, Int) -> Void)?
    private var parkedRemovalReply: ((Bool, String?) -> Void)?

    private static func recordUnexpected(_ selector: String) {
        Issue.record("An exact removal must not send \(selector)")
    }
}
