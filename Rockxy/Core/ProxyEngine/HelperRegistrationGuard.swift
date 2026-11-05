import Foundation
import os

// MARK: - HelperRegistrationGuard

/// Refuses every helper registration mutation while the process is an XCTest or Swift Testing host.
///
/// The test host is a full `Rockxy.app` that carries the shipping bundle identifier and the shipping
/// helper label. macOS Background Task Management keys its record by that label, so a test run that
/// registered, unregistered, or repaired the daemon re-pointed the user's approved registration at a
/// DerivedData bundle, and left it pointing at nothing once that bundle was deleted. Refusing is
/// preferred over giving the test host a different label: a test that registers a second daemon
/// still leaves a privileged job on the machine.
///
/// The guard only removes capability. It never grants a test an install, never relaxes
/// `ensureHelperMutationCanProceed()`, and does not touch caller validation on either side of XPC.
/// A false positive in a shipped app would fail closed (the helper is not modified), never open.
enum HelperRegistrationGuard {
    // MARK: Internal

    /// Raised in place of a registration mutation inside a test host.
    struct RefusedUnderTestError: LocalizedError, Equatable {
        let operation: String

        var errorDescription: String? {
            "Helper registration is disabled while running tests (\(operation))."
        }
    }

    /// Environment variables only the Xcode test runner sets on a test host process.
    static let testRunnerEnvironmentKeys = [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCTestSessionIdentifier",
    ]

    nonisolated static var isCurrentProcessTestHost: Bool {
        isTestHost(
            environment: ProcessInfo.processInfo.environment,
            isTestFrameworkLoaded: NSClassFromString("XCTestCase") != nil
                || NSClassFromString("XCTest.XCTestCase") != nil
                || NSClassFromString("Testing.Test") != nil
        )
    }

    /// Whether this process is a test host.
    ///
    /// Two independent signals, either sufficient: a test runner exported its configuration into the
    /// environment, or a test framework class is loaded into the process. A shipped Rockxy neither
    /// links XCTest or Swift Testing nor is launched by the test runner. Command-line arguments are
    /// deliberately not consulted: a user can open a file whose name contains "XCTest" in a shipped
    /// app, and that must never disable the helper.
    nonisolated static func isTestHost(
        environment: [String: String],
        isTestFrameworkLoaded: Bool
    )
        -> Bool
    {
        if isTestFrameworkLoaded {
            return true
        }
        return testRunnerEnvironmentKeys.contains { key in
            !(environment[key] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    /// Throws `RefusedUnderTestError` and logs when this process is a test host.
    nonisolated static func refuseIfTestHost(operation: String) throws {
        if refuses(operation: operation, isTestHost: isCurrentProcessTestHost) {
            throw RefusedUnderTestError(operation: operation)
        }
    }

    /// Non-throwing form for paths that report "not applicable" instead of failing.
    nonisolated static func refusesCurrentProcess(operation: String) -> Bool {
        refuses(operation: operation, isTestHost: isCurrentProcessTestHost)
    }

    /// Pure decision plus the log line, split out so the decision is testable with injected input.
    nonisolated static func refuses(operation: String, isTestHost: Bool) -> Bool {
        guard isTestHost else {
            return false
        }
        logger.notice(
            "Refused helper registration change under a test host: \(operation, privacy: .public)"
        )
        return true
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HelperRegistrationGuard"
    )
}
