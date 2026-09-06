import Foundation
@testable import Rockxy
import Testing

// The privileged helper's certificate mutations are read-mutate-verify sequences against one
// keychain, and XPC delivers messages concurrently. These pin the gate that keeps two of them from
// interleaving — and, just as importantly, keep it non-blocking: a refused caller must be told so
// *before* anything is mutated, never queued to run later against state it can no longer see.

// MARK: - HelperCertificateMutationGateTests

struct HelperCertificateMutationGateTests {
    @Test("a second mutation is refused rather than queued while the first holds the gate")
    func secondMutationIsRefused() throws {
        let gate = HelperPrivilegedMutationGate()

        let first = try #require(gate.tryAcquire())
        #expect(gate.isBusy)
        #expect(gate.tryAcquire() == nil)

        gate.release(first)
        #expect(gate.isBusy == false)
        #expect(gate.tryAcquire() != nil)
    }

    @Test("a busy gate refuses before the mutation runs")
    func busyGateNeverRunsTheBody() throws {
        let gate = HelperPrivilegedMutationGate()
        let holder = try #require(gate.tryAcquire())

        var ranWhileBusy = false
        let refused: Bool? = gate.withExclusiveAccess {
            ranWhileBusy = true
            return true
        }

        // Nil is the refusal, and the body it guards never executed — so nothing was mutated and
        // nothing is left queued to mutate later.
        #expect(refused == nil)
        #expect(ranWhileBusy == false)

        gate.release(holder)
        #expect(gate.withExclusiveAccess { true } == true)
    }

    @Test("the gate is released before the body's caller resumes, so operations can follow directly")
    func gateIsFreeImmediatelyAfterTheBody() {
        let gate = HelperPrivilegedMutationGate()

        let ran = gate.withExclusiveAccess { true }
        #expect(ran == true)
        // A reply handler that starts the next operation must not be refused by the one that has
        // just finished.
        #expect(gate.isBusy == false)
        #expect(gate.withExclusiveAccess { true } == true)
    }

    @Test("a body that throws still releases the gate")
    func throwingBodyReleasesTheGate() {
        struct MutationFailure: Error {}
        let gate = HelperPrivilegedMutationGate()

        #expect(throws: MutationFailure.self) {
            try gate.withExclusiveAccess { throw MutationFailure() }
        }
        #expect(gate.isBusy == false)
    }

    @Test("a stale or duplicated ticket cannot end a later owner's turn")
    func staleTicketCannotReleaseTheCurrentOwner() throws {
        let gate = HelperPrivilegedMutationGate()

        let first = try #require(gate.tryAcquire())
        gate.release(first)
        let second = try #require(gate.tryAcquire())

        // The first operation's cleanup running late must not hand the keychain to a third caller
        // while the second operation is still mutating it.
        gate.release(first)
        #expect(gate.isBusy)
        #expect(gate.tryAcquire() == nil)

        gate.release(second)
        #expect(gate.isBusy == false)
    }

    @Test("every helper mutation shares one gate, so installs and removals exclude each other")
    func theGateIsProcessWide() throws {
        let holder = try #require(HelperPrivilegedMutationGate.shared.tryAcquire())
        defer { HelperPrivilegedMutationGate.shared.release(holder) }

        #expect(HelperPrivilegedMutationGate.shared.tryAcquire() == nil)
        #expect(HelperPrivilegedMutationGate.busyMessage.isEmpty == false)
        // Phrased as "try again", never as a result the caller can act on.
        #expect(HelperPrivilegedMutationGate.busyMessage.localizedLowercase.contains("try again"))
    }

    @Test("a ticket from another gate cannot release this gate's owner")
    func foreignTicketCannotReleaseOwner() throws {
        let first = HelperPrivilegedMutationGate()
        let second = HelperPrivilegedMutationGate()
        let owner = try #require(first.tryAcquire())
        let foreign = try #require(second.tryAcquire())
        defer { first.release(owner); second.release(foreign) }

        first.release(foreign)
        #expect(first.isBusy)
        #expect(first.tryAcquire() == nil)
    }

    @Test("process-exit barrier refuses concurrent mutation until its owner releases or exits")
    func processExitBarrierExcludesMutations() throws {
        let gate = HelperPrivilegedMutationGate()
        let barrier = try #require(gate.beginProcessExitBarrier())

        #expect(gate.isBusy)
        #expect(gate.tryAcquire() == nil)

        gate.release(barrier)
        #expect(gate.tryAcquire() != nil)
    }
}
