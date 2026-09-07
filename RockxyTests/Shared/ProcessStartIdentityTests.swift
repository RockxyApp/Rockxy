import Darwin
import Foundation
@testable import Rockxy
import Testing

// Regression tests for `ProcessStartIdentity` in the shared recovery layer.

struct ProcessStartIdentityTests {
    @Test("The current process is alive and reports a stable start signature")
    func currentProcessHasStableSignature() {
        let pid = ProcessInfo.processInfo.processIdentifier

        #expect(ProcessStartIdentity.isAlive(pid))

        let firstReading = ProcessStartIdentity.startSignature(for: pid)
        let secondReading = ProcessStartIdentity.startSignature(for: pid)

        #expect(firstReading != nil)
        #expect(firstReading == secondReading)
    }

    @Test("Invalid process identifiers are never alive and have no signature")
    func invalidIdentifiersHaveNoIdentity() {
        for pid in [Int32(0), -1] {
            #expect(!ProcessStartIdentity.isAlive(pid))
            #expect(ProcessStartIdentity.startSignature(for: pid) == nil)
        }
    }

    @Test("A process that has exited no longer matches its recorded identity")
    func exitedProcessDoesNotMatchRecordedIdentity() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()

        let pid = process.processIdentifier
        let recordedSignature = ProcessStartIdentity.startSignature(for: pid)
        #expect(recordedSignature != nil)
        #expect(ProcessStartIdentity.isAlive(pid))
        #expect(ProcessStartIdentity.identifiesSameProcess(
            recordedPID: pid,
            recordedStartSignature: recordedSignature,
            liveStartSignature: ProcessStartIdentity.startSignature(for: pid)
        ))

        process.terminate()
        process.waitUntilExit()

        // Either the PID is gone, or it was handed to a different process — neither is the
        // session that was recorded.
        #expect(!ProcessStartIdentity.identifiesSameProcess(
            recordedPID: pid,
            recordedStartSignature: recordedSignature,
            liveStartSignature: ProcessStartIdentity.startSignature(for: pid)
        ))
    }

    @Test("Signature formatting uses the kernel start time verbatim")
    func signatureFormatsStartTime() {
        let startTime = timeval(tv_sec: 1_788_787_973, tv_usec: 748_707)

        #expect(ProcessStartIdentity.signature(startTime: startTime) == "1788787973.748707")
    }

    @Test("Identity comparison rejects missing, empty, and mismatched signatures")
    func identityComparisonRejectsIncompleteRecords() {
        #expect(!ProcessStartIdentity.identifiesSameProcess(
            recordedPID: nil,
            recordedStartSignature: "1.2",
            liveStartSignature: "1.2"
        ))
        #expect(!ProcessStartIdentity.identifiesSameProcess(
            recordedPID: 0,
            recordedStartSignature: "1.2",
            liveStartSignature: "1.2"
        ))
        #expect(!ProcessStartIdentity.identifiesSameProcess(
            recordedPID: 4_242,
            recordedStartSignature: "",
            liveStartSignature: ""
        ))
        #expect(!ProcessStartIdentity.identifiesSameProcess(
            recordedPID: 4_242,
            recordedStartSignature: "1.2",
            liveStartSignature: nil
        ))
        #expect(ProcessStartIdentity.identifiesSameProcess(
            recordedPID: 4_242,
            recordedStartSignature: "1.2",
            liveStartSignature: "1.2"
        ))
    }
}
