import AppKit
import Combine
import SwiftUI

// MARK: - MainWindowLayoutMetrics

enum MainWindowLayoutMetrics {
    static let defaultWidth: CGFloat = 1_200
    static let defaultHeight: CGFloat = 760
    static let minimumWidth: CGFloat = 960
    static let minimumHeight: CGFloat = 620
    static let sidebarMinimumWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 250
    static let sidebarMaximumWidth: CGFloat = 350
    static let workspaceMinimumWidth: CGFloat = 320
    static let contextDockMinimumWidth: CGFloat = 260
    static let contextDockIdealWidth: CGFloat = 320
}

// MARK: - ContentView

/// Root view of the main window. Sets up a native three-pane workspace with
/// `SidebarView` on the left, `CenterContentView` in the detail area, and the
/// Context Dock inspector on the right.
/// Uses the app-owned `MainContentCoordinator` that drives all data flow to child views.
struct ContentView: View {
    // MARK: Lifecycle

    init(
        coordinator: MainContentCoordinator,
        managesLifecycle: Bool = true,
        representedWorkspaceID: UUID? = nil
    ) {
        _coordinator = Bindable(coordinator)
        self.managesLifecycle = managesLifecycle
        self.representedWorkspaceID = representedWorkspaceID
    }

    // MARK: Internal

    var body: some View {
        NativeWorkspaceSplitView(
            isSidebarPresented: $isSidebarPresented,
            isInspectorPresented: contextDockVisibility,
            autosaveName: Self.workspaceSplitAutosaveName,
            sidebarMinimumWidth: MainWindowLayoutMetrics.sidebarMinimumWidth,
            sidebarIdealWidth: MainWindowLayoutMetrics.sidebarIdealWidth,
            sidebarMaximumWidth: MainWindowLayoutMetrics.sidebarMaximumWidth,
            workspaceMinimumWidth: MainWindowLayoutMetrics.workspaceMinimumWidth,
            inspectorMinimumWidth: MainWindowLayoutMetrics.contextDockMinimumWidth,
            inspectorIdealWidth: MainWindowLayoutMetrics.contextDockIdealWidth,
            toolbarConfiguration: NativeWorkspaceToolbarConfiguration(
                coordinator: coordinator,
                onOpenDeveloperHub: { openWindow(id: "developerSetupHub") },
                onOpenToolWindow: { id in openWindow(id: id) }
            )
        ) {
            SidebarView(coordinator: coordinator)
        } workspace: {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if let warning = coordinator.projectPersistenceWarningMessage {
                        SystemProxyWarningBanner(
                            message: warning,
                            primaryActionTitle: String(
                                localized: "Repair Projects…",
                                bundle: RockxyLocalization.bundle
                            ),
                            onPrimaryAction: {
                                coordinator.isProjectRecoveryPresented = true
                            }
                        )
                    }

                    if let warning = coordinator.systemProxyWarning {
                        SystemProxyWarningBanner(
                            message: warning.message,
                            primaryActionTitle: warning.action?.title,
                            onPrimaryAction: {
                                handleSystemProxyWarningAction(warning.action)
                            },
                            onDismiss: warning.isDismissible ? {
                                coordinator.readiness.dismissWarning()
                            } : nil
                        )
                    }

                    CenterContentView(
                        coordinator: coordinator,
                        onOpenToolWindow: { id in openWindow(id: id) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                toastOverlay
            }
            .animation(.easeOut(duration: 0.18), value: coordinator.activeToast?.id)
        } inspector: {
            ContextDockView(
                coordinator: coordinator,
                onOpenSettings: { openWindow(id: "settings") }
            )
        }
        .frame(
            minWidth: MainWindowLayoutMetrics.minimumWidth,
            minHeight: MainWindowLayoutMetrics.minimumHeight
        )
        // The native split owns the full window content area. AppKit then applies
        // the titlebar safe area to each hosted pane while keeping the semantic
        // sidebar/inspector backgrounds and split dividers continuous through
        // the unified toolbar, matching Xcode's window structure.
        .ignoresSafeArea(.container, edges: .top)
        .background {
            WorkspaceWindowAccessor(
                coordinator: coordinator,
                representedWorkspaceID: representedWorkspaceID
            )
            .frame(width: 0, height: 0)
        }
        .focusedSceneValue(\.commandActions, MainContentCommandActions(coordinator: coordinator))
        .modifier(ConditionalContentWindowNotificationHandlers(
            isEnabled: managesLifecycle,
            coordinator: coordinator,
            openWindow: openWindow
        ))
        .onAppear {
            guard managesLifecycle, !ProcessInfo.processInfo.isTestHost else {
                return
            }
            coordinator.configureSharedGates()
            coordinator.loadPersistedFavorites()
            coordinator.attachToMCPServer(MCPServerCoordinator.shared)
        }
        .onDisappear {
            guard managesLifecycle, !ProcessInfo.processInfo.isTestHost else {
                return
            }
            coordinator.detachFromMCPServer(MCPServerCoordinator.shared)
        }
        .task {
            // Skip startup tasks when running as a test host to avoid actor
            // contention between the app's loadInitialRules and test suites.
            guard managesLifecycle, !ProcessInfo.processInfo.isTestHost else {
                return
            }
            // Rule loading is app-level and must not wait on project hydration —
            // start the observer and kick off the (idempotent, non-blocking) load
            // before hydrating so Map Local and other rule tools have their
            // persisted rules regardless of how long project hydration takes.
            coordinator.setupRulesObserver()
            coordinator.loadInitialRules()
            await coordinator.hydrateProjectsOnLaunch()
            if case .failed = coordinator.projectStore.loadState {
                coordinator.isProjectRecoveryPresented = true
            } else {
                RockxyWorkspaceWindowManager.shared.projectDidChange(coordinator: coordinator)
            }
            coordinator.readiness.startObserving()
            coordinator.setupSSLProxyingObserver()
            // Share the app-level recovery barrier so startup cannot restore an old proxy after
            // this view has already enabled a new capture session.
            await SystemProxyStartupRecovery.task.value
            // Reconcile the helper with this app bundle before any automatic capture starts, so
            // an update cannot swap the helper out from under a session this view just enabled.
            await HelperUpdateStartupReconciliation.task.value
            coordinator.refreshProxyOverrideStatus()
            coordinator.startProxyOnLaunchIfNeeded()
            nearbyTransferReceiver.start(coordinator: coordinator)
        }
        .modifier(ConditionalScriptingWindowOpeners(isEnabled: managesLifecycle, openWindow: openWindow))
        .alert(
            String(localized: "Proxy Error", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { coordinator.proxyError != nil && !coordinator.isProxyRunning },
                set: {
                    if !$0 {
                        coordinator.proxyError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) {
                coordinator.proxyError = nil
            }
        } message: {
            if let error = coordinator.proxyError {
                Text(error)
            }
        }
        .alert(
            nearbyTransferTitle,
            isPresented: Binding(
                get: { nearbyTransferReceiver.pendingInvitation != nil },
                set: { isPresented in
                    if !isPresented, let invitation = nearbyTransferReceiver.pendingInvitation {
                        nearbyTransferReceiver.decline(invitation)
                    }
                }
            )
        ) {
            if let invitation = nearbyTransferReceiver.pendingInvitation {
                Button(String(localized: "Accept and Add iOS Workspace", bundle: RockxyLocalization.bundle)) {
                    nearbyTransferReceiver.approve(invitation)
                }
                Button(String(localized: "Decline", bundle: RockxyLocalization.bundle), role: .cancel) {
                    nearbyTransferReceiver.decline(invitation)
                }
            }
        } message: {
            if let invitation = nearbyTransferReceiver.pendingInvitation {
                Text(
                    "Code: \(invitation.verificationCode)\n\n\(invitation.sessionTitle) contains \(invitation.transactionCount) requests. Confirm the same code appears on \(invitation.deviceName). Your current Mac traffic will stay intact."
                )
            }
        }
        .sheet(item: $coordinator.importPreview) { preview in
            ImportReviewSheet(
                preview: preview,
                currentTransactionCount: coordinator.transactions.count,
                currentLogCount: coordinator.logEntries.count,
                onReplace: { coordinator.executeImport(preview) },
                onCancel: { coordinator.cancelImport() }
            )
        }
        .sheet(item: $coordinator.exportScopeContext) { context in
            ExportScopeSheet(
                context: context,
                onExport: { scope in coordinator.executeExport(context: context, scope: scope) },
                onCancel: { coordinator.exportScopeContext = nil }
            )
        }
        .sheet(item: $coordinator.gistPublishContext) { context in
            GistPublishConfirmationSheet(
                context: context,
                onPublish: { options in
                    try await coordinator.publishTransactionsToGist(context.transactions, options: options)
                },
                onCancel: { coordinator.gistPublishContext = nil }
            )
        }
        .sheet(item: Binding(
            get: {
                coordinator.isProjectManagerPresented ? nil : coordinator.projectNameEditorContext
            },
            set: { coordinator.projectNameEditorContext = $0 }
        )) { context in
            ProjectNameEditorSheet(context: context, coordinator: coordinator)
        }
        .sheet(isPresented: $coordinator.isProjectManagerPresented) {
            ProjectManagerSheet(coordinator: coordinator)
        }
        .sheet(isPresented: $coordinator.isProjectRecoveryPresented) {
            ProjectRecoverySheet(coordinator: coordinator)
        }
        .alert(
            String(localized: "Project Operation Failed", bundle: RockxyLocalization.bundle),
            isPresented: Binding(
                get: { coordinator.lastProjectOperationError != nil },
                set: {
                    if !$0 {
                        coordinator.lastProjectOperationError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK", bundle: RockxyLocalization.bundle)) {
                coordinator.lastProjectOperationError = nil
            }
        } message: {
            if let message = coordinator.projectOperationErrorMessage {
                Text(message)
            }
        }
        .appUIDisplayMetrics(displayMetrics)
    }

    // MARK: Private

    private static let workspaceSplitAutosaveName = RockxyIdentity.current.defaultsKey(
        // Establish compact utility panes once, then preserve every user-adjusted divider
        // position normally again.
        "nativeWorkspaceSplit.compactUtilityPanes.v1"
    )

    @Environment(\.openWindow) private var openWindow
    @Bindable private var coordinator: MainContentCoordinator
    @State private var nearbyTransferReceiver = RockxyNearbyTransferReceiver.shared
    @State private var isSidebarPresented = true

    private let settingsManager = AppSettingsManager.shared
    private let managesLifecycle: Bool
    private let representedWorkspaceID: UUID?

    private var displayMetrics: AppUIDisplayMetrics {
        AppUIDisplayMetrics(settings: settingsManager.appUI)
    }

    private var contextDockVisibility: Binding<Bool> {
        Binding(
            get: { coordinator.isContextDockVisible },
            set: { coordinator.setContextDockVisible($0) }
        )
    }

    private var nearbyTransferTitle: String {
        guard let invitation = nearbyTransferReceiver.pendingInvitation else {
            return String(localized: "Receive Rockxy iOS Session", bundle: RockxyLocalization.bundle)
        }
        return String(localized: "Receive from \(invitation.deviceName)?", bundle: RockxyLocalization.bundle)
    }

    @ViewBuilder private var toastOverlay: some View {
        if let toast = coordinator.activeToast {
            ToastView(message: toast) {
                coordinator.dismissToast(id: toast.id)
            }
            .id(toast.id)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .allowsHitTesting(false)
            .zIndex(100)
        }
    }

    private func handleSystemProxyWarningAction(_ action: SystemProxyWarning.Action?) {
        switch action {
        case .retry:
            coordinator.retrySystemProxy()
        case .retryStop:
            coordinator.stopProxy()
        case .retryDisableSystemRouting:
            coordinator.switchOffSystemProxyOverride()
        case .restoreSystemRouting:
            coordinator.retrySystemProxy()
        case .retryCaptureCheck:
            coordinator.runCaptureHealthCheck()
        case .openHTTPSDecryption:
            openWindow(id: "sslProxyingList")
        case .retryHTTPSInterception:
            coordinator.retryHTTPSInterception()
        case .openGeneralSettings:
            RockxySettingsTab.select(.general)
            openWindow(id: "settings")
        case .openAdvancedProxySettings:
            openWindow(id: "advancedProxySettings")
        case .reinstallAndTrust:
            Task { @MainActor in
                do {
                    try await CertificateManager.shared.installAndTrust()
                } catch {
                    coordinator.activeToast = ToastMessage(
                        style: .error,
                        text: String(
                            localized: "Failed to install certificate — \(error.localizedDescription)",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                }
                await ReadinessCoordinator.shared.deepRefresh()
            }
        case nil:
            break
        }
    }
}

// MARK: - WorkspaceWindowAccessor

private struct WorkspaceWindowAccessor: NSViewRepresentable {
    let coordinator: MainContentCoordinator
    let representedWorkspaceID: UUID?

    func makeNSView(context: Context) -> WorkspaceWindowAnchorView {
        let view = WorkspaceWindowAnchorView()
        view.coordinator = coordinator
        view.representedWorkspaceID = representedWorkspaceID
        return view
    }

    func updateNSView(_ nsView: WorkspaceWindowAnchorView, context: Context) {
        nsView.coordinator = coordinator
        nsView.representedWorkspaceID = representedWorkspaceID
        nsView.attachIfReady()
    }
}

// MARK: - WorkspaceWindowAnchorView

@MainActor
private final class WorkspaceWindowAnchorView: NSView {
    weak var coordinator: MainContentCoordinator?
    var representedWorkspaceID: UUID?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfReady()
    }

    func attachIfReady() {
        guard representedWorkspaceID == nil,
              let window,
              let coordinator else
        {
            return
        }
        NativeWorkspaceWindowChrome.configure(window)
        RockxyWorkspaceWindowManager.shared.registerPrimaryWindow(window, coordinator: coordinator)
    }
}

// MARK: - ConditionalContentWindowNotificationHandlers

private struct ConditionalContentWindowNotificationHandlers: ViewModifier {
    let isEnabled: Bool
    let coordinator: MainContentCoordinator
    let openWindow: OpenWindowAction

    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(ContentWindowNotificationHandlers(coordinator: coordinator, openWindow: openWindow))
        } else {
            content
        }
    }
}

// MARK: - ConditionalScriptingWindowOpeners

private struct ConditionalScriptingWindowOpeners: ViewModifier {
    let isEnabled: Bool
    let openWindow: OpenWindowAction

    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(ScriptingWindowOpeners(openWindow: openWindow))
        } else {
            content
        }
    }
}

// MARK: - ContentWindowNotificationHandlers

private struct ContentWindowNotificationHandlers: ViewModifier {
    let coordinator: MainContentCoordinator
    let openWindow: OpenWindowAction

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .breakpointHit)) { _ in
                openWindow(id: "breakpoints")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDiffWindow)) { _ in
                openWindow(id: "diff")
            }
            .onReceive(NotificationCenter.default.publisher(for: .stopProxyRequested)) { _ in
                coordinator.stopProxy()
            }
            .onReceive(NotificationCenter.default.publisher(for: .systemProxyDidChange)) { _ in
                coordinator.refreshProxyOverrideStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .systemProxyConfigurationDidChange)) { _ in
                coordinator.scheduleProxyOverrideRefresh()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: RockxyIdentity.current.notificationName("openCustomColumnsWindow")
            )) { _ in
                openWindow(id: "customColumns")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openComposeWindow)) { _ in
                openWindow(id: "compose")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openBlockListWindow)) { _ in
                openWindow(id: "blockList")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAllowListWindow)) { _ in
                openWindow(id: "allowList")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMapLocalWindow)) { _ in
                openWindow(id: "mapLocal")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMapRemoteWindow)) { _ in
                openWindow(id: "mapRemote")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNetworkConditionsWindow)) { _ in
                openWindow(id: "networkConditions")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openBreakpointRulesWindow)) { _ in
                openWindow(id: "breakpointRules")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSSLProxyingList)) { _ in
                openWindow(id: "sslProxyingList")
            }
    }
}

// MARK: - ProcessInfo + Test Host Detection

extension ProcessInfo {
    /// Returns `true` when the process is running as a test host (XCTest bundle loaded).
    var isTestHost: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
