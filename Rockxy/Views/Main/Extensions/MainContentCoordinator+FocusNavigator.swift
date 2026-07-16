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
            name: focusSet.name + " " + String(localized: "Copy"),
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
        FocusSet(
            name: String(localized: "New Focus Set"),
            appName: filterCriteria.sidebarApp ?? "",
            domain: filterCriteria.sidebarDomain ?? "",
            pathPrefix: filterCriteria.sidebarPathPrefix ?? ""
        )
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

    private func persistFocusSetsAcrossWorkspaces(_ focusSets: [FocusSet]) {
        FocusSetPersistence.save(focusSets)
        for workspace in workspaceStore.workspaces where workspace.id != activeWorkspace.id {
            workspace.focusSets = focusSets
            if let activeID = workspace.activeFocusSetID,
               !focusSets.contains(where: { $0.id == activeID })
            {
                workspace.activeFocusSetID = nil
                recomputeFilteredTransactions(for: workspace)
            }
        }
    }
}
