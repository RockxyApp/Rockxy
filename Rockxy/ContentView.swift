import AppKit
import Combine
import SwiftUI

// MARK: - MainWindowLayoutMetrics

enum MainWindowLayoutMetrics {
    static let defaultWidth: CGFloat = 1_200
    static let defaultHeight: CGFloat = 760
    static let minimumWidth: CGFloat = 960
    static let minimumHeight: CGFloat = 620
}

// MARK: - ContentView

/// Root view of the main window. Sets up a two-column `NavigationSplitView` with
/// `SidebarView` on the left and `CenterContentView` as the detail area.
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
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(coordinator: coordinator)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
            } detail: {
                VStack(spacing: 0) {
                    if let warning = coordinator.systemProxyWarning {
                        SystemProxyWarningBanner(
                            message: warning.message,
                            primaryActionTitle: warning.action?.title,
                            onPrimaryAction: {
                                handleSystemProxyWarningAction(warning.action)
                            },
                            onDismiss: warning.isDismissible ? { coordinator.readiness.dismissWarning() } : nil
                        )
                    }

                    CenterContentView(
                        coordinator: coordinator,
                        onOpenToolWindow: { id in openWindow(id: id) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("")
                }
            }
        }
        .frame(
            minWidth: MainWindowLayoutMetrics.minimumWidth,
            minHeight: MainWindowLayoutMetrics.minimumHeight
        )
        .background {
            WorkspaceWindowAccessor(
                coordinator: coordinator,
                representedWorkspaceID: representedWorkspaceID
            )
            .frame(width: 0, height: 0)
        }
        .inspector(isPresented: contextDockVisibility) {
            ContextDockView(
                coordinator: coordinator,
                onOpenSettings: openSettings.callAsFunction
            )
            .inspectorColumnWidth(
                min: Self.minimumContextDockWidth,
                ideal: Self.idealContextDockWidth,
                max: Self.maximumContextDockWidth
            )
        }
        .focusedSceneValue(\.commandActions, MainContentCommandActions(coordinator: coordinator))
        .toolbar {
            ProxyToolbarContent(coordinator: coordinator)
        }
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
            coordinator.readiness.startObserving()
            coordinator.setupRulesObserver()
            coordinator.setupSSLProxyingObserver()
            coordinator.loadInitialRules()
            coordinator.refreshProxyOverrideStatus()
            coordinator.startProxyOnLaunchIfNeeded()
            nearbyTransferReceiver.start(coordinator: coordinator)
        }
        .modifier(ConditionalScriptingWindowOpeners(isEnabled: managesLifecycle, openWindow: openWindow))
        .alert(
            String(localized: "Proxy Error"),
            isPresented: Binding(
                get: { coordinator.proxyError != nil && !coordinator.isProxyRunning },
                set: {
                    if !$0 {
                        coordinator.proxyError = nil
                    }
                }
            )
        ) {
            Button(String(localized: "OK")) {
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
                Button(String(localized: "Accept and Add iOS Workspace")) {
                    nearbyTransferReceiver.approve(invitation)
                }
                Button(String(localized: "Decline"), role: .cancel) {
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
        .sheet(isPresented: $coordinator.showExportScope) {
            if let context = coordinator.exportScopeContext {
                ExportScopeSheet(
                    context: context,
                    onExport: { scope in coordinator.executeExport(format: context.format, scope: scope) },
                    onCancel: { coordinator.showExportScope = false }
                )
            }
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
        .overlay(alignment: .bottom) {
            if let toast = coordinator.activeToast {
                ToastView(message: toast) {
                    coordinator.activeToast = nil
                }
            }
        }
        .appUIDisplayMetrics(displayMetrics)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Bindable private var coordinator: MainContentCoordinator
    @State private var nearbyTransferReceiver = RockxyNearbyTransferReceiver.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private let settingsManager = AppSettingsManager.shared
    private let managesLifecycle: Bool
    private let representedWorkspaceID: UUID?

    private static let minimumContextDockWidth: CGFloat = 300
    private static let idealContextDockWidth: CGFloat = 380
    private static let maximumContextDockWidth: CGFloat = 520

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
            return String(localized: "Receive Rockxy iOS Session")
        }
        return String(localized: "Receive from \(invitation.deviceName)?")
    }

    private func handleSystemProxyWarningAction(_ action: SystemProxyWarning.Action?) {
        switch action {
        case .retry:
            coordinator.retrySystemProxy()
        case .openGeneralSettings:
            openSettings()
        case .openAdvancedProxySettings:
            openWindow(id: "advancedProxySettings")
        case .reinstallAndTrust:
            Task { @MainActor in
                do {
                    try await CertificateManager.shared.installAndTrust()
                } catch {
                    coordinator.activeToast = ToastMessage(
                        style: .error,
                        text: String(localized: "Failed to install certificate — \(error.localizedDescription)")
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
    }
}

// MARK: - ProcessInfo + Test Host Detection

extension ProcessInfo {
    /// Returns `true` when the process is running as a test host (XCTest bundle loaded).
    var isTestHost: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
