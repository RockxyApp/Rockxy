import Foundation
@testable import Rockxy
import Testing

/// "Never" blocks every way of acquiring the macOS system proxy and none of the ways of releasing
/// it. Each acquiring path is exercised with the mode substituted through `modeProvider`, so no
/// preference shared with the installed app and no live proxy setting is read or written: every
/// guard runs before the first mutation.
@Suite(.serialized, .sharedPolicyState)
@MainActor
struct SystemProxyNeverModeTests {
    // MARK: Internal

    @Test("Path 1: capture start and restart never acquire in Never or Manual")
    func captureStartIsGated() async throws {
        for mode in [SystemProxyRoutingMode.never, .manual] {
            try await withMode(mode) {
                var mutations = 0
                let enabled = try await AutomaticSystemProxyRouting.enableForCapture(enabledAtStart: true) {
                    mutations += 1
                }
                #expect(!enabled)
                #expect(mutations == 0)
            }
        }
    }

    @Test("Path 2: the switch-on control, menu, palette and CLI route is refused and explained")
    func switchOnIsRefused() async {
        await withMode(.never) {
            let coordinator = MainContentCoordinator()
            coordinator.isProxyRunning = true

            #expect(coordinator.switchOnSystemProxyOverride() == nil)

            #expect(!coordinator.isSystemProxyConfigured)
            #expect(!coordinator.isProxyOverridden)
            #expect(!coordinator.readiness.systemRoutingExpected)
            #expect(coordinator.activeToast?.text == AutomaticSystemProxyRouting.neverUnavailableReason)
        }
    }

    @Test("Path 2: toggling with no override acquires, so it is refused too")
    func toggleIsRefused() async {
        await withMode(.never) {
            let coordinator = MainContentCoordinator()
            coordinator.isProxyRunning = true
            coordinator.toggleSystemProxyOverride()
            #expect(!coordinator.isSystemProxyConfigured)
            #expect(!coordinator.readiness.systemRoutingExpected)
            #expect(coordinator.activeToast?.text == AutomaticSystemProxyRouting.neverUnavailableReason)
        }
    }

    @Test("Path 3: retry never marks routing expected and leaves no Retry warning behind")
    func retryIsRefused() async {
        await withMode(.never) {
            let coordinator = MainContentCoordinator()
            coordinator.isProxyRunning = true
            coordinator.readiness.setProxyEnableFailed(message: "earlier failure")

            coordinator.retrySystemProxy()

            #expect(!coordinator.isSystemProxyConfigured)
            #expect(!coordinator.readiness.systemRoutingExpected)
            #expect(coordinator.readiness.activeWarning == nil)
            #expect(coordinator.activeToast?.text == AutomaticSystemProxyRouting.neverUnavailableReason)
        }
    }

    @Test("Path 4: Welcome enable throws the readable reason before starting anything")
    func welcomeEnableIsRefused() async {
        await withMode(.never) {
            let coordinator = MainContentCoordinator()
            coordinator.isProxyRunning = true
            do {
                try await coordinator.enableSystemProxyFromWelcome()
                Issue.record("Welcome must not acquire the system proxy in Never")
            } catch let error as SystemProxyRoutingBlocked {
                #expect(error.localizedDescription == AutomaticSystemProxyRouting.neverUnavailableReason)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(!coordinator.readiness.systemRoutingExpected)
        }
    }

    @Test("Path 5: the Welcome view model fallback shows the reason and attempts nothing")
    func welcomeViewModelIsRefused() async {
        await withMode(.never) {
            let viewModel = WelcomeViewModel()
            await viewModel.enableProxy()
            #expect(viewModel.errorMessage == AutomaticSystemProxyRouting.neverUnavailableReason)
        }
    }

    @Test("Choke point: a caller that skips its own guard is still refused")
    func chokePointRefuses() async {
        await withMode(.never) {
            let coordinator = MainContentCoordinator()
            await #expect(throws: SystemProxyRoutingBlocked.self) {
                try await coordinator.enableSystemProxySyncingRefusal(port: 9_090)
            }
        }
    }

    @Test("Backstop: the manager itself refuses before touching any state")
    func managerBackstopRefuses() async {
        await withMode(.never) {
            await #expect(throws: SystemProxyRoutingBlocked.self) {
                try await SystemProxyManager.shared.enableSystemProxy(port: 9_090)
            }
        }
    }

    @Test("A refusal reported as a failure never marks routing expected")
    func blockedFailureIsNotAFault() {
        let coordinator = MainContentCoordinator()
        coordinator.readiness.setSystemRoutingExpected(true)
        coordinator.reportEnableFailure(SystemProxyRoutingBlocked())
        #expect(!coordinator.readiness.systemRoutingExpected)
        #expect(coordinator.readiness.activeWarning == nil)
    }

    @Test("Release is never blocked, in any mode")
    func releaseIsAlwaysPermitted() throws {
        for mode in SystemProxyRoutingMode.allCases {
            #expect(AutomaticSystemProxyRouting.permits(.release, mode: mode))
        }
        // The release entry points carry no routing-mode check at all.
        let manager = try source("Rockxy/Core/TrafficCapture/SystemProxyManager.swift")
        let disable = try #require(body(of: "func disableSystemProxy() async throws", in: manager))
        #expect(!disable.contains("AutomaticSystemProxyRouting"))
        let restore = try #require(body(of: "func restorePreviousProxySettings(", in: manager))
        #expect(!restore.contains("AutomaticSystemProxyRouting"))
        let recovery = try source("Rockxy/Views/Main/Extensions/MainContentCoordinator+DirectRecordRecovery.swift")
        let disableWrapper = try #require(body(of: "func disableSystemProxySyncingRefusal()", in: recovery))
        #expect(!disableWrapper.contains("AutomaticSystemProxyRouting"))
        let routing = try source("Rockxy/Views/Main/Extensions/MainContentCoordinator+SystemProxyRouting.swift")
        let switchOff = try #require(body(of: "func switchOffSystemProxyOverride()", in: routing))
        #expect(!switchOff.contains("AutomaticSystemProxyRouting"))
        #expect(!switchOff.contains("systemProxyAcquisitionAllowed"))
    }

    @Test("Controls that switch an active override off stay enabled in Never")
    func disabledControlReasons() {
        let never = SystemProxyRoutingMode.never.rawValue
        #expect(AutomaticSystemProxyRouting.acquisitionUnavailableReason(storedMode: never, isOverrideActive: false)
            == AutomaticSystemProxyRouting.neverUnavailableReason)
        #expect(AutomaticSystemProxyRouting.acquisitionUnavailableReason(storedMode: never, isOverrideActive: true)
            == nil)
        for mode in [SystemProxyRoutingMode.automatic, .manual] {
            #expect(AutomaticSystemProxyRouting.acquisitionUnavailableReason(
                storedMode: mode.rawValue, isOverrideActive: false
            ) == nil)
        }
        #expect(AutomaticSystemProxyRouting
            .acquisitionUnavailableReason(storedMode: "", isOverrideActive: false) == nil)
    }

    @Test("The menu, Advanced Settings and palette controls are disabled with the reason as help")
    func controlsCarryTheReason() throws {
        for path in ["Rockxy/RockxyApp.swift", "Rockxy/Views/Settings/AdvancedProxySettingsView.swift"] {
            let text = try source(path).filter { !$0.isWhitespace }
            #expect(text.contains("acquisitionUnavailableReason(storedMode:storedRoutingMode"))
            #expect(text.contains(".help(systemProxyUnavailableReason??\"\")"))
        }
        let palette = try source("Rockxy/Views/Main/CommandPaletteView.swift").filter { !$0.isWhitespace }
        #expect(palette.contains("[\"proxy.system\":$0]"))
        #expect(palette.contains("guardunavailableReasons[command.id]==nilelse"))
    }

    // MARK: Private

    private func withMode(_ mode: SystemProxyRoutingMode, _ body: () async throws -> Void) async rethrows {
        let previous = AutomaticSystemProxyRouting.modeProvider
        AutomaticSystemProxyRouting.modeProvider = { mode }
        defer { AutomaticSystemProxyRouting.modeProvider = previous }
        try await body()
    }

    private func source(_ relative: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Rockxy.xcodeproj").path) {
                return try String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// The text from `marker` to the next function declaration at the same indent.
    private func body(of marker: String, in text: String) -> String? {
        guard let start = text.range(of: marker) else {
            return nil
        }
        let rest = text[start.lowerBound...].dropFirst(marker.count)
        let end = rest.range(of: "\n    func ")?.lowerBound
            ?? rest.range(of: "\n    @discardableResult")?.lowerBound
            ?? rest.endIndex
        return String(rest[..<end])
    }
}
