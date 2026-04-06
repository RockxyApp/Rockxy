import Combine
import SwiftUI

/// Root view of the main window. Sets up a two-column `NavigationSplitView` with
/// `SidebarView` on the left and `CenterContentView` as the detail area.
/// Owns the `MainContentCoordinator` that drives all data flow to child views.
struct ContentView: View {
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
        .onReceive(NotificationCenter.default.publisher(for: .breakpointRuleCreated)) { _ in
            openWindow(id: "breakpoints")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDiffWindow)) { _ in
            openWindow(id: "diff")
        }
        .onAppear {
            coordinator.loadPersistedFavorites()
        }
        .task {
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
        .onReceive(NotificationCenter.default.publisher(for: .openMapLocalWindow)) { _ in
            openWindow(id: "mapLocal")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMapRemoteWindow)) { _ in
            openWindow(id: "mapRemote")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNetworkConditionsWindow)) { _ in
            openWindow(id: "networkConditions")
        }
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
    @State private var coordinator = MainContentCoordinator()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private func handleSystemProxyWarningAction(_ action: SystemProxyWarning.Action?) {
        switch action {
        case .retry:
            coordinator.retrySystemProxy()
        case .openGeneralSettings:
            openSettings()
        case .openAdvancedProxySettings:
            openWindow(id: "advancedProxySettings")
        case nil:
            break
        }
    }
}
