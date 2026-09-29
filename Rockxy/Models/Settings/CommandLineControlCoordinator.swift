import Foundation
import os

// MARK: - CommandLineControlCoordinator

/// Runs the socket `rockxy-cli` talks to while command-line control is allowed, and routes each
/// request to the main workspace.
@MainActor
final class CommandLineControlCoordinator {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Internal

    static let shared = CommandLineControlCoordinator()

    static let enabledKey = RockxyIdentity.current.defaultsKey("commandLine.enabled")

    /// Socket file name inside the app's support folder; `rockxy-cli` looks for the same name.
    static let socketFileName = "rockxy-cli.sock"

    weak var target: CommandLineControlTarget?

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    private(set) var lastError: String?

    var socketPath: String {
        RockxyIdentity.current.appSupportPath(Self.socketFileName).path
    }

    /// The command-line tool shipped inside the app bundle.
    var toolPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/rockxy-cli").path
    }

    func startIfEnabled() {
        guard isEnabled else {
            stop()
            return
        }
        let server = server ?? LocalCommandSocketServer { data in
            await Self.shared.handle(data)
        }
        self.server = server
        do {
            try FileManager.default.createDirectory(
                at: RockxyIdentity.current.appSupportDirectory(),
                withIntermediateDirectories: true
            )
            try server.start(path: socketPath)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Command-line control did not start: \(error.localizedDescription)")
        }
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        startIfEnabled()
    }

    func stop() {
        server?.stop()
    }

    func handle(_ data: Data) async -> Data {
        let response: CommandLineResponse
        if let request = try? JSONDecoder().decode(CommandLineRequest.self, from: data) {
            response = await CommandLineCommandRunner.run(request, target: target)
        } else {
            response = .failure(String(
                localized: "The request could not be read. Update rockxy-cli to match this Rockxy.",
                bundle: RockxyLocalization.bundle
            ))
        }
        return (try? JSONEncoder().encode(response)) ?? Data()
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "CommandLineControl")

    private let defaults: UserDefaults
    private var server: LocalCommandSocketServer?
}
