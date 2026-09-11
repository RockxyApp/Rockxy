import Foundation
@testable import Rockxy
import Testing

// Drives the real `HelperConnection.installRootCertificate(derData:)` wrapper — its dedicated
// session, its capability probe, its capability gate, its cancellation check, and its send gate —
// against a fake helper. Nothing here reaches a privileged helper, the System keychain, or a trust
// setting: the session the wrapper runs on is injected, so no NSXPCConnection is ever created.
//
// The distinction every case turns on is *dispatch*. `HelperInstallNotDispatched` is the app's only
// licence to raise its own authorization dialog for the same material, so it has to be produced
// exactly when nothing reached the daemon — and never once the message has been committed, where
// the helper may have applied the install and lost only the reply.

// MARK: - CertificateInstallDispatchTests

@MainActor
struct CertificateInstallDispatchTests {
    // MARK: Internal

    @Test("a protocol 1 helper is never sent an install, whatever its build number claims")
    func protocolOneIsNeverAskedToInstall() async {
        let fake = InstallFakeHelperProxy()
        // A shipped copy of Rockxy embeds a helper at this build that still speaks protocol 1 —
        // and whose install sweeps the root CA label before adding anything.
        fake.info = HelperInfo(binaryVersion: "9.9.9", buildNumber: 999_999, protocolVersion: 1)
        let teardowns = InstallTeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])

        let failure = await #expect(throws: HelperInstallNotDispatched.self) {
            try await connection.installRootCertificate(derData: Self.sampleDER)
        }

        #expect(failure?.errorDescription == HelperConnectionError.certInstallUnsupported.errorDescription)
        #expect(fake.installPayloads.isEmpty)
        #expect(teardowns.count == 1)
    }

    @Test("a protocol 2 helper receives exactly the supplied bytes, once")
    func protocolTwoReceivesTheExactBytes() async throws {
        let fake = InstallFakeHelperProxy()
        let teardowns = InstallTeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])

        try await connection.installRootCertificate(derData: Self.sampleDER)

        #expect(fake.installPayloads == [Self.sampleDER])
        #expect(fake.infoRequestCount == 1)
        #expect(teardowns.count == 1)
    }

    @Test("a session that cannot be created reports that nothing was sent")
    func unavailableSessionIsNotDispatched() async {
        let connection = Self.connection(returning: [])

        await #expect(throws: HelperInstallNotDispatched.self) {
            try await connection.installRootCertificate(derData: Self.sampleDER)
        }
    }

    @Test("a poisoned session sends nothing and leaves the app free to install itself")
    func poisonedSessionIsNotDispatched() async {
        let fake = InstallFakeHelperProxy()
        let teardowns = InstallTeardownCounter()
        let poisoned = HelperCertificateSession(proxy: fake) { teardowns.record() }
        poisoned.router.deliver(InstallSessionFailure())
        let connection = Self.connection(returning: [poisoned])

        await #expect(throws: HelperInstallNotDispatched.self) {
            try await connection.installRootCertificate(derData: Self.sampleDER)
        }

        #expect(fake.infoRequestCount == 0)
        #expect(fake.installPayloads.isEmpty)
        #expect(teardowns.count == 1)
    }

    @Test("a transport failure between the probe and the send prevents the install")
    func failureBetweenProbeAndSendSendsNothing() async {
        let fake = InstallFakeHelperProxy()
        fake.defersInfoReply = true
        let teardowns = InstallTeardownCounter()
        let session = HelperCertificateSession(proxy: fake) { teardowns.record() }
        let connection = Self.connection(returning: [session])

        let task = Task { try await connection.installRootCertificate(derData: Self.sampleDER) }
        let probeStarted = await waitUntil { fake.hasPendingInfoReply }
        #expect(probeStarted)

        // The probe is answered, then the connection drops before the wrapper resumes. Both run on
        // the main actor without an await in between, so the ordering is exact.
        #expect(fake.answerPendingInfo())
        session.router.deliver(InstallSessionFailure())

        await #expect(throws: HelperInstallNotDispatched.self) {
            try await task.value
        }
        #expect(fake.installPayloads.isEmpty)
        #expect(teardowns.count == 1)
    }

    @Test("cancelling during the capability probe sends no install")
    func cancellationDuringProbeSendsNothing() async {
        let fake = InstallFakeHelperProxy()
        fake.defersInfoReply = true
        let teardowns = InstallTeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])

        let task = Task { try await connection.installRootCertificate(derData: Self.sampleDER) }
        let probeStarted = await waitUntil { fake.hasPendingInfoReply }
        #expect(probeStarted)

        task.cancel()
        // The helper answers the probe anyway: the wrapper must still stop at its own check.
        #expect(fake.answerPendingInfo())

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(fake.installPayloads.isEmpty)
        #expect(teardowns.count == 1)
    }

    @Test("a timeout after the send is uncertain, not a licence to install again")
    func timeoutAfterSendIsDispatched() async throws {
        let fake = InstallFakeHelperProxy()
        fake.defersInstallReply = true
        let teardowns = InstallTeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])
        connection.certificateRequestTimeout = .milliseconds(100)

        let failure = await #expect(throws: (any Error).self) {
            try await connection.installRootCertificate(derData: Self.sampleDER)
        }

        // The message was committed before the timer fired, so the helper may still be applying
        // it. A second app-side install here would mean a second admin dialog for material that is
        // possibly already installed.
        #expect(!(failure is HelperInstallNotDispatched))
        #expect(try CertificateManager.helperInstallSentNothing(#require(failure)) == false)
        #expect(fake.installPayloads == [Self.sampleDER])
        #expect(teardowns.count == 1)

        // Resuming the continuation twice would trap, so surviving this line is the assertion.
        #expect(fake.answerPendingInstall(success: true, message: nil))
    }

    @Test("a helper that reports a failure has still been asked, so no fallback follows")
    func reportedFailureIsDispatched() async throws {
        let fake = InstallFakeHelperProxy()
        fake.installSucceeds = false
        fake.installMessage = "keychain is locked"
        let teardowns = InstallTeardownCounter()
        let connection = Self.connection(returning: [HelperCertificateSession(proxy: fake) { teardowns.record() }])

        let failure = await #expect(throws: HelperConnectionError.self) {
            try await connection.installRootCertificate(derData: Self.sampleDER)
        }

        #expect(failure?.errorDescription?.contains("keychain is locked") == true)
        #expect(try CertificateManager.helperInstallSentNothing(#require(failure)) == false)
        #expect(teardowns.count == 1)
    }

    // MARK: Private

    private static let sampleDER = Data([0x30, 0x82, 0x01, 0x02, 0xAB, 0xCD])

    /// A connection whose certificate sessions come from `sessions`, in order.
    private static func connection(returning sessions: [HelperCertificateSession]) -> HelperConnection {
        let queue = InstallSessionQueue(sessions)
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

// MARK: - InstallSessionQueue

/// Hands out the prepared sessions in order and fails loudly if the wrapper asks for one more.
private final class InstallSessionQueue: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ sessions: [HelperCertificateSession]) {
        remaining = sessions
    }

    // MARK: Internal

    func next() throws -> HelperCertificateSession {
        try lock.withLock {
            guard !remaining.isEmpty else {
                throw InstallSessionFailure()
            }
            return remaining.removeFirst()
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var remaining: [HelperCertificateSession]
}

// MARK: - InstallSessionFailure

private struct InstallSessionFailure: Error {}

// MARK: - InstallTeardownCounter

private final class InstallTeardownCounter: @unchecked Sendable {
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

// MARK: - InstallFakeHelperProxy

/// A stand-in for the privileged helper that records what the wrapper actually sent and lets a test
/// decide when — or whether — a reply arrives.
private final class InstallFakeHelperProxy: NSObject, RockxyHelperProtocol, @unchecked Sendable {
    // MARK: Internal

    var info = HelperInfo(binaryVersion: "1.0.0", buildNumber: 1, protocolVersion: 2)

    var defersInfoReply = false
    var defersInstallReply = false
    var installSucceeds = true
    var installMessage: String?

    var installPayloads: [Data] {
        lock.withLock { sentInstalls }
    }

    var infoRequestCount: Int {
        lock.withLock { infoRequests }
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

    /// Answers a parked install. Returns false when nothing was waiting.
    @discardableResult
    func answerPendingInstall(success: Bool, message: String?) -> Bool {
        let parked = lock.withLock { () -> ((Bool, String?) -> Void)? in
            let reply = parkedInstallReply
            parkedInstallReply = nil
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

    func installRootCertificate(_ derData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        let deferred: Bool = lock.withLock {
            sentInstalls.append(derData)
            if defersInstallReply {
                parkedInstallReply = reply
                return true
            }
            return false
        }
        guard !deferred else {
            return
        }
        reply(installSucceeds, installMessage)
    }

    func removeRootCertificate(withReply reply: @escaping (Bool, String?) -> Void) {
        Self.recordUnexpected("removeRootCertificate")
        reply(false, "unexpected")
    }

    func removeRootCertificateMatching(_: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        Self.recordUnexpected("removeRootCertificateMatching")
        reply(false, "unexpected")
    }

    func cleanupStaleCertificates(_: String, withReply reply: @escaping (Int, String?) -> Void) {
        // An installation that swept stale certificates is the defect this lane removes.
        Self.recordUnexpected("cleanupStaleCertificates")
        reply(0, "unexpected")
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

    func verifyRootCertificateTrusted(_: String, withReply reply: @escaping (Bool) -> Void) {
        Self.recordUnexpected("verifyRootCertificateTrusted")
        reply(false)
    }

    func setBypassDomains(_: [String], withReply reply: @escaping (Bool, String?) -> Void) {
        Self.recordUnexpected("setBypassDomains")
        reply(false, "unexpected")
    }

    // MARK: Private

    private let lock = NSLock()
    private var sentInstalls: [Data] = []
    private var infoRequests = 0
    private var parkedInfoReply: ((String, Int, Int) -> Void)?
    private var parkedInstallReply: ((Bool, String?) -> Void)?

    private static func recordUnexpected(_ selector: String) {
        Issue.record("A certificate install must not send \(selector)")
    }
}
