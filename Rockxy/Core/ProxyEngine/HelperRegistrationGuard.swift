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
/// A false positive in a shipped app would fail closed (the helper is not modified), never open,
/// which is why the decision cannot rest on anything another process can set.
enum HelperRegistrationGuard {
    // MARK: Internal

    /// Raised in place of a registration mutation inside a test host.
    struct RefusedUnderTestError: LocalizedError, Equatable {
        let operation: String

        var errorDescription: String? {
            "Helper registration is disabled while running tests (\(operation))."
        }
    }

    /// Whether this process is a test host, decided once per process.
    ///
    /// Latched so every call in one process agrees. `HelperManager+AppUpdate` runs
    /// `performUninstall()`, a sleep, then `performInstall()`; a guard that answered differently
    /// between those two calls could leave the helper unregistered.
    nonisolated static let isCurrentProcessTestHost: Bool = isTestHost(
        isTestFrameworkLoaded: loadedImagePaths().contains(where: isTestFrameworkImagePath)
    )

    /// Whether a loaded Mach-O image path belongs to XCTest or Swift Testing.
    nonisolated static func isTestFrameworkImagePath(_ path: String) -> Bool {
        path.contains("/XCTest.framework/") || path.contains("/Testing.framework/")
    }

    /// Whether this process is a test host, decided solely by whether a test framework is loaded.
    ///
    /// The loaded-image scan is the only signal, because it is the only one that cannot be set
    /// from outside the process. A hardened-runtime app with library validation does not load a
    /// foreign framework, and `DYLD_INSERT_LIBRARIES` is stripped, so a shipped Rockxy cannot have
    /// `XCTest.framework` or `Testing.framework` in its image list.
    ///
    /// Nothing the environment says is consulted, and that is deliberate rather than an omission.
    /// An earlier version of this guard decided on `XCTestConfigurationFilePath` and its siblings.
    /// Any process running as the user can plant those for every future app launch with
    /// `launchctl setenv`; it survives logout, so every Rockxy opened afterwards refused to
    /// install, uninstall, repair, force-reset or force-remove the privileged daemon, with no way
    /// for the user to see why. Requiring the environment to *agree* with the image scan fixes the
    /// denial but buys nothing in exchange: the scan already cannot be faked, while a runner that
    /// stops setting those keys would make this guard fail open and let a test run re-point the
    /// user's approved registration again -- the defect it exists to prevent. One unspoofable
    /// signal is both safer and simpler than two where the weaker one can only do harm.
    ///
    /// Command-line arguments are not consulted either: a user can open a file whose name contains
    /// "XCTest" in a shipped app, and that must never disable the helper.
    nonisolated static func isTestHost(isTestFrameworkLoaded: Bool) -> Bool {
        isTestFrameworkLoaded
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

    private static func loadedImagePaths() -> [String] {
        (0 ..< _dyld_image_count()).compactMap { index in
            _dyld_get_image_name(index).map { String(cString: $0) }
        }
    }
}
