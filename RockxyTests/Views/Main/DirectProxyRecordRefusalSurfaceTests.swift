import Foundation
@testable import Rockxy
import Testing

// MARK: - DirectProxyRecordRefusalSurfaceTests

/// The banner that tells the user the Mac's proxy settings cannot be restored automatically
/// because the saved record could not be verified. Everything here drives the coordinator's
/// observable state through the injected probe, so no live proxy setting is ever read or written.
@Suite(.serialized, .sharedPolicyState)
@MainActor
struct DirectProxyRecordRefusalSurfaceTests {
    // MARK: Internal

    @Test("The warning appears when the refusal flag is set and carries the restore action")
    func warningAppearsWhenFlagIsSet() {
        let coordinator = makeCoordinator(refused: true)

        #expect(coordinator.systemProxyWarning == nil || coordinator.systemProxyWarning?
            .action != .restoreProxySettings)

        coordinator.syncDirectWatchdogRefusal()

        let warning = coordinator.systemProxyWarning
        #expect(coordinator.isDirectProxyRecordUnverified)
        #expect(warning?.action == .restoreProxySettings)
        #expect(warning?.action?.title == "Restore Proxy Settings")
        #expect(warning?.message == SystemProxyWarning.directRecordUnverifiedMessage)
        #expect(warning?.isDismissible == false)
    }

    @Test("The warning disappears when the manager clears the flag")
    func warningDisappearsWhenFlagClears() {
        let flag = Flag(true)
        let coordinator = makeCoordinator(flag: flag)
        coordinator.syncDirectWatchdogRefusal()
        #expect(coordinator.systemProxyWarning?.action == .restoreProxySettings)

        flag.value = false
        coordinator.syncDirectWatchdogRefusal()

        #expect(!coordinator.isDirectProxyRecordUnverified)
        #expect(coordinator.systemProxyWarning?.action != .restoreProxySettings)
    }

    @Test("Nothing is shown while the flag has never been set")
    func nothingShownByDefault() {
        let coordinator = makeCoordinator(refused: false)
        coordinator.syncDirectWatchdogRefusal()

        #expect(!coordinator.isDirectProxyRecordUnverified)
        #expect(coordinator.systemProxyWarning?.action != .restoreProxySettings)
    }

    @Test("While capture runs the action takes the manual Stop path and nothing else")
    func actionWhileRunningStopsCapture() {
        let coordinator = makeCoordinator(refused: true)
        coordinator.isProxyRunning = true
        let calls = Calls()

        coordinator.restoreProxySettingsAfterUnverifiedRecord(
            stopCapture: {
                calls.stop += 1
                return nil
            },
            switchOffRouting: {
                calls.switchOff += 1
                return Task {}
            }
        )

        #expect(calls.stop == 1)
        #expect(calls.switchOff == 0)
    }

    @Test("With no listener the action restores the proxy settings directly")
    func actionWhileStoppedSwitchesRoutingOff() {
        let coordinator = makeCoordinator(refused: true)
        coordinator.isProxyRunning = false
        let calls = Calls()

        coordinator.restoreProxySettingsAfterUnverifiedRecord(
            stopCapture: {
                calls.stop += 1
                return nil
            },
            switchOffRouting: {
                calls.switchOff += 1
                return Task {}
            }
        )

        #expect(calls.stop == 0)
        #expect(calls.switchOff == 1)
    }

    @Test("Activation re-reads the refusal so one that arrived in the background shows the banner")
    func activationSurfacesRefusalFromBackground() async {
        let flag = Flag(false)
        let coordinator = makeCoordinator(flag: flag)
        coordinator.isProxyRunning = true
        coordinator.syncDirectWatchdogRefusal()
        #expect(coordinator.systemProxyWarning?.action != .restoreProxySettings)

        flag.value = true
        let calls = Calls()
        let task = coordinator.refreshProxyOverrideStatusOnActivation {
            calls.reconcile += 1
            coordinator.syncDirectWatchdogRefusal()
        }
        await task?.value

        #expect(calls.reconcile == 1)
        #expect(coordinator.isDirectProxyRecordUnverified)
        #expect(coordinator.systemProxyWarning?.action == .restoreProxySettings)
    }

    @Test("Activation does nothing when there is no listener and no known override")
    func activationSkipsWhenNothingToRestore() {
        let coordinator = makeCoordinator(refused: true)
        coordinator.isProxyRunning = false
        coordinator.isProxyOverridden = false
        let calls = Calls()

        let task = coordinator.refreshProxyOverrideStatusOnActivation { calls.reconcile += 1 }

        #expect(task == nil)
        #expect(calls.reconcile == 0)
    }

    @Test("A known override with no listener still reconciles on activation")
    func activationReconcilesKnownOverride() async {
        let coordinator = makeCoordinator(refused: false)
        coordinator.isProxyRunning = false
        coordinator.isProxyOverridden = true
        let calls = Calls()

        await coordinator.refreshProxyOverrideStatusOnActivation { calls.reconcile += 1 }?.value

        #expect(calls.reconcile == 1)
    }

    @Test("The workspace observes app activation and routes it to the coordinator")
    func contentViewObservesActivation() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Rockxy/ContentView.swift"),
            encoding: .utf8
        )
        let stripped = source.filter { !$0.isWhitespace }

        #expect(stripped.contains(
            "NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)){_incoordinator.refreshProxyOverrideStatusOnActivation()"
        ))
    }

    @Test("A restore that already failed keeps its own warning instead of being replaced")
    func failedRestoreWarningIsNotReplaced() {
        let coordinator = makeCoordinator(refused: true)
        coordinator.syncDirectWatchdogRefusal()
        let readiness = coordinator.readiness
        readiness.setCaptureActive(false)
        readiness.setCaptureActive(true)
        readiness.setProxyRestoreFailed(retryAction: .retryStop)
        defer {
            readiness.clearProxyRestoreFailure()
            readiness.setCaptureActive(false)
        }

        #expect(coordinator.systemProxyWarning?.action == .retryStop)
    }

    @Test("The toolbar popover row reports the unverified restore record")
    func popoverRowReportsUnverifiedRecord() {
        func presentation(unverified: Bool) -> CaptureStatusPresentation {
            CaptureStatusPresentation(
                displayState: .running,
                listenAddress: "127.0.0.1",
                port: 9_090,
                certReadiness: .trusted,
                helperReadiness: .installedCompatible,
                isSystemProxyConfigured: true,
                isRestoreRecordUnverified: unverified
            )
        }

        #expect(presentation(unverified: true).systemRouting.value == "Restore not verified")
        #expect(presentation(unverified: true).systemRouting.level == .attention)
        #expect(presentation(unverified: false).systemRouting.value == "Routing active")
    }

    @Test("User-facing text says what is true and does not expose internals")
    func messageAvoidsInternals() {
        let message = SystemProxyWarning.directRecordUnverifiedMessage

        #expect(!message.localizedCaseInsensitiveContains("watchdog"))
        #expect(!message.localizedCaseInsensitiveContains("launchd"))
        #expect(message.contains("proxy settings still point at Rockxy"))
        #expect(message.contains("could not verify"))
        #expect(message.contains("put the settings back"))
    }

    @Test("The localization catalog carries every new key with a Simplified Chinese value")
    func catalogCarriesNewKeys() throws {
        let data = try Data(contentsOf: projectRoot().appendingPathComponent("Rockxy/Localizable.xcstrings"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        let keys = [
            "Restore Proxy Settings",
            "Restore not verified",
            SystemProxyWarning.directRecordUnverifiedMessage,
        ]

        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "missing catalog key: \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let zh = try #require(localizations["zh-Hans"] as? [String: Any])
            let unit = try #require(zh["stringUnit"] as? [String: Any])
            #expect(unit["state"] as? String == "translated")
            #expect((unit["value"] as? String)?.isEmpty == false)
        }
    }

    @Test("The workspace routes the banner action to the coordinator's restore")
    func contentViewRoutesTheAction() throws {
        let source = try String(
            contentsOf: projectRoot().appendingPathComponent("Rockxy/ContentView.swift"),
            encoding: .utf8
        )
        let stripped = source.filter { !$0.isWhitespace }

        #expect(stripped.contains("case.restoreProxySettings:coordinator.restoreProxySettingsAfterUnverifiedRecord()"))
    }

    // MARK: Private

    private final class Flag {
        // MARK: Lifecycle

        init(_ value: Bool) {
            self.value = value
        }

        // MARK: Internal

        var value: Bool
    }

    private final class Calls {
        var stop = 0
        var switchOff = 0
        var reconcile = 0
    }

    private func makeCoordinator(refused: Bool) -> MainContentCoordinator {
        makeCoordinator(flag: Flag(refused))
    }

    private func makeCoordinator(flag: Flag) -> MainContentCoordinator {
        let coordinator = MainContentCoordinator()
        coordinator.directWatchdogRefusalProbe = { flag.value }
        return coordinator
    }

    private func projectRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Rockxy.xcodeproj").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

// MARK: - DirectWatchdogNeverRanSurfaceTests

/// A second, separate fault from a refused record: the watchdog job never started (launchd
/// `EX_CONFIG`). It has its own flag and honest copy, and leads to the same restore action.
@Suite(.serialized, .sharedPolicyState)
@MainActor
struct DirectWatchdogNeverRanSurfaceTests {
    @Test("A watchdog that never ran shows its own copy and the existing restore action")
    func warningUsesOwnCopy() {
        let coordinator = MainContentCoordinator()
        coordinator.directWatchdogRefusalProbe = { false }
        coordinator.directWatchdogNeverRanProbe = { true }
        coordinator.syncDirectWatchdogRefusal()

        let warning = coordinator.systemProxyWarning
        #expect(coordinator.isDirectWatchdogNotRunning)
        #expect(!coordinator.isDirectProxyRecordUnverified)
        #expect(warning?.action == .restoreProxySettings)
        #expect(warning?.message == SystemProxyWarning.directWatchdogNotRunningMessage)
        #expect(warning?.message != SystemProxyWarning.directRecordUnverifiedMessage)
        #expect(!SystemProxyWarning.directWatchdogNotRunningMessage.contains("verify"))
        #expect(warning?.isDismissible == false)
    }

    @Test("A refused record outranks, and clearing the flag removes the banner")
    func priorityAndClearing() {
        let coordinator = MainContentCoordinator()
        coordinator.directWatchdogRefusalProbe = { true }
        coordinator.directWatchdogNeverRanProbe = { true }
        coordinator.syncDirectWatchdogRefusal()
        #expect(coordinator.systemProxyWarning?.message == SystemProxyWarning.directRecordUnverifiedMessage)

        coordinator.directWatchdogRefusalProbe = { false }
        coordinator.directWatchdogNeverRanProbe = { false }
        coordinator.syncDirectWatchdogRefusal()
        #expect(!coordinator.isDirectWatchdogNotRunning)
        #expect(coordinator.systemProxyWarning?.action != .restoreProxySettings)
    }
}
