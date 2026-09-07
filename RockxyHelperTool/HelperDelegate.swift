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

        let processID = connection.processIdentifier
        guard let startSignature = ProcessStartIdentity.startSignature(for: processID),
              !startSignature.isEmpty
        else {
            Self.logger.warning("Rejected XPC connection whose process identity could not be captured (pid: \(processID))")
            return false
        }

        Self.logger.info("Accepted XPC connection from pid \(processID)")
        IdleExitMonitor.resetIdleTimer()

        connection.exportedInterface = NSXPCInterface(with: RockxyHelperProtocol.self)
        // One service object per connection, bound to the peer this listener just authenticated.
        // Exporting a process-wide object would leave every ownership-bearing method deciding
        // from an identifier the message carried, which the sender chooses.
        connection.exportedObject = HelperService(
            boundConnectionPID: processID,
            boundConnectionStartSignature: startSignature,
            boundUserID: connection.effectiveUserIdentifier
        )

        connection.invalidationHandler = {
            let processID = connection.processIdentifier
            Self.logger.warning("XPC connection invalidated for pid \(processID)")
            HelperService.handleConnectionInvalidated(processID: processID)
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
