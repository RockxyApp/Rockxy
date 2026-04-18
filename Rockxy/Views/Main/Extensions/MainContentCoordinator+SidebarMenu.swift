import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// Extends `MainContentCoordinator` with sidebar menu behavior for the main workspace.

// MARK: - MainContentCoordinator + SidebarMenu

/// Coordinator extension for sidebar right-click context menu actions.
/// Provides SSL proxying toggle, favorites management, sorting, and export
/// actions for domain and app rows in the sidebar source list.
extension MainContentCoordinator {
    // MARK: - SSL Proxying

    func isSSLProxyingEnabled(for domain: String) -> Bool {
        SSLProxyingManager.shared.includeRules.contains { $0.isEnabled && $0.matches(domain) }
    }

    func enableSSLProxyingForDomain(_ domain: String) {
        guard !domain.isEmpty else {
            return
        }
        let rule = SSLProxyingRule(domain: domain, listType: .include)
        SSLProxyingManager.shared.addRule(rule)
        Self.logger.info("Enabled SSL proxying for domain: \(domain)")
    }

    func disableSSLProxyingForDomain(_ domain: String) {
        guard !domain.isEmpty else {
            return
        }
        let matchingIncludeIDs = SSLProxyingManager.shared.includeRules
            .filter { $0.matches(domain) }
            .map(\.id)
        let idSet = Set(matchingIncludeIDs)
        if !idSet.isEmpty {
            SSLProxyingManager.shared.removeRules(ids: idSet)
            Self.logger.info("Disabled SSL proxying for domain: \(domain)")
        }
    }

    func enableSSLProxyingForApp(_ app: AppInfo) {
        for domain in app.domains where !isSSLProxyingEnabled(for: domain) {
            enableSSLProxyingForDomain(domain)
        }
    }

    func observedDomainsForApp(named appName: String) -> [String] {
        if let liveDomains = appNodes.first(where: { $0.name == appName })?.domains,
           !liveDomains.isEmpty
        {
            return liveDomains
        }
        return TrafficDomainSnapshot.shared.domains(forApp: appName)
    }

    func enableSSLProxyingFromInspector(for domain: String) {
        guard !domain.isEmpty else {
            return
        }

        if !SSLProxyingManager.shared.isEnabled {
            SSLProxyingManager.shared.setEnabled(true)
        }

        let alreadyEnabled = isSSLProxyingEnabled(for: domain)
        if !alreadyEnabled {
            enableSSLProxyingForDomain(domain)
        }

        activeToast = ToastMessage(
            style: .success,
            text: alreadyEnabled ?
                String(
                    localized: "SSL Proxying is already enabled for \(domain). Make the request again to inspect it."
                ) :
                String(localized: "Enabled SSL Proxying for \(domain). Make the request again to inspect it.")
        )
    }

    func enableSSLProxyingFromInspector(forAppNamed appName: String) {
        guard !appName.isEmpty else {
            return
        }

        let domains = observedDomainsForApp(named: appName)
        guard !domains.isEmpty else {
            return
        }

        if !SSLProxyingManager.shared.isEnabled {
            SSLProxyingManager.shared.setEnabled(true)
        }

        enableSSLProxyingForApp(
            AppInfo(
                name: appName,
                domains: domains,
                requestCount: domains.count
            )
        )

        activeToast = ToastMessage(
            style: .success,
            text: String(
                localized: "Enabled SSL Proxying for domains from \(appName). Make the request again to inspect them."
            )
        )
    }

    func installAndTrustCertificateFromInspector() {
        Task { @MainActor in
            do {
                try await certificateManager.installAndTrust()
                await readiness.deepRefresh()
                activeToast = ToastMessage(
                    style: .success,
                    text: String(
                        localized: "Certificate installed and trusted. Make the request again to inspect HTTPS content."
                    )
                )
            } catch {
                activeToast = ToastMessage(
                    style: .error,
                    text: String(localized: "Failed to install certificate — \(error.localizedDescription)")
                )
            }
        }
    }

    // MARK: - Bypass Proxy List

    func isInBypassList(_ domain: String) -> Bool {
        BypassProxyManager.shared.isHostBypassed(domain)
    }

    func addToBypassList(_ domain: String) {
        BypassProxyManager.shared.addDomain(domain)
        Self.logger.info("Added domain to bypass list: \(domain)")
    }

    func removeFromBypassList(_ domain: String) {
        let matchingIDs = BypassProxyManager.shared.domains
            .filter { $0.matches(domain) }
            .map(\.id)
        let idSet = Set(matchingIDs)
        if !idSet.isEmpty {
            BypassProxyManager.shared.removeDomains(ids: idSet)
            Self.logger.info("Removed domain from bypass list: \(domain)")
        }
    }

    // MARK: - Favorites Toggle

    func toggleSidebarFavorite(_ item: SidebarItem) {
        if favorites.contains(item) {
            removeFavorite(item)
        } else {
            addFavorite(item)
        }
    }

    func isFavorite(_ item: SidebarItem) -> Bool {
        favorites.contains(item)
    }

    // MARK: - Sorting

    func sortDomainTreeAlphabetically() {
        domainTree.sort { $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending }
        // Rebuild index map after sort
        domainIndexMap.removeAll()
        for (index, node) in domainTree.enumerated() {
            domainIndexMap[node.domain] = index
        }
        Self.logger.info("Sorted domain tree alphabetically")
    }

    func sortAppNodesAlphabetically() {
        appNodes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // Rebuild index map after sort
        appNodeIndexMap.removeAll()
        for (index, node) in appNodes.enumerated() {
            appNodeIndexMap[node.name] = index
        }
        Self.logger.info("Sorted app nodes alphabetically")
    }

    // MARK: - Copy & Export

    func copyDomainToClipboard(_ domain: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(domain, forType: .string)
    }

    func exportTransactionsForDomain(_ domain: String) {
        let domainTransactions = transactions.filter { $0.request.host == domain }
        guard !domainTransactions.isEmpty else {
            return
        }

        let exporter = HARExporter()
        let data: Data
        do {
            data = try exporter.export(transactions: domainTransactions)
        } catch {
            Self.logger.error("Failed to serialize HAR for domain \(domain): \(error.localizedDescription)")
            showSidebarExportError(error)
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(domain).har"
        panel.allowedContentTypes = [.har]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url)
            Self.logger.info("Exported \(domainTransactions.count) transactions for \(domain)")
        } catch {
            Self.logger.error("Failed to export transactions: \(error.localizedDescription)")
            showSidebarExportError(error)
        }
    }

    func exportTransactionsForApp(_ appName: String) {
        let appTransactions = transactions.filter { $0.clientApp == appName }
        guard !appTransactions.isEmpty else {
            return
        }

        let exporter = HARExporter()
        let data: Data
        do {
            data = try exporter.export(transactions: appTransactions)
        } catch {
            Self.logger.error("Failed to serialize HAR for app \(appName): \(error.localizedDescription)")
            showSidebarExportError(error)
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(appName)-traffic.har"
        panel.allowedContentTypes = [.har]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url)
            Self.logger.info("Exported \(appTransactions.count) transactions for app \(appName)")
        } catch {
            Self.logger.error("Failed to export transactions: \(error.localizedDescription)")
            showSidebarExportError(error)
        }
    }

    private func showSidebarExportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Export Failed")
        alert.informativeText = String(localized: "Could not export HAR file.\n\n\(error.localizedDescription)")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    // MARK: - Delete / Remove

    func removeDomainFromSidebar(_ domain: String) {
        transactions.removeAll { $0.request.host == domain }

        if let index = domainIndexMap[domain] {
            domainTree.remove(at: index)
            domainIndexMap.removeValue(forKey: domain)
            // Rebuild index map
            domainIndexMap.removeAll()
            for (i, node) in domainTree.enumerated() {
                domainIndexMap[node.domain] = i
            }
        }

        // Remove from app nodes' domain lists
        for i in appNodes.indices {
            appNodes[i].domains.removeAll { $0 == domain }
        }

        // Clear selection if it was this domain
        if case .domainNode(domain) = sidebarSelection {
            sidebarSelection = nil
        }

        recomputeFilteredTransactions()
        Self.logger.info("Removed domain from sidebar: \(domain)")
    }

    func removeAppFromSidebar(_ appName: String) {
        transactions.removeAll { $0.clientApp == appName }

        if let index = appNodeIndexMap[appName] {
            appNodes.remove(at: index)
            appNodeIndexMap.removeValue(forKey: appName)
            // Rebuild index map
            appNodeIndexMap.removeAll()
            for (i, node) in appNodes.enumerated() {
                appNodeIndexMap[node.name] = i
            }
        }

        // Clear selection if it was this app
        if case .app(appName, _) = sidebarSelection {
            sidebarSelection = nil
        }

        recomputeFilteredTransactions()
        Self.logger.info("Removed app from sidebar: \(appName)")
    }

    // MARK: - Tools (Rule Creation from Domain)

    func createBlockRuleForDomain(_ domain: String) {
        let context = BlockRuleEditorContextBuilder.fromDomain(domain)
        BlockRuleEditorContextStore.shared.setPending(context)
        NotificationCenter.default.post(name: .openBlockListWindow, object: nil)
        Self.logger.info("Created Block rule context for domain: \(domain)")
    }

    func createAllowListRuleForDomain(_ domain: String) {
        let context = AllowListEditorContextBuilder.fromDomain(domain)
        AllowListEditorContextStore.shared.setPending(context)
        NotificationCenter.default.post(name: .openAllowListWindow, object: nil)
        Self.logger.info("Created Allow List rule context for domain: \(domain)")
    }

    func createMapLocalRuleForDomain(_ domain: String) {
        let draft = MapLocalDraftBuilder.fromDomain(domain)
        MapLocalDraftStore.shared.setPending(draft)
        NotificationCenter.default.post(name: .openMapLocalWindow, object: nil)
        Self.logger.info("Created Map Local draft for domain: \(domain)")
    }

    func createMapRemoteRuleForDomain(_ domain: String) {
        let draft = MapRemoteDraftBuilder.fromDomain(domain)
        MapRemoteDraftStore.shared.setPending(draft)
        NotificationCenter.default.post(name: .openMapRemoteWindow, object: nil)
        Self.logger.info("Created Map Remote draft for domain: \(domain)")
    }

    func createBreakpointRuleForDomain(_ domain: String) {
        let context = BreakpointEditorContextBuilder.fromDomain(domain)
        BreakpointEditorContextStore.shared.setPending(context)
        NotificationCenter.default.post(name: .openBreakpointRulesWindow, object: nil)
    }

    func createNetworkConditionsRuleForDomain(_ domain: String) {
        let draft = NetworkConditionsDraftBuilder.fromDomain(domain)
        NetworkConditionsDraftStore.shared.setPending(draft)
        NotificationCenter.default.post(name: .openNetworkConditionsWindow, object: nil)
        Self.logger.info("Created Network Conditions draft for domain: \(domain)")
    }
}
