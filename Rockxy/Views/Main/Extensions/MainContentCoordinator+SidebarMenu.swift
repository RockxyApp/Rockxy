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
        let normalizedDomain = normalizedSSLHost(domain)
        guard !normalizedDomain.isEmpty,
              !BypassProxyManager.shared.isHostBypassed(normalizedDomain) else
        {
            return false
        }
        return SSLProxyingManager.shared.isDecryptionConfigured(host: normalizedDomain)
    }

    /// Returns a user-facing reason when a one-host Decrypt shortcut cannot safely override the
    /// current policy. Exact host Tunnel rules are intentionally omitted: selecting Decrypt for
    /// that same host replaces the exact opposite behavior. Broader Tunnel and bypass rules must
    /// be reviewed explicitly because removing them would affect other traffic.
    func sslProxyingHostDecryptBlockedReason(
        for domain: String,
        application: ClientApplicationIdentity? = nil,
        allowReplacingExactTunnel: Bool = true
    ) -> String? {
        let normalizedDomain = normalizedSSLHost(domain)
        guard !normalizedDomain.isEmpty else {
            return String(localized: "The host is unavailable.", bundle: RockxyLocalization.bundle)
        }

        if let application,
           SSLProxyingManager.shared.applicationExcludeRules.contains(where: {
               $0.isEnabled && $0.applicationIdentifier == application.identifier
           })
        {
            return String(
                localized: "The application Tunnel rule takes priority. Change the application behavior first.",
                bundle: RockxyLocalization.bundle
            )
        }

        if BypassProxyManager.shared.isHostBypassed(normalizedDomain) {
            return String(
                localized: "This host is in Full Proxy Bypass. Remove that bypass entry before decrypting it.",
                bundle: RockxyLocalization.bundle
            )
        }

        if SSLProxyingManager.shared.isHostInTLSBypassList(normalizedDomain) {
            return String(
                localized: "This host is in the HTTPS TLS Bypass list. Remove that bypass pattern before decrypting it.",
                bundle: RockxyLocalization.bundle
            )
        }

        if let rule = SSLProxyingManager.shared.excludeRules.first(where: {
            guard $0.isEnabled, $0.matches(normalizedDomain) else {
                return false
            }
            return !allowReplacingExactTunnel || !sslHostPatternsAreEqual($0.domain, normalizedDomain)
        }) {
            if sslHostPatternsAreEqual(rule.domain, normalizedDomain) {
                return String(
                    localized: "Tunnel rule \(rule.domain) takes priority. Change that host behavior before decrypting it.",
                    bundle: RockxyLocalization.bundle
                )
            }
            return String(
                localized: "Tunnel rule \(rule.domain) takes priority. Review that broader rule before decrypting this host.",
                bundle: RockxyLocalization.bundle
            )
        }

        return nil
    }

    func isSSLProxyingEnabled(for application: ClientApplicationIdentity) -> Bool {
        guard SSLProxyingManager.shared.isEnabled else {
            return false
        }
        let hasTunnel = SSLProxyingManager.shared.applicationExcludeRules.contains {
            $0.isEnabled && $0.applicationIdentifier == application.identifier
        }
        guard !hasTunnel else {
            return false
        }
        return SSLProxyingManager.shared.applicationIncludeRules.contains {
            $0.isEnabled && $0.applicationIdentifier == application.identifier
        }
    }

    @discardableResult
    func enableSSLProxyingForDomain(_ domain: String, refreshPresentation: Bool = true) -> Bool {
        let normalizedDomain = normalizedSSLHost(domain)
        guard !normalizedDomain.isEmpty,
              sslProxyingHostDecryptBlockedReason(for: normalizedDomain) == nil else
        {
            return false
        }

        var didChange = false

        if !SSLProxyingManager.shared.isEnabled {
            SSLProxyingManager.shared.setEnabled(true)
            didChange = true
        }

        // An already-effective wildcard Decrypt rule needs no exact duplicate.
        if isSSLProxyingEnabled(for: normalizedDomain) {
            if didChange, refreshPresentation {
                refreshSSLProxyingPresentation()
            }
            return didChange
        }

        let exactTunnelIDs = Set(SSLProxyingManager.shared.excludeRules.filter {
            sslHostPatternsAreEqual($0.domain, normalizedDomain)
        }.map(\.id))
        if !exactTunnelIDs.isEmpty {
            SSLProxyingManager.shared.removeRules(ids: exactTunnelIDs)
            didChange = true
        }

        let exactDecryptRules = SSLProxyingManager.shared.includeRules.filter {
            sslHostPatternsAreEqual($0.domain, normalizedDomain)
        }
        if exactDecryptRules.isEmpty {
            let rule = SSLProxyingRule(domain: normalizedDomain, listType: .include)
            SSLProxyingManager.shared.addRule(rule)
            didChange = true
        } else {
            for existing in exactDecryptRules where !existing.isEnabled {
                SSLProxyingManager.shared.setRuleEnabled(id: existing.id, enabled: true)
                didChange = true
            }
        }

        if didChange, refreshPresentation {
            refreshSSLProxyingPresentation()
        }
        Self.logger.info("Enabled SSL proxying for exact host: \(normalizedDomain)")
        return didChange
    }

    @discardableResult
    func disableSSLProxyingForDomain(_ domain: String, refreshPresentation: Bool = true) -> Bool {
        let normalizedDomain = normalizedSSLHost(domain)
        guard !normalizedDomain.isEmpty else {
            return false
        }

        var didChange = false
        // Only replace the exact host behavior. Removing a matching wildcard Decrypt rule would
        // unexpectedly disable decryption for sibling hosts; an exact Tunnel exception safely
        // overrides it instead.
        let exactDecryptIDs = Set(SSLProxyingManager.shared.includeRules.filter {
            sslHostPatternsAreEqual($0.domain, normalizedDomain)
        }.map(\.id))
        if !exactDecryptIDs.isEmpty {
            SSLProxyingManager.shared.removeRules(ids: exactDecryptIDs)
            didChange = true
        }

        let exactTunnelRules = SSLProxyingManager.shared.excludeRules.filter {
            sslHostPatternsAreEqual($0.domain, normalizedDomain)
        }
        if exactTunnelRules.isEmpty {
            SSLProxyingManager.shared.addRule(
                SSLProxyingRule(domain: normalizedDomain, listType: .exclude)
            )
            didChange = true
        } else {
            for existing in exactTunnelRules where !existing.isEnabled {
                SSLProxyingManager.shared.setRuleEnabled(id: existing.id, enabled: true)
                didChange = true
            }
        }

        if didChange, refreshPresentation {
            refreshSSLProxyingPresentation()
        }
        Self.logger.info("Set exact host to tunnel without decryption: \(normalizedDomain)")
        return didChange
    }

    @discardableResult
    func enableSSLProxyingForApp(_ app: AppInfo, refreshPresentation: Bool = true) -> Bool {
        if let identity = app.identity {
            return setSSLProxyingBehaviorForApplication(
                identity,
                listType: .include,
                refreshPresentation: refreshPresentation
            )
        }
        return enableSSLProxyingForObservedHosts(app, refreshPresentation: refreshPresentation)
    }

    @discardableResult
    func enableSSLProxyingForObservedHosts(_ app: AppInfo, refreshPresentation: Bool = true) -> Bool {
        var didChange = false
        if !SSLProxyingManager.shared.isEnabled {
            SSLProxyingManager.shared.setEnabled(true)
            didChange = true
        }
        for domain in app.domains where !isSSLProxyingEnabled(for: domain) {
            didChange = enableSSLProxyingForDomain(domain, refreshPresentation: false) || didChange
        }
        if didChange, refreshPresentation {
            refreshSSLProxyingPresentation()
        }
        return didChange
    }

    @discardableResult
    func disableSSLProxyingForApp(_ app: AppInfo, refreshPresentation: Bool = true) -> Bool {
        if let identity = app.identity {
            let matchingIDs = Set(
                SSLProxyingManager.shared.applicationRules
                    .filter { $0.applicationIdentifier == identity.identifier }
                    .map(\.id)
            )
            guard !matchingIDs.isEmpty else {
                return false
            }
            SSLProxyingManager.shared.removeApplicationRules(ids: matchingIDs)
            if refreshPresentation {
                refreshSSLProxyingPresentation()
            }
            return true
        }
        return disableSSLProxyingForObservedHosts(app, refreshPresentation: refreshPresentation)
    }

    @discardableResult
    func disableSSLProxyingForObservedHosts(_ app: AppInfo, refreshPresentation: Bool = true) -> Bool {
        var didChange = false
        for domain in app.domains where isSSLProxyingEnabled(for: domain) {
            didChange = disableSSLProxyingForDomain(domain, refreshPresentation: false) || didChange
        }
        if didChange, refreshPresentation {
            refreshSSLProxyingPresentation()
        }
        return didChange
    }

    @discardableResult
    func setSSLProxyingBehaviorForApplication(
        _ identity: ClientApplicationIdentity,
        listType: SSLProxyingListType,
        fallbackDomain: String? = nil,
        refreshPresentation: Bool = true
    ) -> Bool {
        var didChange = false
        if listType == .include, !SSLProxyingManager.shared.isEnabled {
            SSLProxyingManager.shared.setEnabled(true)
            didChange = true
        }

        let oppositeIDs = Set(
            SSLProxyingManager.shared.applicationRules
                .filter {
                    $0.applicationIdentifier == identity.identifier && $0.listType != listType
                }
                .map(\.id)
        )
        if !oppositeIDs.isEmpty {
            SSLProxyingManager.shared.removeApplicationRules(ids: oppositeIDs)
            didChange = true
        }

        if let existing = SSLProxyingManager.shared.applicationRules.first(where: {
            $0.applicationIdentifier == identity.identifier && $0.listType == listType
        }) {
            if !existing.isEnabled {
                SSLProxyingManager.shared.setApplicationRuleEnabled(id: existing.id, enabled: true)
                didChange = true
            }
        } else {
            SSLProxyingManager.shared.addApplicationRule(
                ApplicationSSLProxyingRule(identity: identity, listType: listType)
            )
            didChange = true
        }

        if listType == .include {
            var hosts = Set(observedDomainsForApp(named: identity.displayName, fallbackDomain: fallbackDomain))
            for app in appNodes where app.identity?.identifier == identity.identifier {
                hosts.formUnion(app.domains)
            }
            for app in TrafficDomainSnapshot.shared.appEntries
                where app.identity?.identifier == identity.identifier
            {
                hosts.formUnion(app.domains)
            }
            for host in hosts {
                SSLProxyingManager.shared.retryInterception(for: host)
            }
        }

        if didChange, refreshPresentation {
            refreshSSLProxyingPresentation()
        }
        return didChange
    }

    func refreshSSLProxyingPresentation() {
        sslProxyingRefreshToken += 1
        for workspace in workspaceStore.allWorkspaces {
            workspace.lastDeriveWasAppendOnly = false
            deriveFilteredRows(for: workspace)
        }
    }

    func observedDomainsForApp(named appName: String, fallbackDomain: String? = nil) -> [String] {
        var orderedDomains: [String] = []
        var seen = Set<String>()

        func appendDomains(_ candidates: [String]) {
            for candidate in candidates {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                    continue
                }
                orderedDomains.append(trimmed)
            }
        }

        if let liveDomains = appNodes.first(where: { $0.name == appName })?.domains {
            appendDomains(liveDomains)
        }

        appendDomains(TrafficDomainSnapshot.shared.domains(forApp: appName))

        appendDomains(Array(observedDomainsByApp[appName] ?? []))

        if let fallbackDomain {
            appendDomains([fallbackDomain])
        }

        return orderedDomains.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Returns a stable identity only when every observed identity with this display name agrees.
    /// Name-only transactions can then inherit a previously observed Chrome/Safari identity for
    /// the inspector action, while same-name applications remain ambiguous and fail closed.
    func observedApplicationIdentity(named appName: String) -> ClientApplicationIdentity? {
        let normalizedName = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty else {
            return nil
        }

        let candidates = (appNodes + TrafficDomainSnapshot.shared.appEntries).compactMap { app -> ClientApplicationIdentity? in
            guard app.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName else {
                return nil
            }
            return app.identity
        }
        let identitiesByIdentifier = Dictionary(candidates.map { ($0.identifier, $0) }) { first, _ in first }
        guard identitiesByIdentifier.count == 1 else {
            return nil
        }
        return identitiesByIdentifier.values.first
    }

    func isSSLProxyingFullyEnabled(forAppNamed appName: String, fallbackDomain: String? = nil) -> Bool {
        if let identity = observedApplicationIdentity(named: appName) {
            return isSSLProxyingEnabled(for: identity)
        }
        let domains = observedDomainsForApp(named: appName, fallbackDomain: fallbackDomain)
        guard !domains.isEmpty else {
            return false
        }
        return domains.allSatisfy { isSSLProxyingEnabled(for: $0) }
    }

    func enableSSLProxyingFromInspector(for domain: String) {
        guard !domain.isEmpty else {
            return
        }

        if let blockedReason = sslProxyingHostDecryptBlockedReason(for: domain) {
            activeToast = ToastMessage(style: .warning, text: blockedReason)
            return
        }

        let alreadyEnabled = isSSLProxyingEnabled(for: domain)
        enableSSLProxyingForDomain(domain)

        activeToast = ToastMessage(
            style: .success,
            text: alreadyEnabled ?
                String(
                    localized: "HTTPS Decryption is already enabled for \(domain). Make the request again to inspect it.",
                    bundle: RockxyLocalization.bundle
                ) :
                String(
                    localized: "Enabled HTTPS Decryption for \(domain). Make the request again to inspect it.",
                    bundle: RockxyLocalization.bundle
                )
        )
    }

    func retrySSLProxyingFromInspector(for domain: String) {
        guard !domain.isEmpty else {
            return
        }

        if let blockedReason = sslProxyingHostDecryptBlockedReason(for: domain) {
            activeToast = ToastMessage(style: .warning, text: blockedReason)
            return
        }

        enableSSLProxyingForDomain(domain, refreshPresentation: false)
        SSLProxyingManager.shared.retryInterception(for: domain)
        refreshSSLProxyingPresentation()

        activeToast = ToastMessage(
            style: .success,
            text: String(
                localized: "Decryption retry is ready for \(domain). Repeat the request or reconnect the app.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    func disableSSLProxyingFromInspector(for domain: String) {
        guard !domain.isEmpty else {
            return
        }

        disableSSLProxyingForDomain(domain)

        activeToast = ToastMessage(
            style: .success,
            text: String(
                localized: "Disabled HTTPS Decryption for \(domain). Requests to it will stay tunneled.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    func enableSSLProxyingFromInspector(forAppNamed appName: String, fallbackDomain: String? = nil) {
        guard !appName.isEmpty else {
            return
        }

        let domains = observedDomainsForApp(named: appName, fallbackDomain: fallbackDomain)
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

        let enabledCount = domains.count(where: isSSLProxyingEnabled(for:))
        if enabledCount == domains.count {
            activeToast = ToastMessage(
                style: .success,
                text: String(
                    localized: "Added host Decrypt rules for domains observed from \(appName). These rules apply to every application.",
                    bundle: RockxyLocalization.bundle
                )
            )
        } else {
            activeToast = ToastMessage(
                style: .warning,
                text: String(
                    localized: "Configured \(enabledCount) of \(domains.count) observed hosts. Review Tunnel or bypass rules for the remaining hosts.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    func setSSLProxyingFromInspector(
        for application: ClientApplicationIdentity,
        listType: SSLProxyingListType,
        fallbackDomain: String? = nil
    ) {
        // Configure the application-wide rule first. It applies to every host the application
        // uses regardless of whether the currently inspected host can decrypt, so feedback is
        // derived only after the rule is installed.
        setSSLProxyingBehaviorForApplication(
            application,
            listType: listType,
            fallbackDomain: fallbackDomain
        )

        switch listType {
        case .include:
            // App Decrypt is application-wide, but the supplied current host can still be pinned
            // to Tunnel by a broader host Tunnel rule, Full Proxy Bypass, or the HTTPS TLS Bypass
            // list. Warn truthfully in that case instead of claiming the current host will decrypt.
            if let fallbackDomain,
               !fallbackDomain.isEmpty,
               let blockedReason = sslProxyingHostDecryptBlockedReason(
                   for: fallbackDomain,
                   allowReplacingExactTunnel: false
               )
            {
                activeToast = ToastMessage(
                    style: .warning,
                    text: String(
                        localized: "Set \(application.displayName) to decrypt HTTPS. \(fallbackDomain) stays tunneled: \(blockedReason)",
                        bundle: RockxyLocalization.bundle
                    )
                )
            } else {
                activeToast = ToastMessage(
                    style: .success,
                    text: String(
                        localized: "Set \(application.displayName) to decrypt HTTPS. Matching tunneled connections reset automatically — if one stays tunneled, reconnect the app.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
        case .exclude:
            // Tunnel keeps new-connection semantics: already intercepted connections are not
            // tracked as live raw tunnels, so they are not reset.
            activeToast = ToastMessage(
                style: .success,
                text: String(
                    localized: "Set \(application.displayName) to tunnel HTTPS on new connections. Reconnect the app.",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    func disableSSLProxyingFromInspector(forAppNamed appName: String, fallbackDomain: String? = nil) {
        guard !appName.isEmpty else {
            return
        }

        let domains = observedDomainsForApp(named: appName, fallbackDomain: fallbackDomain)
        guard !domains.isEmpty else {
            return
        }

        disableSSLProxyingForApp(
            AppInfo(
                name: appName,
                domains: domains,
                requestCount: domains.count
            )
        )

        activeToast = ToastMessage(
            style: .success,
            text: String(
                localized: "Set domains observed from \(appName) to Tunnel. These host rules apply to every application.",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    func setupSSLProxyingObserver() {
        guard sslProxyingObserver == nil else {
            return
        }
        sslProxyingObserver = NotificationCenter.default.addObserver(
            forName: .sslProxyingStateDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSSLProxyingPresentation()
            }
        }
    }

    func rebuildObservedDomainsByApp() {
        var countsByApp: [String: [String: Int]] = [:]

        for transaction in transactions {
            let appName = normalizedObservedAppName(transaction.clientApp)
            let host = normalizedObservedHost(transaction.request.host)
            guard !appName.isEmpty, !host.isEmpty else {
                continue
            }
            countsByApp[appName, default: [:]][host, default: 0] += 1
        }

        observedDomainCountsByApp = countsByApp
        observedDomainsByApp = countsByApp.mapValues { Set($0.keys) }
    }

    func appendObservedDomainsByApp(from batch: [HTTPTransaction]) {
        guard !batch.isEmpty else {
            return
        }
        var changedApps: Set<String> = []
        for transaction in batch {
            let appName = normalizedObservedAppName(transaction.clientApp)
            let host = normalizedObservedHost(transaction.request.host)
            guard !host.isEmpty else {
                continue
            }
            observedDomainCountsByApp[appName, default: [:]][host, default: 0] += 1
            changedApps.insert(appName)
        }
        publishObservedDomains(for: changedApps)
    }

    func moveObservedDomainsFromUnknown(for transactions: [HTTPTransaction]) {
        let unknown = normalizedObservedAppName(nil)
        var changedApps: Set<String> = []
        for transaction in transactions {
            let destination = normalizedObservedAppName(transaction.clientApp)
            let host = normalizedObservedHost(transaction.request.host)
            guard destination != unknown, !host.isEmpty else {
                continue
            }

            if let count = observedDomainCountsByApp[unknown]?[host] {
                if count <= 1 {
                    observedDomainCountsByApp[unknown]?.removeValue(forKey: host)
                } else {
                    observedDomainCountsByApp[unknown]?[host] = count - 1
                }
                if observedDomainCountsByApp[unknown]?.isEmpty == true {
                    observedDomainCountsByApp.removeValue(forKey: unknown)
                }
            }
            observedDomainCountsByApp[destination, default: [:]][host, default: 0] += 1
            changedApps.insert(destination)
        }
        if !changedApps.isEmpty {
            changedApps.insert(unknown)
            publishObservedDomains(for: changedApps)
        }
    }

    func installAndTrustCertificateFromInspector() {
        Task { @MainActor in
            do {
                try await certificateManager.installAndTrust()
                await readiness.deepRefresh()
                activeToast = ToastMessage(
                    style: .success,
                    text: String(
                        localized: "Certificate installed and trusted. Make the request again to inspect HTTPS content.",
                        bundle: RockxyLocalization.bundle
                    )
                )
            } catch {
                activeToast = ToastMessage(
                    style: .error,
                    text: String(
                        localized: "Failed to install certificate — \(error.localizedDescription)",
                        bundle: RockxyLocalization.bundle
                    )
                )
            }
        }
    }

    private func publishObservedDomains(for appNames: Set<String>) {
        var snapshot = observedDomainsByApp
        for appName in appNames {
            if let counts = observedDomainCountsByApp[appName], !counts.isEmpty {
                snapshot[appName] = Set(counts.keys)
            } else {
                snapshot.removeValue(forKey: appName)
            }
        }
        observedDomainsByApp = snapshot
    }

    private func normalizedObservedAppName(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? String(localized: "Unknown", bundle: RockxyLocalization.bundle) : normalized
    }

    private func normalizedObservedHost(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedSSLHost(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sslHostPatternsAreEqual(_ lhs: String, _ rhs: String) -> Bool {
        normalizedSSLHost(lhs) == normalizedSSLHost(rhs)
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
        refreshDomainTree(for: activeWorkspace, alphabetical: true)
        // Rebuild index map after sort
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
        exportTransactionsForDomain(domain, pathPrefix: nil)
    }

    func exportTransactionsForDomain(
        _ domain: String,
        pathPrefix: String?,
        format: TrafficExportFormat = .har
    ) {
        let domainTransactions = sidebarDomainExportTransactions(domain, pathPrefix: pathPrefix)
        guard !domainTransactions.isEmpty else {
            return
        }
        let suffix = pathPrefix?
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        exportTransactions(
            domainTransactions,
            format: format,
            defaultStem: suffix.map { "\(domain)-\($0)" } ?? domain
        )
    }

    func exportTransactionsForApp(_ appName: String, format: TrafficExportFormat = .har) {
        let appTransactions = sidebarAppExportTransactions(appName)
        guard !appTransactions.isEmpty else {
            return
        }
        exportTransactions(appTransactions, format: format, defaultStem: "\(appName)-traffic")
    }

    func sidebarDomainExportTransactions(_ domain: String, pathPrefix: String?) -> [HTTPTransaction] {
        transactions.filter {
            DomainGrouping.host($0.request.host, matchesDomain: domain)
                && DomainGrouping.path($0.request.path, matchesPrefix: pathPrefix)
        }
    }

    func sidebarAppExportTransactions(_ appName: String) -> [HTTPTransaction] {
        transactions.filter { $0.clientApp == appName }
    }

    // MARK: - Delete / Remove

    func removeDomainFromSidebar(_ domain: String) {
        removeDomainFromSidebar(domain, pathPrefix: nil)
    }

    func removeDomainFromSidebar(_ domain: String, pathPrefix: String?) {
        transactions.removeAll {
            DomainGrouping.host($0.request.host, matchesDomain: domain)
                && DomainGrouping.path($0.request.path, matchesPrefix: pathPrefix)
        }
        rebuildObservedDomainsByApp()

        // Clear selection if it was removed by this action.
        switch sidebarSelection {
        case let .domainNode(selectedDomain) where selectedDomain == domain && pathPrefix == nil:
            sidebarSelection = nil
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarScope = .allTraffic
        case let .domainPath(selectedDomain, selectedPath)
            where selectedDomain == domain && selectedPath == pathPrefix:
            sidebarSelection = nil
            filterCriteria.sidebarDomain = nil
            filterCriteria.sidebarPathPrefix = nil
            filterCriteria.sidebarScope = .allTraffic
        default:
            break
        }

        rebuildSidebarIndexes()
        recomputeFilteredTransactions()
        Self.logger.info("Removed domain from sidebar: \(domain)")
    }

    func removeAppFromSidebar(_ appName: String) {
        transactions.removeAll { $0.clientApp == appName }
        rebuildObservedDomainsByApp()

        // Clear selection if it was this app
        if case .app(appName, _) = sidebarSelection {
            sidebarSelection = nil
            filterCriteria.sidebarApp = nil
            filterCriteria.sidebarScope = .allTraffic
        }

        rebuildSidebarIndexes()
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
        Self.logger.info("Created Network Conditions draft for domain: \(domain, privacy: .private)")
    }
}
