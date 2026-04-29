import AppKit
import Combine
import SwiftUI

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
                    CenterContentView(coordinator: coordinator)
                        .navigationTitle("")
                }
            }
        }
        .background {
            WorkspaceWindowAccessor(
                coordinator: coordinator,
                representedWorkspaceID: representedWorkspaceID
            )
            .frame(width: 0, height: 0)
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
                    onExport: { scope in coordinator.executeHARExport(scope: scope) },
                    onCancel: { coordinator.showExportScope = false }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = coordinator.activeToast {
                ToastView(message: toast) {
                    coordinator.activeToast = nil
                }
            }
        }
        .overlay(alignment: .top) {
            if isRenamingWorkspace {
                WorkspaceTitleEditor(
                    title: $workspaceRenameDraft,
                    onCommit: commitWorkspaceRename,
                    onCancel: cancelWorkspaceRename
                )
                .padding(.top, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .renameWorkspaceTabRequested)) { notification in
            guard let workspaceID = notification.userInfo?["workspaceID"] as? UUID,
                  workspaceID == contentWorkspaceID else {
                return
            }
            beginWorkspaceRename(workspaceID: workspaceID)
        }
        .animation(.snappy(duration: 0.16), value: isRenamingWorkspace)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Bindable private var coordinator: MainContentCoordinator
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isRenamingWorkspace = false
    @State private var renamingWorkspaceID: UUID?
    @State private var workspaceRenameDraft = ""
    private let managesLifecycle: Bool
    private let representedWorkspaceID: UUID?

    private var contentWorkspaceID: UUID {
        representedWorkspaceID
            ?? coordinator.workspaceStore.workspaces.first(where: { !$0.isClosable })?.id
            ?? coordinator.workspaceStore.activeWorkspaceID
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

    private func beginWorkspaceRename(workspaceID: UUID) {
        guard let workspace = coordinator.workspaceStore.workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }
        renamingWorkspaceID = workspaceID
        workspaceRenameDraft = workspace.title
        isRenamingWorkspace = true
    }

    private func commitWorkspaceRename() {
        guard let renamingWorkspaceID else {
            cancelWorkspaceRename()
            return
        }
        let trimmed = workspaceRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelWorkspaceRename()
            return
        }
        coordinator.workspaceStore.renameWorkspace(id: renamingWorkspaceID, to: trimmed)
        RockxyWorkspaceWindowManager.shared.updateWindowTitles(coordinator: coordinator)
        cancelWorkspaceRename()
    }

    private func cancelWorkspaceRename() {
        isRenamingWorkspace = false
        renamingWorkspaceID = nil
        workspaceRenameDraft = ""
    }
}

// MARK: - Workspace Title Editor

private struct WorkspaceTitleEditor: View {
    @Binding var title: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        TextField(String(localized: "Tab Name"), text: $title)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 280)
            .focused($isFocused)
            .onSubmit(onCommit)
            .onExitCommand(perform: onCancel)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            .onAppear {
                isFocused = true
            }
    }

    @FocusState private var isFocused: Bool
}

// MARK: - Workspace Window Accessor

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
              let coordinator else {
            return
        }
        RockxyWorkspaceWindowManager.shared.registerPrimaryWindow(window, coordinator: coordinator)
    }
}

// MARK: - Conditional Lifecycle Modifiers

private struct ConditionalContentWindowNotificationHandlers: ViewModifier {
    let isEnabled: Bool
    let coordinator: MainContentCoordinator
    let openWindow: OpenWindowAction

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(ContentWindowNotificationHandlers(coordinator: coordinator, openWindow: openWindow))
        } else {
            content
        }
    }
}

private struct ConditionalScriptingWindowOpeners: ViewModifier {
    let isEnabled: Bool
    let openWindow: OpenWindowAction

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(ScriptingWindowOpeners(openWindow: openWindow))
        } else {
            content
        }
    }
}

// MARK: - Content Window Notification Handlers

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
