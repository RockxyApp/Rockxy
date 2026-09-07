import Foundation
import os

/// Monitors XPC activity and exits the helper daemon after a period of inactivity.
///
/// The helper is a launchd on-demand daemon, so exiting when idle is safe — launchd
/// will re-launch it when a new XPC connection arrives. Before exiting, the monitor
/// checks whether an active proxy override exists and defers exit if so.
enum IdleExitMonitor {
    // MARK: Internal

    /// Starts the idle exit timer. Call once from `main.swift` before `RunLoop.current.run()`.
    static func start() {
        logger.info("Idle exit monitor started (timeout: \(Int(idleTimeout))s)")
        scheduleTimer()
    }

    /// Resets the idle timer. Call on every XPC activity (new connection, method call).
    static func resetIdleTimer() {
        queue.async {
            logger.debug("Idle timer reset due to XPC activity")
            idleTimer?.cancel()
            scheduleTimerOnQueue()
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "IdleExitMonitor"
    )

    private static let idleTimeout: TimeInterval = 5 * 60
    /// The same gate every privileged mutation takes, so exiting is serialized against them.
    private static let mutationGate = HelperPrivilegedMutationGate.shared
    private static let queue = DispatchQueue(label: "com.amunx.rockxy.helper.idle-exit")

    private static var idleTimer: DispatchSourceTimer?

    private static func scheduleTimer() {
        queue.async {
            scheduleTimerOnQueue()
        }
    }

    /// Must be called on `queue`.
    private static func scheduleTimerOnQueue() {
        idleTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + idleTimeout)
        timer.setEventHandler {
            checkAndExit()
        }
        idleTimer = timer
        timer.resume()
    }

    /// Must be called on `queue`.
    ///
    /// A timer event that has already been dequeued cannot be cancelled, so reading the proxy
    /// status and exiting on the answer used to be enough to exit in the middle of somebody
    /// else's privileged mutation — with the reply never arriving and the settings left part-way.
    /// The decision now runs through the same exclusive gate every proxy and certificate mutation
    /// takes: a busy gate means the helper is still needed, and a free one cannot be filled
    /// between the recheck and the exit because this holds it.
    private static func checkAndExit() {
        switch HelperIdleExitSequence.run(
            proxyIsOverridden: {
                // The status answers for the routed service alone, so an override that stopped on
                // a secondary one reads as idle. A restore point still on disk names exactly the
                // services in that position, and exiting would take away the only process left
                // that could put them back.
                HelperOverrideResidencyPolicy.overrideNeedsHelper(
                    routedServiceIsOverridden: ProxyConfigurator.getCurrentStatus().isOverridden,
                    unresolvedBackupExists: CrashRecovery.hasBackup()
                )
            },
            acquireExitBarrier: { mutationGate.beginProcessExitBarrier() },
            release: { mutationGate.release($0) }
        ) {
        case .deferOverridden:
            logger.info("Idle timeout reached but a proxy override or its restore point is still in place — deferring exit")
            if CrashRecovery.hasBackup() {
                HelperService.scheduleBackupRecovery(reason: "idle residency check")
            }
            scheduleTimerOnQueue()
        case .deferBusy:
            logger.info("Idle timeout reached while a privileged operation is running — deferring exit")
            scheduleTimerOnQueue()
        case .exit:
            logger.info("Idle timeout reached with no active proxy override — exiting")
            exit(0)
        }
    }
}
