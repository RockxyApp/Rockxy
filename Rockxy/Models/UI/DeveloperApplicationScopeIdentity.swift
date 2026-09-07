import AppKit
import Foundation

// Generic identity for developer-application installations and the settings scope Rockxy would
// prepare for them. The comparison seam is pure so preparation guards and restart detection can
// be verified deterministically without launching or inspecting real applications.

// MARK: - DeveloperApplicationScopeIdentity

/// One installed application described only by evidence Rockxy can verify: the resolved bundle
/// path and the recognized settings adapter detected inside that bundle. No product, vendor, or
/// process-name knowledge is encoded here.
struct DeveloperApplicationScopeIdentity: Equatable, Sendable {
    let bundlePath: String
    let settingsAdapter: DeveloperApplicationSettingsAdapter?
}

// MARK: - DeveloperApplicationRunningInstance

/// A running process paired with the installation identity it resolves to.
struct DeveloperApplicationRunningInstance: Equatable, Sendable {
    let processIdentifier: Int32
    let scope: DeveloperApplicationScopeIdentity
}

// MARK: - DeveloperApplicationScopeResolution

enum DeveloperApplicationScopeResolution {
    /// Two installations conflict when they are the same bundle, or when both resolve to the same
    /// recognized settings adapter. Adapter identity *is* settings-scope identity: the adapter
    /// payload determines the single settings file Rockxy would prepare, so two installations
    /// sharing it also share the transaction. Installations without a recognized adapter keep
    /// exact-path semantics because Rockxy never mutates settings for them.
    static func sharesSettingsScope(
        _ candidate: DeveloperApplicationScopeIdentity,
        _ other: DeveloperApplicationScopeIdentity
    )
        -> Bool
    {
        if !candidate.bundlePath.isEmpty, candidate.bundlePath == other.bundlePath {
            return true
        }
        guard let candidateAdapter = candidate.settingsAdapter,
              let otherAdapter = other.settingsAdapter else
        {
            return false
        }
        return candidateAdapter == otherAdapter
    }

    /// The running instance that must block a new preparation, if any.
    static func blockingInstance(
        candidate: DeveloperApplicationScopeIdentity,
        runningInstances: [DeveloperApplicationRunningInstance]
    )
        -> DeveloperApplicationRunningInstance?
    {
        runningInstances.first { sharesSettingsScope(candidate, $0.scope) }
    }

    /// The running instance that took over from an application that just exited. The exited
    /// process identifier is excluded so a stale listing of the original process can never be
    /// mistaken for its successor.
    static func successor(
        candidate: DeveloperApplicationScopeIdentity,
        excludingProcessIdentifier: Int32?,
        runningInstances: [DeveloperApplicationRunningInstance]
    )
        -> DeveloperApplicationRunningInstance?
    {
        runningInstances.first { instance in
            instance.processIdentifier > 0
                && instance.processIdentifier != excludingProcessIdentifier
                && sharesSettingsScope(candidate, instance.scope)
        }
    }
}

// MARK: - DeveloperApplicationWorkspaceScopeProvider

/// Resolves the identity of every running application from LaunchServices.
@MainActor
enum DeveloperApplicationWorkspaceScopeProvider {
    /// - Parameter resolvingSettingsAdapters: Detecting an adapter reads bounded metadata inside
    ///   each running bundle. Callers that only need path identity skip that work entirely.
    static func runningInstances(
        resolvingSettingsAdapters: Bool,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    )
        -> [DeveloperApplicationRunningInstance]
    {
        workspace.runningApplications.compactMap { application in
            guard !application.isTerminated, let bundleURL = application.bundleURL else {
                return nil
            }
            return DeveloperApplicationRunningInstance(
                processIdentifier: application.processIdentifier,
                scope: DeveloperApplicationCaptureConfigurator.scopeIdentity(
                    forBundleAt: bundleURL,
                    resolvingSettingsAdapter: resolvingSettingsAdapters,
                    fileManager: fileManager
                )
            )
        }
    }
}
