import AppKit
import Foundation

// Launch lifecycle for user-selected developer applications: how Rockxy opens a fresh instance
// with a scoped environment and how it learns that the instance registered with macOS or exited.

// MARK: - DeveloperApplicationRegistrationState

enum DeveloperApplicationRegistrationState: Equatable, Sendable {
    case registered
    case pending
}

// MARK: - DeveloperApplicationLaunchReceipt

struct DeveloperApplicationLaunchReceipt: Equatable, Sendable {
    let lifecycleProcessIdentifier: Int32
    let registeredProcessIdentifier: Int32?
    let registrationState: DeveloperApplicationRegistrationState
}

// MARK: - DeveloperApplicationLaunching

@MainActor
protocol DeveloperApplicationLaunching {
    @discardableResult
    func launch(
        _ installation: DeveloperApplicationInstallation,
        arguments: [String],
        environment: [String: String],
        onTermination: (@MainActor @Sendable () -> Void)?
    )
        async throws -> DeveloperApplicationLaunchReceipt
}

// MARK: - DeveloperApplicationWorkspaceLauncher

/// Launches a fresh application instance with a scoped environment via LaunchServices.
///
/// `NSWorkspace.OpenConfiguration.environment` is additive to the caller's environment. Running
/// `/usr/bin/open` with an explicit `Process.environment` first prevents unrelated credentials and
/// developer-shell state from leaking into the selected application while retaining normal macOS
/// application registration and activation.
@MainActor
struct DeveloperApplicationWorkspaceLauncher: DeveloperApplicationLaunching {
    // MARK: Internal

    @discardableResult
    func launch(
        _ installation: DeveloperApplicationInstallation,
        arguments: [String],
        environment: [String: String],
        onTermination: (@MainActor @Sendable () -> Void)?
    )
        async throws -> DeveloperApplicationLaunchReceipt
    {
        let launchStartedAt = Date()
        let process = Process()
        let errorPipe = Pipe()
        let environmentArguments = environment.keys.sorted().flatMap { key in
            ["--env", "\(key)=\(environment[key] ?? "")"]
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-W", "-n"] + environmentArguments + [installation.appURL.path]
            + (arguments.isEmpty ? [] : ["--args"] + arguments)
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()
        errorPipe.fileHandleForWriting.closeFile()
        let errorCapture = DeveloperApplicationLaunchErrorCapture()
        errorCapture.startDraining(errorPipe.fileHandleForReading)
        let registration = try await registration(
            installation: installation,
            launchStartedAt: launchStartedAt,
            supervisor: process,
            errorCapture: errorCapture
        )
        let processIdentifier = process.processIdentifier
        if let onTermination {
            installTerminationHandler(on: process, callback: onTermination)
        }
        return DeveloperApplicationLaunchReceipt(
            lifecycleProcessIdentifier: processIdentifier,
            registeredProcessIdentifier: registration.processIdentifier,
            registrationState: registration.state
        )
    }

    // MARK: Private

    private struct Registration {
        let state: DeveloperApplicationRegistrationState
        let processIdentifier: Int32?
    }

    private func registration(
        installation: DeveloperApplicationInstallation,
        launchStartedAt: Date,
        supervisor: Process,
        errorCapture: DeveloperApplicationLaunchErrorCapture
    )
        async throws -> Registration
    {
        let expectedURL = installation.appURL.standardizedFileURL.resolvingSymlinksInPath()
        for _ in 0 ..< 200 {
            if let application = NSWorkspace.shared.runningApplications.first(where: { application in
                guard !application.isTerminated,
                      let bundleURL = application.bundleURL,
                      bundleURL.standardizedFileURL.resolvingSymlinksInPath() == expectedURL else
                {
                    return false
                }
                return application.launchDate.map { $0 >= launchStartedAt.addingTimeInterval(-1) } ?? true
            }) {
                return Registration(state: .registered, processIdentifier: application.processIdentifier)
            }
            if !supervisor.isRunning {
                supervisor.waitUntilExit()
                errorCapture.waitForDrain()
                let message = String(data: errorCapture.capturedData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw DeveloperSetupLaunchError.processFailed(
                    command: installation.displayName,
                    status: supervisor.terminationStatus,
                    message: message?.isEmpty == false
                        ? message
                        : "The application exited before registering with macOS."
                )
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Gatekeeper, first-run verification, and remote filesystems can legitimately take longer
        // than the bounded UI wait. The workflow binds durable recovery to this still-running
        // `open -W` lifecycle supervisor until startup reconciliation can discover the app itself.
        return Registration(state: .pending, processIdentifier: nil)
    }

    private func installTerminationHandler(
        on process: Process,
        callback: @escaping @MainActor @Sendable () -> Void
    ) {
        process.terminationHandler = { [process] _ in
            process.terminationHandler = nil
            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                // A killed or failed supervisor is not proof that the launched application quit.
                // Preserve the durable record for app-identity reconciliation on next startup.
                return
            }
            Task { @MainActor in
                callback()
            }
        }
        if !process.isRunning {
            process.terminationHandler = nil
            if process.terminationReason == .exit, process.terminationStatus == 0 {
                callback()
            }
        }
    }
}
