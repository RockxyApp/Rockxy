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

    private static func checkAndExit() {
        let status = ProxyConfigurator.getCurrentStatus()
        if status.isOverridden {
            logger.info("Idle timeout reached but proxy is still overridden on port \(status.port) — deferring exit")
            scheduleTimerOnQueue()
            return
        }

        logger.info("Idle timeout reached with no active proxy override — exiting")
        exit(0)
    }
}
