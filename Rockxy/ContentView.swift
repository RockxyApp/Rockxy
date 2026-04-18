import Combine
import SwiftUI

// MARK: - ContentView

/// Root view of the main window. Sets up a two-column `NavigationSplitView` with
/// `SidebarView` on the left and `CenterContentView` as the detail area.
/// Uses the app-owned `MainContentCoordinator` that drives all data flow to child views.
struct ContentView: View {
    // MARK: Lifecycle

    init(coordinator: MainContentCoordinator) {
        _coordinator = Bindable(coordinator)
    }

    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.workspaceStore.workspaces.count > 1 {
                WorkspaceTabStrip(coordinator: coordinator)
            }

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
            .id(coordinator.activeWorkspace.id)
        }
        .focusedSceneValue(\.commandActions, MainContentCommandActions(coordinator: coordinator))
        .toolbar {
            ProxyToolbarContent(coordinator: coordinator)
        }
        .onReceive(NotificationCenter.default.publisher(for: .breakpointHit)) { _ in
            openWindow(id: "breakpoints")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDiffWindow)) { _ in
            openWindow(id: "diff")
        }
        .onAppear {
            guard !ProcessInfo.processInfo.isTestHost else {
                return
            }
            coordinator.configureSharedGates()
            coordinator.loadPersistedFavorites()
            coordinator.attachToMCPServer(MCPServerCoordinator.shared)
        }
        .task {
            // Skip startup tasks when running as a test host to avoid actor
            // contention between the app's loadInitialRules and test suites.
            guard !ProcessInfo.processInfo.isTestHost else {
                return
            }
            coordinator.readiness.startObserving()
            coordinator.setupRulesObserver()
            coordinator.loadInitialRules()
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
        .modifier(ScriptingWindowOpeners(openWindow: openWindow))
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
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Bindable private var coordinator: MainContentCoordinator
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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

// MARK: - ProcessInfo + Test Host Detection

extension ProcessInfo {
    /// Returns `true` when the process is running as a test host (XCTest bundle loaded).
    var isTestHost: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
