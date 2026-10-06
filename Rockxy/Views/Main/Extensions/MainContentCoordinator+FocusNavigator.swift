import Foundation

// MARK: - MainContentCoordinator + FocusNavigator

extension MainContentCoordinator {
    func toggleTrafficSignal(_ signal: TrafficSignal) {
        activeWorkspace.activeTrafficSignal = activeWorkspace.activeTrafficSignal == signal ? nil : signal
        focusNavigatorMode = .browse
        recomputeFilteredTransactions()
    }

    func trafficSignalCount(_ signal: TrafficSignal) -> Int {
        transactions.count { !$0.isTLSFailure && signal.matches($0) }
    }

    func applyFocusSet(_ focusSet: FocusSet?) {
        activeWorkspace.activeFocusSetID = focusSet?.id
        if focusSet != nil {
            focusNavigatorMode = .focus
        }
        recomputeFilteredTransactions()
    }

    func saveFocusSet(_ focusSet: FocusSet) {
        if let index = activeWorkspace.focusSets.firstIndex(where: { $0.id == focusSet.id }) {
            activeWorkspace.focusSets[index] = focusSet
        } else {
            activeWorkspace.focusSets.append(focusSet)
        }
        persistFocusSetsAcrossWorkspaces(activeWorkspace.focusSets)
        applyFocusSet(focusSet)
    }

    func duplicateFocusSet(_ focusSet: FocusSet) {
        var copy = FocusSet(
            name: focusSet.name + " " + String(localized: "Copy", bundle: RockxyLocalization.bundle),
            appName: focusSet.appName,
            domain: focusSet.domain,
            pathPrefix: focusSet.pathPrefix,
            excludedDomain: focusSet.excludedDomain,
            excludedPathPrefix: focusSet.excludedPathPrefix
        )
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        activeWorkspace.focusSets.append(copy)
        persistFocusSetsAcrossWorkspaces(activeWorkspace.focusSets)
    }

    func deleteFocusSet(_ focusSet: FocusSet) {
        activeWorkspace.focusSets.removeAll { $0.id == focusSet.id }
        persistFocusSetsAcrossWorkspaces(activeWorkspace.focusSets)
        if activeWorkspace.activeFocusSetID == focusSet.id {
            applyFocusSet(nil)
        }
    }

    func makeFocusSetFromCurrentScope() -> FocusSet {
        var focusSet = FocusSet(
            name: String(localized: "New Focus Set", bundle: RockxyLocalization.bundle),
            appName: filterCriteria.sidebarApp ?? "",
            domain: filterCriteria.sidebarDomain ?? "",
            pathPrefix: filterCriteria.sidebarPathPrefix ?? ""
        )
        focusSet.name = focusSet.suggestedName
        return focusSet
    }

    func muteTrafficSource(_ source: MutedTrafficSource) {
        activeWorkspace.mutedTrafficSources.insert(source)
        recomputeFilteredTransactions()
    }

    func unmuteTrafficSource(_ source: MutedTrafficSource) {
        activeWorkspace.mutedTrafficSources.remove(source)
        recomputeFilteredTransactions()
    }

    func unmuteAllTrafficSources() {
        activeWorkspace.mutedTrafficSources.removeAll()
        recomputeFilteredTransactions()
    }

    func mutedTransactionCount(for source: MutedTrafficSource) -> Int {
        transactions.count { source.matches($0) }
    }

    /// Single Focus/Noise inclusion predicate shared by request-list workspace visibility and
    /// Assistant related-traffic selection. Traffic Signals are intentionally excluded here so the
    /// request list can layer its own signal lens on top without leaking that filter into the
    /// Assistant's automatically discovered related context.
    func isWithinFocusNoiseScope(_ transaction: HTTPTransaction, workspace: WorkspaceState) -> Bool {
        if workspace.mutedTrafficSources.contains(where: { $0.matches(transaction) }) {
            return false
        }
        return workspace.activeFocusSet?.matches(transaction) ?? true
    }

    private func persistFocusSetsAcrossWorkspaces(_ focusSets: [FocusSet]) {
        FocusSetPersistence.save(focusSets)
        for workspace in workspaceStore.allWorkspaces where workspace.id != activeWorkspace.id {
            workspace.focusSets = focusSets
            let hadActiveFocusSet = workspace.activeFocusSetID != nil
            if let activeID = workspace.activeFocusSetID,
               !focusSets.contains(where: { $0.id == activeID })
            {
                workspace.activeFocusSetID = nil
            }
            if hadActiveFocusSet {
                recomputeFilteredTransactions(for: workspace)
            }
        }
    }
}
