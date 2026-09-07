import Darwin
import Foundation

// Identifies a specific running process across a relaunch of an observer process.

// MARK: - ProcessStartIdentity

/// A PID on its own does not identify a process: the kernel recycles process identifiers, so a
/// recorded PID can name an unrelated process minutes later. Pairing the PID with the kernel's
/// process start time gives an identity that a recycled PID cannot forge.
enum ProcessStartIdentity {
    // MARK: Internal

    /// Whether a process with this identifier currently exists.
    /// `EPERM` still means the process is there — it just belongs to another user.
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else {
            return false
        }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    /// Reads the kernel start time of a live process and formats it as a stable signature.
    /// Returns nil when the process no longer exists or the kernel refuses the query.
    static func startSignature(for pid: Int32) -> String? {
        guard pid > 0 else {
            return nil
        }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0, info.kp_proc.p_pid == pid else {
            return nil
        }

        return signature(startTime: info.kp_proc.p_un.__p_starttime)
    }

    /// Formats a kernel start time into the signature stored alongside a backup.
    static func signature(startTime: timeval) -> String {
        "\(startTime.tv_sec).\(startTime.tv_usec)"
    }

    /// Pure comparison used by recovery: a recorded identity names the same process only when
    /// the PID is positive, a signature was recorded, and the live process reports that exact
    /// signature. A missing recorded signature is a legacy record, never a match.
    static func identifiesSameProcess(
        recordedPID: Int32?,
        recordedStartSignature: String?,
        liveStartSignature: String?
    )
        -> Bool
    {
        guard let recordedPID, recordedPID > 0,
              let recordedStartSignature, !recordedStartSignature.isEmpty,
              let liveStartSignature, !liveStartSignature.isEmpty else
        {
            return false
        }
        return recordedStartSignature == liveStartSignature
    }
}
