import Foundation
@testable import Rockxy
import Testing

// Regression tests for `HelperConnection` in the core proxy engine layer.

// MARK: - HelperConnectionErrorTests

struct HelperConnectionErrorTests {
    @Test("connectionFailed has descriptive message")
    func connectionFailedDescription() {
        let error = HelperConnectionError.connectionFailed
        let description = error.errorDescription ?? ""
        #expect(description.contains("XPC connection"))
    }

    @Test("proxyOverrideFailed includes the reason")
    func proxyOverrideFailedDescription() {
        let error = HelperConnectionError.proxyOverrideFailed("port already in use")
        let description = error.errorDescription ?? ""
        #expect(description.contains("port already in use"))
    }

    @Test("proxyRestoreFailed includes the reason")
    func proxyRestoreFailedDescription() {
        let error = HelperConnectionError.proxyRestoreFailed("no saved settings")
        let description = error.errorDescription ?? ""
        #expect(description.contains("no saved settings"))
    }

    @Test("uninstallFailed has descriptive message")
    func uninstallFailedDescription() {
        let error = HelperConnectionError.uninstallFailed
        let description = error.errorDescription ?? ""
        #expect(description.contains("uninstall"))
    }

    @Test("xpcTimeout has descriptive message")
    func xpcTimeoutDescription() {
        let error = HelperConnectionError.xpcTimeout
        let description = error.errorDescription ?? ""
        #expect(description.contains("timed out"))
    }

    @Test("appSignatureInvalid keeps technical detail out of end-user copy")
    func appSignatureInvalidDescription() {
        let error = HelperConnectionError.appSignatureInvalid("stale build")
        let description = error.errorDescription ?? ""
        #expect(description.contains("fresh copy"))
        #expect(!description.contains("stale build"))
    }

    @Test("applicationMustReopen gives an end-user recovery step")
    func applicationMustReopenDescription() {
        let description = HelperConnectionError.applicationMustReopen.errorDescription ?? ""
        #expect(description.contains("Quit and reopen Rockxy"))
        #expect(!description.localizedLowercase.contains("rebuild"))
    }

    @Test("signingIdentityMismatch includes signer names in description")
    func signingIdentityMismatchDescription() {
        let error = HelperConnectionError.signingIdentityMismatch(app: "Dev", helper: "Prod")
        let description = error.errorDescription ?? ""
        #expect(description.contains("Dev"))
        #expect(description.contains("Prod"))
    }

    @Test("certRemovalUnsupported tells the user to update the helper")
    func certRemovalUnsupportedDescription() {
        let description = HelperConnectionError.certRemovalUnsupported.errorDescription ?? ""
        #expect(description.localizedLowercase.contains("update the helper"))
        // The certificate is still installed, so the copy must not read as "already removed".
        #expect(!description.localizedLowercase.contains("removed"))
    }

    @Test("All cases conform to LocalizedError with non-nil descriptions")
    func allCasesHaveDescriptions() {
        let cases: [HelperConnectionError] = [
            .connectionFailed,
            .proxyOverrideFailed("test"),
            .proxyRestoreFailed("test"),
            .uninstallFailed,
            .xpcTimeout,
            .certInstallFailed("test"),
            .certInstallUnsupported,
            .certRemoveFailed("test"),
            .certRemovalUnsupported,
            .bypassDomainsFailed("test"),
            .executableRefreshUnsupported,
            .executableRefreshDeferred,
            .applicationMustReopen,
            .appSignatureInvalid("test"),
            .signingIdentityMismatch(app: "test", helper: "test"),
        ]

        for error in cases {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(description?.isEmpty == false)
        }
    }
}

// MARK: - XPCOperationCompletionTests

/// One XPC call can be answered by the helper's reply, by the connection's error handler, and
/// by the local timeout. Resuming a continuation twice traps, so exactly one of them may win.
struct XPCOperationCompletionTests {
    @Test("only the first completion path wins")
    func onlyTheFirstClaimWins() {
        let completion = XPCOperationCompletion()

        #expect(completion.claim())
        #expect(completion.claim() == false)
        #expect(completion.claim() == false)
    }

    @Test("concurrent completion attempts produce exactly one winner")
    func concurrentClaimsProduceOneWinner() async {
        let completion = XPCOperationCompletion()

        let winners = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 32 {
                group.addTask { completion.claim() }
            }
            var claimed = 0
            for await didClaim in group where didClaim {
                claimed += 1
            }
            return claimed
        }

        #expect(winners == 1)
    }
}

// MARK: - XPCFailureRouterTests

/// A proxy carries one error handler but a session sends more than one message through it, so
/// a delivery failure has to complete the operation that is actually waiting.
struct XPCFailureRouterTests {
    @Test("a failure reaches the operation that is waiting")
    func failureReachesTheOpenOperation() {
        let router = XPCFailureRouter()
        let received = ErrorRecorder()

        router.begin { received.record($0) }
        router.deliver(SampleFailure(id: "first"))

        #expect(received.identifiers == ["first"])
    }

    @Test("a failure that arrives before the operation opens is replayed to it")
    func earlyFailureIsReplayed() {
        let router = XPCFailureRouter()
        let received = ErrorRecorder()

        // The proxy can fail between its creation and the first message.
        router.deliver(SampleFailure(id: "early"))
        router.begin { received.record($0) }

        #expect(received.identifiers == ["early"])
    }

    @Test("a transport failure between the probe and mutation prevents sending the mutation")
    func interPhaseFailurePreventsSend() {
        let router = XPCFailureRouter()
        let received = ErrorRecorder()

        router.begin { _ in }
        router.end()
        router.deliver(SampleFailure(id: "late"))

        let maySend = router.begin { received.record($0) }
        #expect(!maySend)
        #expect(received.identifiers == ["late"])
        router.end()
        #expect(!router.begin { _ in })
    }

    @Test("a session poisoned after the window opened still sends nothing")
    func poisonedSessionCannotCommitASend() {
        let router = XPCFailureRouter()
        let operation = XPCOperationCompletion()
        var sent = false

        router.begin(operation: operation) { _ in }
        // The failure lands after `begin` said yes — the window a second `isFinished` check
        // would only have moved.
        router.deliver(SampleFailure(id: "inter-phase"))

        #expect(!router.commit(operation) { sent = true })
        #expect(!sent)
    }

    @Test("an operation that already completed sends nothing")
    func completedOperationCannotCommitASend() {
        let router = XPCFailureRouter()
        let operation = XPCOperationCompletion()
        var sent = false

        router.begin(operation: operation) { _ in }
        // The local timeout won the race to complete the caller.
        #expect(router.claim(operation))

        #expect(!router.commit(operation) { sent = true })
        #expect(!sent)
    }

    @Test("a reply delivered inline during the send neither deadlocks nor sends twice")
    func inlineReplyDuringSendIsSafe() {
        let router = XPCFailureRouter()
        let operation = XPCOperationCompletion()
        var completions = 0

        router.begin(operation: operation) { _ in }
        let sent = router.commit(operation) {
            if router.claim(operation) {
                completions += 1
                router.end()
            }
        }

        #expect(sent)
        #expect(completions == 1)
        #expect(!router.commit(operation) { completions += 1 })
        #expect(completions == 1)
    }

    @Test("a reply from a finished exchange cannot complete the one that followed it")
    func lateReplyCannotClaimTheNextExchange() {
        let router = XPCFailureRouter()
        let first = XPCOperationCompletion()
        let second = XPCOperationCompletion()

        router.begin(operation: first) { _ in }
        #expect(router.claim(first))
        router.end()

        router.begin(operation: second) { _ in }
        #expect(!router.claim(first))
        #expect(router.claim(second))
    }
}

// MARK: - SampleFailure

private struct SampleFailure: Error {
    let id: String
}

// MARK: - ErrorRecorder

private final class ErrorRecorder: @unchecked Sendable {
    // MARK: Internal

    var identifiers: [String] {
        lock.withLock { recorded }
    }

    func record(_ error: any Error) {
        lock.withLock { recorded.append((error as? SampleFailure)?.id ?? "unknown") }
    }

    // MARK: Private

    private let lock = NSLock()
    private var recorded: [String] = []
}
