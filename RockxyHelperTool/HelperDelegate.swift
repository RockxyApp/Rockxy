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
        // Apply the runtime signing requirement FIRST (it must precede resume) so the validator
        // is told, not left to guess, whether the runtime is already enforcing identity.
        let enforcement = Self.applyRuntimeSigningRequirement(to: connection)

        guard ConnectionValidator.isValidCaller(connection, enforcement: enforcement) else {
            Self.logger.warning("Rejected XPC connection from untrusted caller (pid: \(connection.processIdentifier))")
            return false
        }

        let processID = connection.processIdentifier
        guard let startSignature = ProcessStartIdentity.startSignature(for: processID),
              !startSignature.isEmpty else
        {
            Self.logger
                .warning("Rejected XPC connection whose process identity could not be captured (pid: \(processID))")
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

    /// Returns `.runtimeRequirementApplied` only when a requirement was built, pre-compiled by
    /// `SecRequirementCreateWithString`, and `setCodeSigningRequirement` then returned. The call
    /// raises an Objective-C exception on a malformed string, which Swift cannot catch, so the
    /// pre-compile in `connectionCodeSigningRequirement` is the guard against reaching it.
    private static func applyRuntimeSigningRequirement(
        to connection: NSXPCConnection
    )
        -> ConnectionValidator.IdentityEnforcement
    {
        guard let requirement = CallerValidation.connectionCodeSigningRequirement(
            helper: CallerValidation.launchSigningProfile,
            allowedIdentifiers: RockxyIdentity.current.allowedCallerIdentifiers
        ) else {
            logger
                .warning(
                    "No team-based XPC code-signing requirement available; audit-token check is the only identity enforcement"
                )
            return .validatorOnly
        }
        connection.setCodeSigningRequirement(requirement)
        return .runtimeRequirementApplied
    }
}
