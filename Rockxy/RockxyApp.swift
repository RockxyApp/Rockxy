import AppKit
import Combine
import os
import SwiftUI
import UniformTypeIdentifiers

// Application entry point. Declares the main window scene with `ContentView`,
// the native Settings utility window, and the full set of custom menu bar commands.

// MARK: - AppLifecycleState

@MainActor @Observable
final class AppLifecycleState {
    var showWelcome = false
    var showKeyboardShortcuts = false
    var showCommandPalette = false
}

// MARK: - RockxyApp

@main
struct RockxyApp: App {
    // MARK: Lifecycle

    @MainActor
    init() {
        let projectRepository: ProjectCatalogPersisting? = RockxyIdentity.isRunningTests
            ? nil
            : ProjectCatalogRepository()
        let coordinator = MainContentCoordinator(projectCatalogRepository: projectRepository)
        _mainCoordinator = State(initialValue: coordinator)
        ExternalDocumentOpenRouter.shared.register(coordinator: coordinator)

        // Nearby transfer belongs to the app lifecycle, not the main-window
        // lifecycle. macOS can restore Rockxy with no open windows, and the
        // iPhone must still be able to discover it while the app is running.
        if !RockxyIdentity.isRunningTests {
            coordinator.configureBabylonCaptureIntake()
            BabylonCaptureReceiver.shared.start(coordinator: coordinator, pairingStore: .shared)
            RockxyNearbyTransferReceiver.shared.start(coordinator: coordinator)
        }
    }

    // MARK: Internal

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window(RockxyIdentity.current.displayName, id: "main") {
            AppUIDisplayMetricsProvider {
                MainWindowContent(
                    lifecycleState: lifecycleState,
                    coordinator: mainCoordinator
                )
            }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(
            width: MainWindowLayoutMetrics.defaultWidth,
            height: MainWindowLayoutMetrics.defaultHeight
        )
        .defaultPosition(.center)
        .commands {
            RockxyMenuCommands(lifecycleState: lifecycleState, coordinator: mainCoordinator)
            BabylonCaptureCommands()
        }

        Window(String(localized: "Advanced Proxy Settings", bundle: RockxyLocalization.bundle), id: "advancedProxySettings") {
            ToolWindowDisplayMetricsProvider {
                AdvancedProxySettingsView(coordinator: mainCoordinator)
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Babylon Pairing", bundle: RockxyLocalization.bundle), id: "babylonPairing") {
            ToolWindowDisplayMetricsProvider {
                BabylonPairingView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 460, height: 420)

        Window(String(localized: "Babylon Runtime", bundle: RockxyLocalization.bundle), id: "babylonRuntime") {
            ToolWindowDisplayMetricsProvider {
                BabylonRuntimeView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 920, height: 660)

        developerSetupWindow

        settingsWindow

        ReverseProxyWindowScene()
        DNSSpoofingWindowScene()
        TLSKeyLogWindowScene()

        macCertificateSetupGuideWindow

        customCertificatesWindow

        Window(String(localized: "Automatic Setup", bundle: RockxyLocalization.bundle), id: "automaticSetup") {
            AppUIDisplayMetricsProvider {
                DeveloperSetupAutomaticWindowView(coordinator: mainCoordinator)
            }
        }
        .commandsRemoved()
        .defaultSize(width: 760, height: 520)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)

        Window(String(localized: "Manual Setup", bundle: RockxyLocalization.bundle), id: "manualSetup") {
            AppUIDisplayMetricsProvider {
                DeveloperSetupManualWindowView(coordinator: mainCoordinator)
            }
        }
        .commandsRemoved()
        .defaultSize(width: 780, height: 560)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)

        Window(String(localized: "Map Local", bundle: RockxyLocalization.bundle), id: "mapLocal") {
            ToolWindowDisplayMetricsProvider {
                MapLocalWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Map Local Editor", bundle: RockxyLocalization.bundle), id: "mapLocalEditor") {
            ToolWindowDisplayMetricsProvider {
                MapLocalEditorWindowView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 960, height: 640)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Map Remote", bundle: RockxyLocalization.bundle), id: "mapRemote") {
            ToolWindowDisplayMetricsProvider {
                MapRemoteWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Map Remote Editor", bundle: RockxyLocalization.bundle), id: "mapRemoteEditor") {
            ToolWindowDisplayMetricsProvider {
                MapRemoteEditorWindowView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 834, height: 584)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Block List", bundle: RockxyLocalization.bundle), id: "blockList") {
            ToolWindowDisplayMetricsProvider {
                BlockListWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Modify Headers", bundle: RockxyLocalization.bundle), id: "modifyHeaders") {
            ToolWindowDisplayMetricsProvider {
                ModifyHeaderWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Network Conditions", bundle: RockxyLocalization.bundle), id: "networkConditions") {
            ToolWindowDisplayMetricsProvider {
                NetworkConditionsWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "HTTPS Decryption", bundle: RockxyLocalization.bundle), id: "sslProxyingList") {
            ToolWindowDisplayMetricsProvider {
                SSLProxyingListView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Full Proxy Bypass", bundle: RockxyLocalization.bundle), id: "bypassProxyList") {
            ToolWindowDisplayMetricsProvider {
                BypassProxyListView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "External Proxy Settings", bundle: RockxyLocalization.bundle), id: "externalProxySettings") {
            ToolWindowDisplayMetricsProvider {
                ExternalProxySettingsView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 900, height: 680)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "SOCKS Proxy Settings", bundle: RockxyLocalization.bundle), id: "socksProxySettings") {
            ToolWindowDisplayMetricsProvider {
                SOCKSProxySettingsView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 640, height: 280)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Allow List", bundle: RockxyLocalization.bundle), id: "allowList") {
            ToolWindowDisplayMetricsProvider {
                AllowListWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Diff", bundle: RockxyLocalization.bundle), id: "diff") {
            ToolWindowDisplayMetricsProvider {
                DiffWindowView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 1_240, height: 820)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Scripting", bundle: RockxyLocalization.bundle), id: "scriptingList") {
            ToolWindowDisplayMetricsProvider {
                ScriptingListWindowView()
            }
        }
        .commandsRemoved()
        .defaultPosition(.center)
        .defaultSize(width: 1_120, height: 700)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Script Editor", bundle: RockxyLocalization.bundle), id: "scriptEditor") {
            ToolWindowDisplayMetricsProvider {
                ScriptEditorWindowView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 1_120, height: 720)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .rockxyDisablingRestorationOnModernMacOS()

        Window(String(localized: "Inspector Preview Tabs", bundle: RockxyLocalization.bundle), id: "bodyPreviewerTabs") {
            ToolWindowDisplayMetricsProvider {
                PreviewerTabSettingsView(store: mainCoordinator.previewTabStore)
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 820, height: 560)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Custom Header Columns", bundle: RockxyLocalization.bundle), id: "customColumns") {
            ToolWindowDisplayMetricsProvider {
                CustomHeaderColumnsView(store: mainCoordinator.headerColumnStore)
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 900, height: 620)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Protobuf Mapping", bundle: RockxyLocalization.bundle), id: "protobufSettings") {
            ToolWindowDisplayMetricsProvider {
                ProtobufSettingsWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 940, height: 620)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Local Protobuf Schemas", bundle: RockxyLocalization.bundle), id: "protobufSchemaList") {
            ToolWindowDisplayMetricsProvider {
                ProtobufSchemaListWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 820, height: 560)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Breakpoint Rules", bundle: RockxyLocalization.bundle), id: "breakpointRules") {
            ToolWindowDisplayMetricsProvider {
                BreakpointRulesWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Breakpoint Rule Editor", bundle: RockxyLocalization.bundle), id: "breakpointRuleEditor") {
            ToolWindowDisplayMetricsProvider {
                BreakpointRuleEditorWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Breakpoint Templates", bundle: RockxyLocalization.bundle), id: "breakpointTemplates") {
            ToolWindowDisplayMetricsProvider {
                BreakpointTemplateWindowView()
            }
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        Window(String(localized: "Breakpoint Queue", bundle: RockxyLocalization.bundle), id: "breakpoints") {
            ToolWindowDisplayMetricsProvider {
                BreakpointWindowView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 1_120, height: 720)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        composeWindow

        detachedInspectorWindow
    }

    // MARK: Private

    private static let identity = RockxyIdentity.current

    @State private var mainCoordinator: MainContentCoordinator

    @State private var lifecycleState = AppLifecycleState()

    private var developerSetupWindow: some Scene {
        DeveloperSetupWindowScene(coordinator: mainCoordinator)
    }

    private var settingsWindow: some Scene {
        SettingsWindowScene()
    }

    private var macCertificateSetupGuideWindow: some Scene {
        MacCertificateSetupGuideWindowScene()
    }

    private var customCertificatesWindow: some Scene {
        CustomCertificatesWindowScene()
    }

    private var composeWindow: some Scene {
        ComposeWindowScene()
    }

    private var detachedInspectorWindow: some Scene {
        DetachedInspectorWindowScene(coordinator: mainCoordinator)
    }
}

// MARK: - DetachedInspectorWindowScene

/// Standalone Inspector window pinned to one transaction. It is an intent-dependent
/// utility window, so restoration is disabled on macOS 15+ (mirroring the Compose /
/// Certificate scene wrappers) rather than re-opening empty after a relaunch.
private struct DetachedInspectorWindowScene: Scene {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some Scene {
        detachedInspectorWindow
    }

    // MARK: Private

    private var detachedInspectorWindow: some Scene {
        let base = Window(String(localized: "Inspector", bundle: RockxyLocalization.bundle), id: "detachedInspector") {
            AppUIDisplayMetricsProvider {
                DetachedInspectorWindowView(coordinator: coordinator)
            }
        }
        .commandsRemoved()
        .defaultSize(width: 1_040, height: 680)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)

        if #available(macOS 15.0, *) {
            return base.restorationBehavior(.disabled)
        } else {
            return base
        }
    }
}

// MARK: - CustomCertificatesWindowScene

/// Certificate identities are managed in a focused utility window with
/// predictable geometry rather than restoring a stale, oversized workspace.
private struct CustomCertificatesWindowScene: Scene {
    // MARK: Internal

    var body: some Scene {
        customCertificatesWindow
    }

    // MARK: Private

    private var customCertificatesWindow: some Scene {
        let base = Window(String(localized: "Custom Certificates", bundle: RockxyLocalization.bundle), id: "customCertificates") {
            ToolWindowDisplayMetricsProvider {
                CustomCertificatesView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 900, height: 620)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)

        if #available(macOS 15.0, *) {
            return base.restorationBehavior(.disabled)
        } else {
            return base
        }
    }
}

// MARK: - MacCertificateSetupGuideWindowScene

/// Certificate setup is a focused utility, so it opens at a predictable size
/// instead of inheriting geometry from a previous app session.
private struct MacCertificateSetupGuideWindowScene: Scene {
    // MARK: Internal

    var body: some Scene {
        macCertificateSetupGuideWindow
    }

    // MARK: Private

    private var macCertificateSetupGuideWindow: some Scene {
        let base = Window(String(localized: "Mac Setup Guide", bundle: RockxyLocalization.bundle), id: "certificateSetup") {
            ToolWindowDisplayMetricsProvider {
                MacCertificateSetupGuideView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 720, height: 500)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)

        if #available(macOS 15.0, *) {
            return base.restorationBehavior(.disabled)
        } else {
            return base
        }
    }
}

// MARK: - DeveloperSetupWindowScene

/// Developer Setup is a utility workspace, so it opens at a compact, predictable
/// size instead of restoring geometry that can make it rival the main window.
private struct DeveloperSetupWindowScene: Scene {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some Scene {
        developerSetupWindow
    }

    // MARK: Private

    private var developerSetupWindow: some Scene {
        let base = Window(String(localized: "Developer Setup", bundle: RockxyLocalization.bundle), id: "developerSetupHub") {
            AppUIDisplayMetricsProvider {
                DeveloperSetupWindowView(coordinator: coordinator)
            }
        }
        .commandsRemoved()
        .defaultSize(width: 1_000, height: 640)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)

        if #available(macOS 15.0, *) {
            return base.restorationBehavior(.disabled)
        } else {
            return base
        }
    }
}

// MARK: - ComposeWindowScene

/// Compose window scene with restoration disabled on macOS 15+.
/// On macOS 14, the window may auto-restore on relaunch (acceptable degradation).
private struct ComposeWindowScene: Scene {
    // MARK: Internal

    var body: some Scene {
        composeWindow
    }

    // MARK: Private

    private var composeWindow: some Scene {
        let base = Window(String(localized: "Compose", bundle: RockxyLocalization.bundle), id: "compose") {
            ToolWindowDisplayMetricsProvider {
                ComposeWindowView()
            }
        }
        .commandsRemoved()
        .defaultSize(width: 1_120, height: 720)
        .defaultPosition(.center)
        .windowToolbarStyle(.unifiedCompact)

        if #available(macOS 15.0, *) {
            return base.restorationBehavior(.disabled)
        } else {
            return base
        }
    }
}

// MARK: - Scene restoration helper

private extension Scene {
    /// Disable window-state restoration on macOS 15+ so intent-dependent windows
    /// (like the Script Editor) never re-open empty after a relaunch. On macOS 14
    /// the window may auto-restore (acceptable degradation), mirroring the
    /// Compose / Certificate scene wrappers.
    func rockxyDisablingRestorationOnModernMacOS() -> some Scene {
        if #available(macOS 15.0, *) {
            return restorationBehavior(.disabled)
        } else {
            return self
        }
    }
}

// MARK: - MainWindowContent

private struct MainWindowContent: View {
    // MARK: Internal

    let lifecycleState: AppLifecycleState
    let coordinator: MainContentCoordinator

    var body: some View {
        ContentView(coordinator: coordinator)
            .sheet(isPresented: Binding(
                get: { lifecycleState.showWelcome },
                set: { lifecycleState.showWelcome = $0 }
            )) {
                WelcomeView(isFirstLaunch: true, onComplete: { lifecycleState.showWelcome = false },
                            onClose: { lifecycleState.showWelcome = false },
                            onEnableSystemProxy: { try await coordinator.enableSystemProxyFromWelcome() })
            }
            .sheet(isPresented: Binding(
                get: { lifecycleState.showKeyboardShortcuts },
                set: { lifecycleState.showKeyboardShortcuts = $0 }
            )) {
                KeyboardShortcutsView()
            }
            .modifier(CommandPaletteSheet(lifecycleState: lifecycleState, coordinator: coordinator))
            .task {
                guard !setupChecked else {
                    return
                }
                setupChecked = true

                // Present onboarding before asynchronous setup checks. Otherwise closing the
                // sheet during a check can be undone when that check finishes.
                if showWelcomeOnLaunch {
                    lifecycleState.showWelcome = true
                }

                // Migration backfill: if all setup steps are already satisfied, mark onboarding complete
                if !onboardingCompletedOnce {
                    let certInstalled = await CertificateManager.shared.isRootCAInstalled()
                    let certTrusted = await CertificateManager.shared.isRootCATrusted()
                    let helperOK = HelperManager.shared.status == .installedCompatible
                        && !HelperManager.shared.automaticRefreshRecoveryPending
                    let proxyOK = await SystemProxyManager.shared.isSystemProxyEnabledAsync()
                    if certInstalled, certTrusted, helperOK, proxyOK {
                        onboardingCompletedOnce = true
                    }
                }

                // "Show on startup" is an explicit opt-out that must win even while setup is
                // incomplete: a device-only workflow may never enable the system proxy, and the
                // sheet stays reachable from Help > Welcome to Rockxy.
            }
    }

    // MARK: Private

    private static let identity = RockxyIdentity.current

    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true
    @AppStorage(RockxyIdentity.current.defaultsKey("onboardingCompletedOnce")) private var onboardingCompletedOnce =
        false
    @State private var setupChecked = false
}

// MARK: - ProjectLinks

private enum ProjectLinks {
    static let homepage = "https://rockxy.io"
    static let repository = "https://github.com/RockxyApp/Rockxy"
    static let wiki = "\(repository)/wiki"
    static let issues = "\(repository)/issues"

    static var repositoryURL: URL? {
        URL(string: repository)
    }
}

// MARK: - RockxyMenuCommands

/// Defines Rockxy's full menu bar structure: File (session/export), Edit (copy as cURL),
/// View (layout/tabs), Flow (replay/clear), Tools (proxy control), Diff, Scripting,
/// Certificate, and Help. Actions are dispatched via `MainContentCommandActions`
/// through the focused scene value pattern.
struct RockxyMenuCommands: Commands {
    // MARK: Internal

    let lifecycleState: AppLifecycleState
    let coordinator: MainContentCoordinator

    var body: some Commands {
        appMenu
        fileMenu
        editMenu
        projectMenu
        viewMenu
        flowMenu
        toolsMenu
        secondaryMenus
        helpMenu
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MenuCommands")

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.commandActions) private var actions: MainContentCommandActions?
    @ObservedObject private var updater = AppUpdater.shared

    /// The focused-scene value is nil whenever a tool window (Settings, Map Local, Compose, …)
    /// is key. Menu commands still target the single main workspace in that case instead of
    /// silently doing nothing, so ⌘O / ⌥⌘N / ⌘K keep working from any window.
    private var proxyActions: MainContentCommandActions { actions ?? MainContentCommandActions(coordinator: coordinator) }

    @AppStorage(NoCacheHeaderMutator.userDefaultsKey) private var isNoCachingEnabled = false
    @StateObject private var externalProxyMenuState = ExternalProxyMenuState()

    private let certificateRouter = CertificateMenuActionRouter()

    @CommandsBuilder private var appMenu: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About \(RockxyIdentity.current.displayName)", bundle: RockxyLocalization.bundle)) {
                showAboutPanel()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "Check for Updates…", bundle: RockxyLocalization.bundle)) {
                updater.checkForUpdates()
            }
            .disabled(!updater.canInitiateUpdateCheck)

            Divider()

            Button(String(localized: "Change Logs…", bundle: RockxyLocalization.bundle)) {
                updater.openFullChangelog()
            }

            Divider()

            Button(String(localized: "Settings…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private var fileMenu: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Tab", bundle: RockxyLocalization.bundle)) {
                proxyActions.newWorkspaceTab()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(!proxyActions.canCreateWorkspaceTab)

            Button(String(localized: "Close Tab", bundle: RockxyLocalization.bundle)) {
                proxyActions.closeWorkspaceTab()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(!proxyActions.canCloseWorkspaceTab)

            Button(String(localized: "Rename Tab…", bundle: RockxyLocalization.bundle)) {
                proxyActions.renameWorkspaceTab()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!proxyActions.canRenameWorkspaceTab)

            Button(String(localized: "New Session", bundle: RockxyLocalization.bundle)) {
                proxyActions.clearSession()
            }

            Divider()

            Button(String(localized: "Open Session…", bundle: RockxyLocalization.bundle)) {
                proxyActions.openSession()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button(String(localized: "Save Session…", bundle: RockxyLocalization.bundle)) {
                proxyActions.saveSession()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Import HAR…", bundle: RockxyLocalization.bundle)) {
                proxyActions.importHAR()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button(String(localized: "Export HAR…", bundle: RockxyLocalization.bundle)) {
                proxyActions.exportHAR()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button(String(localized: "Export CSV…", bundle: RockxyLocalization.bundle)) {
                proxyActions.exportCSV()
            }
            .disabled(!proxyActions.hasVisibleTransactions)

            Button(String(localized: "Export Rockxy Session…", bundle: RockxyLocalization.bundle)) {
                proxyActions.exportRockxySession()
            }
            .disabled(!proxyActions.hasVisibleTransactions)

            Button(String(localized: "Export OpenAPI YAML…", bundle: RockxyLocalization.bundle)) {
                proxyActions.exportOpenAPIYAML()
            }
            .disabled(!proxyActions.canExportOpenAPI)

            Button(String(localized: "Export OpenAPI HTML…", bundle: RockxyLocalization.bundle)) {
                proxyActions.exportOpenAPIHTML()
            }
            .disabled(!proxyActions.canExportOpenAPI)
        }
    }

    private var editMenu: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button(String(localized: "Copy URL", bundle: RockxyLocalization.bundle)) {
                proxyActions.copyURL()
            }
            .keyboardShortcut("u", modifiers: [.command, .option])
            .disabled(!proxyActions.hasSelectedTransaction)

            Button(String(localized: "Copy as cURL", bundle: RockxyLocalization.bundle)) {
                proxyActions.copyAsCURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!proxyActions.hasSelectedTransaction)

            Button(String(localized: "Focus on URL", bundle: RockxyLocalization.bundle)) {
                proxyActions.focusSearchField()
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button(String(localized: "Find in Capture", bundle: RockxyLocalization.bundle)) {
                proxyActions.focusSearchField()
            }
            .keyboardShortcut("f", modifiers: [.command])
        }
    }

    private var projectMenu: some Commands {
        CommandMenu(String(localized: "Project", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "New Project…", bundle: RockxyLocalization.bundle)) {
                proxyActions.newProject()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!proxyActions.canCreateProject)

            Button(String(localized: "Rename Project…", bundle: RockxyLocalization.bundle)) {
                proxyActions.renameActiveProject()
            }
            .disabled(!proxyActions.canEditProjects)

            Button(String(localized: "Manage Projects…", bundle: RockxyLocalization.bundle)) {
                proxyActions.manageProjects()
            }

            Divider()

            Button(String(localized: "Export Project Configuration…", bundle: RockxyLocalization.bundle)) {
                proxyActions.exportProjectConfiguration()
            }
            .disabled(!proxyActions.canEditProjects)

            Button(String(localized: "Import Project Configuration…", bundle: RockxyLocalization.bundle)) {
                proxyActions.importProjectConfiguration()
            }
            .disabled(!proxyActions.canCreateProject)

            Divider()

            ForEach(proxyActions.projects) { project in
                Button {
                    proxyActions.switchProject(id: project.id)
                } label: {
                    if project.id == proxyActions.activeProjectID {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
                .disabled(!proxyActions.canEditProjects)
            }

            if proxyActions.projectsNeedRecovery {
                Divider()
                Button(String(localized: "Repair Projects…", bundle: RockxyLocalization.bundle)) {
                    proxyActions.showProjectRecovery()
                }
            }
        }
    }

    private var viewMenu: some Commands {
        CommandGroup(after: .toolbar) {
            Button(proxyActions.advancedFiltersMenuTitle) {
                proxyActions.toggleFilterBar()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button(String(localized: "Search Apps and Domains", bundle: RockxyLocalization.bundle)) {
                proxyActions.focusSidebarSearchField()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button(String(localized: "Command Palette…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "main")
                lifecycleState.showCommandPalette = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Toggle(
                String(localized: "Follow Live Traffic", bundle: RockxyLocalization.bundle),
                isOn: Binding(
                    get: { proxyActions.isFollowingLiveTraffic },
                    set: { proxyActions.setFollowingLiveTraffic($0) }
                )
            )
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button(
                proxyActions.isShowingTrafficInsights
                    ? String(localized: "Hide Traffic Insights", bundle: RockxyLocalization.bundle)
                    : String(localized: "Show Traffic Insights", bundle: RockxyLocalization.bundle)
            ) {
                proxyActions.toggleTrafficInsights()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Toggle Source List Panel", bundle: RockxyLocalization.bundle)) {
                proxyActions.toggleSourceList()
            }
            .keyboardShortcut("[", modifiers: [.command, .control])

            Divider()

            Button(
                proxyActions.isBottomInspectorVisible
                    ? String(localized: "Hide Bottom Inspector", bundle: RockxyLocalization.bundle)
                    : String(localized: "Show Bottom Inspector", bundle: RockxyLocalization.bundle)
            ) {
                proxyActions.toggleInspectorBottom()
            }
            .keyboardShortcut("]", modifiers: [.command, .control])
            .disabled(!proxyActions.canToggleBottomInspector)

            Button(
                proxyActions.isContextDockVisible
                    ? String(localized: "Hide Context Dock", bundle: RockxyLocalization.bundle)
                    : String(localized: "Show Context Dock", bundle: RockxyLocalization.bundle)
            ) {
                proxyActions.toggleInspectorRight()
            }
            .keyboardShortcut("\\", modifiers: [.command, .control])

            Button(
                proxyActions.isTrafficSplitViewVisible
                    ? String(localized: "Hide Split View", bundle: RockxyLocalization.bundle)
                    : String(localized: "Show Split View", bundle: RockxyLocalization.bundle)
            ) {
                proxyActions.toggleTrafficSplitView()
            }

            Divider()

            Button(String(localized: "Select Next Tab", bundle: RockxyLocalization.bundle)) {
                proxyActions.nextWorkspaceTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button(String(localized: "Select Previous Tab", bundle: RockxyLocalization.bundle)) {
                proxyActions.previousWorkspaceTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            WorkspaceTabNumberCommands(actions: proxyActions)

            Divider()

            Button(String(localized: "Jump to First Request", bundle: RockxyLocalization.bundle)) {
                proxyActions.selectFirstTransaction()
            }
            .disabled(!proxyActions.hasVisibleTransactions)

            Button(String(localized: "Jump to Last Request", bundle: RockxyLocalization.bundle)) {
                proxyActions.selectLastTransaction()
            }
            .disabled(!proxyActions.hasVisibleTransactions)
        }
    }

    private var flowMenu: some Commands {
        CommandMenu(String(localized: "Flow", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Compose…", bundle: RockxyLocalization.bundle)) {
                proxyActions.composeFreshRequest()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button(String(localized: "Repeat", bundle: RockxyLocalization.bundle)) {
                proxyActions.replayRequest()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!proxyActions.canRepeatSelection)

            Button(String(localized: "Edit and Repeat…", bundle: RockxyLocalization.bundle)) {
                proxyActions.editAndRepeat()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!proxyActions.hasSelectedTransaction)

            Divider()

            FlowExportMenu(actions: proxyActions)

            Divider()

            Button(String(localized: "Add Note…", bundle: RockxyLocalization.bundle)) {
                proxyActions.addComment()
            }
            .disabled(!proxyActions.hasSelectedTransaction)

            Menu(String(localized: "Highlight", bundle: RockxyLocalization.bundle)) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button(color.rawValue.capitalized) {
                        proxyActions.setHighlight(color)
                    }
                }
                Divider()
                Button(String(localized: "Remove Highlight", bundle: RockxyLocalization.bundle)) {
                    proxyActions.setHighlight(nil)
                }
            }
            .disabled(!proxyActions.hasSelectedTransaction)

            Divider()

            Button(String(localized: "Clear Session", bundle: RockxyLocalization.bundle)) {
                proxyActions.clearSession()
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button(String(localized: "Clear Session and Filters", bundle: RockxyLocalization.bundle)) {
                proxyActions.clearCaptureAndFilters()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle)) {
                proxyActions.deleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(!proxyActions.hasSelectedTransaction)
        }
    }

    private var toolsMenu: some Commands {
        CommandMenu(String(localized: "Tools", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Start Proxy", bundle: RockxyLocalization.bundle)) {
                proxyActions.startProxy()
            }
            .disabled(proxyActions.isProxyRunning)

            Button(String(localized: "Stop Proxy", bundle: RockxyLocalization.bundle)) {
                proxyActions.stopProxy()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!proxyActions.isProxyRunning)

            Button(
                !proxyActions.isRecording
                    ? String(localized: "Resume Recording", bundle: RockxyLocalization.bundle)
                    : String(localized: "Pause Recording", bundle: RockxyLocalization.bundle)
            ) {
                proxyActions.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!proxyActions.canToggleRecording)

            Button(String(localized: "Toggle System Proxy", bundle: RockxyLocalization.bundle)) {
                proxyActions.toggleSystemProxyOverride()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(!proxyActions.canToggleSystemProxyOverride)

            Divider()

            Button(String(localized: "Debug My App…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "developerSetupHub")
            }

            Divider()

            Toggle(String(localized: "No Caching", bundle: RockxyLocalization.bundle), isOn: $isNoCachingEnabled)
                .keyboardShortcut("c", modifiers: [.command, .option])

            Divider()

            Button(String(localized: "HTTPS Decryption…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "sslProxyingList")
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button(String(localized: "Full Proxy Bypass…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "bypassProxyList")
            }
            .keyboardShortcut("b", modifiers: [.command, .option])

            Menu(String(localized: "Proxy Settings", bundle: RockxyLocalization.bundle)) {
                Toggle(
                    String(localized: "Use External Proxy", bundle: RockxyLocalization.bundle),
                    isOn: externalProxyEnabledBinding
                )
                .help(externalProxyMenuState.isEnabled
                    ? String(localized: "External Proxy is on", bundle: RockxyLocalization.bundle)
                    : String(localized: "External Proxy is off", bundle: RockxyLocalization.bundle))
                .keyboardShortcut("e", modifiers: [.command, .option])

                Button(String(localized: "External Proxy Settings…", bundle: RockxyLocalization.bundle)) {
                    openWindow(id: "externalProxySettings")
                }
            }

            Divider()

            Button(String(localized: "Breakpoint Rules…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "breakpointRules")
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button(String(localized: "Add Breakpoint Rule", bundle: RockxyLocalization.bundle)) {
                proxyActions.addBreakpointRuleForSelection()
            }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(!proxyActions.hasSelectedTransaction)

            Button(String(localized: "Breakpoint Queue…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "breakpoints")
            }

            Button(String(localized: "Breakpoint Templates…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "breakpointTemplates")
            }

            Divider()

            Button(String(localized: "Map Local…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "mapLocal")
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Button(String(localized: "Map Remote…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "mapRemote")
            }

            Divider()

            Button(String(localized: "Block List…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "blockList")
            }
            .keyboardShortcut("[", modifiers: [.command, .option])

            Button(String(localized: "Allow List…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "allowList")
            }
            .keyboardShortcut("a", modifiers: [.command, .option])

            Button(String(localized: "Modify Headers…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "modifyHeaders")
            }

            Divider()

            Button(String(localized: "Protobuf…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "protobufSettings")
            }

            Button(String(localized: "Network Conditions…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "networkConditions")
            }
            ConnectionToolsMenuItems()

            Divider()

            Button(String(localized: "Inspector Preview Tabs…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "bodyPreviewerTabs")
            }

            Button(String(localized: "Custom Header Columns…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "customColumns")
            }
        }
    }

    private var diffMenu: some Commands {
        CommandMenu(String(localized: "Diff", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Open Diff View…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "diff")
            }
            .keyboardShortcut("y", modifiers: [.command, .option])

            Divider()

            Button(String(localized: "Compare Selected", bundle: RockxyLocalization.bundle)) {
                proxyActions.compareSelected()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(!proxyActions.canCompareSelected)
        }
    }

    private var scriptingMenu: some Commands {
        CommandMenu(String(localized: "Scripting", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Script List…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "scriptingList")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    @CommandsBuilder private var secondaryMenus: some Commands {
        diffMenu
        scriptingMenu
        certificateMenu
        setupMenu
    }

    private var certificateMenu: some Commands {
        CommandMenu(String(localized: "Certificate", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Install Certificate on This Mac…", bundle: RockxyLocalization.bundle)) {
                dispatchCertificateAction(.installOnMac)
            }

            Divider()

            Menu(String(localized: "Install Certificate on iOS", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "iOS Simulator…", bundle: RockxyLocalization.bundle)) {
                    dispatchCertificateAction(.installOniOSSimulator)
                }
                Button(String(localized: "Physical iPhone or iPad…", bundle: RockxyLocalization.bundle)) {
                    dispatchCertificateAction(.installOniOSDevice)
                }
            }

            Menu(String(localized: "Install Certificate on Android", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "Android Emulator…", bundle: RockxyLocalization.bundle)) {
                    dispatchCertificateAction(.installOnAndroidEmulator)
                }
                Button(String(localized: "Android Device…", bundle: RockxyLocalization.bundle)) {
                    dispatchCertificateAction(.installOnAndroidDevice)
                }
            }

            Divider()

            Button(String(localized: "Install Certificate on Java VMs…", bundle: RockxyLocalization.bundle)) {
                dispatchCertificateAction(.installOnJavaVMs)
            }

            Menu(String(localized: "Install Certificate on Developments", bundle: RockxyLocalization.bundle)) {
                Button(String(localized: "Flutter…", bundle: RockxyLocalization.bundle)) {
                    dispatchCertificateAction(.installOnDevelopment(.flutter))
                }
                Button(String(localized: "React Native…", bundle: RockxyLocalization.bundle)) {
                    dispatchCertificateAction(.installOnDevelopment(.reactNative))
                }
                Button(String(localized: "Electron…", bundle: RockxyLocalization.bundle)) {
                    dispatchCertificateAction(.installOnDevelopment(.electronJS))
                }
                Button(String(localized: "Next.js…", bundle: RockxyLocalization.bundle)) {
                    dispatchCertificateAction(.installOnDevelopment(.nextJS))
                }
            }

            Button(String(localized: "Install Certificate on Firefox Browsers…", bundle: RockxyLocalization.bundle)) {
                dispatchCertificateAction(.installOnFirefox)
            }

            Divider()

            Button(String(localized: "Add Custom Certificates…", bundle: RockxyLocalization.bundle)) {
                dispatchCertificateAction(.addCustomCertificates)
            }

            Divider()

            Menu(String(localized: "Export", bundle: RockxyLocalization.bundle)) {
                ForEach(CertificateExportFormat.allCases, id: \.self) { format in
                    Button(format.menuTitle) {
                        dispatchCertificateAction(.export(format))
                    }
                }
            }

            Divider()

            Button(String(localized: "Reset all Rockxy Certificates", bundle: RockxyLocalization.bundle)) {
                dispatchCertificateAction(.resetAll)
            }
        }
    }

    private var setupMenu: some Commands {
        CommandMenu(String(localized: "Setup", bundle: RockxyLocalization.bundle)) {
            Button(String(localized: "Automatic Setup...", bundle: RockxyLocalization.bundle)) {
                _ = DeveloperSetupRouteStore.shared
                    .requestAutomatic(targetID: DeveloperSetupRouteStore.defaultRuntimeTargetID)
                openWindow(id: "automaticSetup")
            }

            Divider()

            Button(String(localized: "Manual Setup...", bundle: RockxyLocalization.bundle)) {
                DeveloperSetupRouteStore.shared
                    .requestManual(targetID: DeveloperSetupRouteStore.defaultRuntimeTargetID)
                openWindow(id: "manualSetup")
            }
        }
    }

    private var helpMenu: some Commands {
        CommandGroup(replacing: .help) {
            Button(String(localized: "Getting Started…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "main")
                lifecycleState.showWelcome = true
            }

            Button(String(localized: "Keyboard Shortcuts", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "main")
                lifecycleState.showKeyboardShortcuts = true
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])

            Button(String(localized: "Debug My App…", bundle: RockxyLocalization.bundle)) {
                openWindow(id: "developerSetupHub")
            }

            Divider()

            Button(String(localized: "Force Reset Rockxy Helper…", bundle: RockxyLocalization.bundle)) {
                let commandActions = proxyActions
                HelperRecoveryPresenter.presentForceReset {
                    commandActions.stopProxy()
                }
            }

            Divider()

            Button(String(localized: "Homepage…", bundle: RockxyLocalization.bundle)) {
                openURL(ProjectLinks.homepage)
            }

            Button(String(localized: "Github…", bundle: RockxyLocalization.bundle)) {
                openURL(ProjectLinks.repository)
            }

            Button(String(localized: "Technical Documents…", bundle: RockxyLocalization.bundle)) {
                openURL(ProjectLinks.wiki)
            }

            Divider()

            Button(String(localized: "Report Bug…", bundle: RockxyLocalization.bundle)) {
                openURL(ProjectLinks.issues)
            }

            Button(String(localized: "Copy Debug Info…", bundle: RockxyLocalization.bundle)) {
                copyDebugInfo()
            }
        }
    }

    private var externalProxyEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                externalProxyMenuState.isEnabled
            },
            set: { isEnabled in
                setExternalProxyEnabled(isEnabled)
            }
        )
    }

    private func setExternalProxyEnabled(_ isEnabled: Bool) {
        do {
            try UpstreamProxyStore.shared.setEnabled(isEnabled)
            externalProxyMenuState.refresh()
        } catch {
            externalProxyMenuState.refresh()
            if isEnabled {
                openWindow(id: "externalProxySettings")
            }
            Self.logger.error("Failed to toggle External Proxy: \(error.localizedDescription)")
        }
    }

    private func dispatchCertificateAction(_ action: CertificateMenuAction) {
        switch certificateRouter.route(for: action) {
        case .openCertificateSetupGuide:
            openWindow(id: "certificateSetup")
        case let .openDeveloperSetup(targetID, tab):
            DeveloperSetupRouteStore.shared.request(targetID: targetID, tab: tab)
            openWindow(id: "developerSetupHub")
        case .openCustomCertificates:
            openWindow(id: "customCertificates")
        case let .export(format):
            CertificateExportPanelPresenter().export(format: format)
        case .resetAll:
            confirmAndResetCertificates()
        }
    }

    private func confirmAndResetCertificates() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Reset all Rockxy Certificates?", bundle: RockxyLocalization.bundle)
        alert.informativeText = String(
            localized: "This removes Rockxy's generated root CA, trust settings, cached host certificates, and custom certificate records.",
            bundle: RockxyLocalization.bundle
        )
        alert.addButton(withTitle: String(localized: "Reset", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            do {
                try await CertificateManager.shared.reset()
                try CustomCertificateManager.shared.deleteAll()
                await MainActor.run {
                    AppSettingsManager.shared.updateLastExportedRootCAPath(nil)
                }
            } catch {
                await MainActor.run {
                    showCertificateError(error.localizedDescription)
                }
            }
        }
    }

    private func showCertificateError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Certificate Action Failed", bundle: RockxyLocalization.bundle)
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
        alert.runModal()
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let credits = NSMutableAttributedString(
            string: String(localized: "The Rockxy Community source edition is licensed under AGPL-3.0-or-later.\n", bundle: RockxyLocalization.bundle)
        )

        if let homepage = ProjectLinks.repositoryURL {
            let linkText = String(localized: "View the public source and license on GitHub", bundle: RockxyLocalization.bundle)
            let link = NSMutableAttributedString(string: linkText)
            link.addAttribute(.link, value: homepage, range: NSRange(location: 0, length: link.length))
            credits.append(link)
        }
        let noticesURL = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt")
            ?? Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt", subdirectory: "Legal")
        if let noticesURL {
            credits.append(NSAttributedString(string: "\n"))
            let notices = NSMutableAttributedString(string: String(localized: "Third-Party Software Notices", bundle: RockxyLocalization.bundle))
            notices.addAttribute(.link, value: noticesURL, range: NSRange(location: 0, length: notices.length))
            credits.append(notices)
        }

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: RockxyIdentity.current.displayName,
            .applicationVersion: version,
            .version: String(localized: "Build \(build)", bundle: RockxyLocalization.bundle),
            .credits: credits,
        ]

        if let applicationIcon = NSApplication.shared.applicationIconImage {
            options[.applicationIcon] = applicationIcon
        }

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    private func copyDebugInfo() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let info = "\(RockxyIdentity.current.displayName) \(version) (\(build)) / macOS \(osVersion)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
}
