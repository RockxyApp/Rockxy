import Darwin
import Foundation
import os

// Monitors process termination signals so proxy cleanup can run before exit.

// MARK: - TerminationSignalMonitor

/// Observes common termination signals so Rockxy can restore proxy settings before exit.
final class TerminationSignalMonitor {
    // MARK: Lifecycle

    init(cleanup: @escaping @Sendable (Int32) -> Void) {
        self.cleanup = cleanup
        install()
    }

    deinit {
        for source in sources {
            source.cancel()
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "TerminationSignalMonitor")

    private let cleanup: @Sendable (Int32) -> Void
    private let lock = NSLock()
    private var handledSignal = false
    private var sources: [DispatchSourceSignal] = []
    private let observedSignals: [Int32] = [SIGTERM, SIGINT, SIGHUP, SIGQUIT]

    private func install() {
        for signum in observedSignals {
            Darwin.signal(signum, SIG_IGN)

            let source = DispatchSource.makeSignalSource(
                signal: signum,
                queue: DispatchQueue.global(qos: .userInitiated)
            )
            source.setEventHandler { [weak self] in
                self?.handle(signum: signum)
            }
            source.resume()
            sources.append(source)
        }
    }

    private func handle(signum: Int32) {
        lock.lock()
        let shouldHandle = !handledSignal
        if shouldHandle {
            handledSignal = true
        }
        lock.unlock()

        guard shouldHandle else {
            return
        }

        Self.logger.warning("Received termination signal \(signum), performing emergency cleanup")

        for source in sources {
            source.cancel()
        }

        cleanup(signum)

        Darwin.signal(signum, SIG_DFL)
        Darwin.kill(Darwin.getpid(), signum)
    }
}
