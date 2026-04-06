import AppKit
import Foundation
import os

/// Observes `NSWindow` lifecycle events (close, etc.) for diagnostic logging.
/// Helps trace window management issues in the multi-window macOS app.
@MainActor
final class WindowLifecycleMonitor {
    // MARK: Internal

    func startMonitoring() {
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else {
                return
            }
            Self.logger.debug("Window closing: \(window.title)")
        }
        observations.append(closeObserver)
    }

    func stopMonitoring() {
        for observer in observations {
            NotificationCenter.default.removeObserver(observer)
        }
        observations.removeAll()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WindowLifecycleMonitor")

    private var observations: [NSObjectProtocol] = []
}
