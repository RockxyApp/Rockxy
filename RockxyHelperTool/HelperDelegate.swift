import Foundation
import os

/// NSXPCListenerDelegate that validates incoming connections and sets up the exported service.
final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    // MARK: Internal

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    )
        -> Bool
    {
        guard ConnectionValidator.isValidCaller(connection) else {
            Self.logger.warning("Rejected XPC connection from untrusted caller (pid: \(connection.processIdentifier))")
            return false
        }

        Self.logger.info("Accepted XPC connection from pid \(connection.processIdentifier)")
        IdleExitMonitor.resetIdleTimer()

        connection.exportedInterface = NSXPCInterface(with: RockxyHelperProtocol.self)
        connection.exportedObject = HelperService.shared

        connection.invalidationHandler = {
            let processID = connection.processIdentifier
            Self.logger.warning("XPC connection invalidated for pid \(processID)")
            HelperService.shared.handleConnectionInvalidated(processID: processID)
        }

        connection.interruptionHandler = {
            Self.logger.info("XPC connection interrupted (transient, not restoring proxy)")
        }

        connection.resume()
        return true
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "HelperDelegate")
}
