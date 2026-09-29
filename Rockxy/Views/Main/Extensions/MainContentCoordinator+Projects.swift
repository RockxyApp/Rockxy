import Foundation
import Observation

// MARK: - ProjectObservationTarget

private final class ProjectObservationTarget: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: Internal

    weak var coordinator: MainContentCoordinator?
}

// Extends `MainContentCoordinator` with non-visual Project orchestration: startup
// hydration, Project lifecycle (switch/create/delete/rename/reorder), and
// Observation-driven debounced autosave of durable traffic-tab configuration.
//
// This layer owns only orchestration. It never presents UI. Durable Project
// persistence contains only `ProjectTabSnapshot` view intent, while runtime capture
// histories and logs are isolated in bounded in-memory Project buckets. User
// messaging and sheets are owned by the app layer.

// MARK: - MainContentCoordinator + Projects

extension MainContentCoordinator {
    // MARK: - Startup Hydration

    /// Loads the persisted catalog exactly once, coalescing concurrent callers. On a
    /// ready load it applies the active Project's tabs and capture history to the
    /// workspace store and arms debounced autosave. On a failed load it retains
    /// the current safe workspaces, performs no writes, and leaves the store's
    /// failure observable (`projectStore.loadState` / `loadFailureMessage`).
    func hydrateProjectsOnLaunch() async {
        if let existing = projectHydrationTask {
            await existing.value
            return
        }
        guard !hasHydratedProjects else {
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.performProjectHydration()
        }
        projectHydrationTask = task
        await task.value
        // Clear only after a failed attempt so an explicit retry can re-run; a
        // successful hydration is guarded by `hasHydratedProjects`.
        if !hasHydratedProjects {
            projectHydrationTask = nil
        }
    }

    /// Ensures app-lifecycle data producers never bind traffic or workspaces to
    /// the provisional default Project that exists before catalog hydration.
    /// External intake fails closed when the persisted catalog cannot be loaded.
    func ensureProjectCatalogReadyForDataIntake() async -> Bool {
        // A receiver may deliver many frames while recovery UI is open. Do not
        // turn each frame into another disk retry after a known load failure;
        // only the explicit Retry action should leave this state.
        if case .failed = projectStore.loadState {
            return false
        }
        await hydrateProjectsOnLaunch()
        return hasHydratedProjects && projectStore.loadState == .ready
    }

    // MARK: - Project Switching

    /// Persists the outgoing Project's tabs and runtime capture projection, activates
    /// `id`, then restores that Project's tabs/history without stopping the app-wide
    /// proxy listener. The target is validated before any outgoing
    /// mutation; on failure the current UI/workspaces and active Project stay
    /// coherent. Re-selecting the active Project is a successful no-op.
    @discardableResult
    func switchToProject(id: UUID) -> Bool {
        guard !isClearingSession else {
            lastProjectOperationError = .captureClearInProgress
            return false
        }
        guard projectStore.isMutable else {
            lastProjectOperationError = .storeNotReady
            return false
        }
        guard id != projectStore.activeProjectID else {
            lastProjectOperationError = nil
            return true
        }
        // Validate the target before mutating the outgoing Project.
        guard projectStore.projects.contains(where: { $0.id == id }) else {
            lastProjectOperationError = .projectNotFound
            return false
        }
        cacheActiveProjectCaptureState()
        guard flushProjectTabSnapshot() else {
            return false
        }
        do {
            try projectStore.selectProject(id: id)
        } catch let error as ProjectMutationError {
            lastProjectOperationError = error
            return false
        } catch {
            return false
        }
        activateCurrentProject()
        lastProjectOperationError = nil
        return true
    }

    // MARK: - Reconciliation

    /// Edition-neutral local reconciliation seam. Applies an externally reconciled
    /// set of Project entities while keeping the coordinator's workspace tabs,
    /// capture-routing context, and per-Project runtime buckets coherent.
    ///
    /// `expectedRevision` is the caller's last-observed local catalog revision. The
    /// active Project's live tab configuration is flushed first (so an unsaved edit
    /// is preserved rather than lost), then the store performs an in-process
    /// compare-and-swap against `expectedRevision`. If the flush advanced the
    /// revision the candidate is now stale and is rejected for caller retry — the
    /// flushed edit is never overwritten. Runtime buckets are cleared only for
    /// removed Project IDs. The workspace/capture context is refreshed only when the
    /// active Project identity or its tab configuration actually changed, so an
    /// inactive-only reconciliation leaves the current live workspace untouched.
    /// Runtime capture for a surviving active Project is preserved across a refresh.
    /// Returns whether the catalog changed; failures surface via
    /// `lastProjectOperationError`.
    @discardableResult
    func reconcileProjects(_ projects: [Project], expectedRevision: UInt64) -> Bool {
        guard !isClearingSession else {
            lastProjectOperationError = .captureClearInProgress
            return false
        }
        guard projectStore.isMutable else {
            lastProjectOperationError = .storeNotReady
            return false
        }

        let previousProjectIDs = Set(projectStore.projects.map(\.id))
        cacheActiveProjectCaptureState()
        guard flushProjectTabSnapshot() else {
            return false
        }
        let previousActive = projectStore.activeProject

        let changed: Bool
        do {
            changed = try projectStore.reconcile(projects: projects, expectedRevision: expectedRevision)
        } catch let error as ProjectMutationError {
            lastProjectOperationError = error
            return false
        } catch {
            return false
        }

        let removedProjectIDs = previousProjectIDs.subtracting(projectStore.projects.map(\.id))
        for projectID in removedProjectIDs {
            transactionsByProjectID.removeValue(forKey: projectID)
            logEntriesByProjectID.removeValue(forKey: projectID)
            sessionProvenanceByProjectID.removeValue(forKey: projectID)
            captureGenerationByProjectID.removeValue(forKey: projectID)
            nextSequenceNumberByProjectID.removeValue(forKey: projectID)
        }

        let newActive = projectStore.activeProject
        let activeIdentityChanged = newActive.id != previousActive.id
        let activeTabConfigurationChanged = newActive.activeTabID != previousActive.activeTabID
            || newActive.tabs != previousActive.tabs
        if activeIdentityChanged || activeTabConfigurationChanged {
            activateCurrentProject()
        }

        lastProjectOperationError = nil
        return changed
    }

    // MARK: - Capacity Refresh

    /// Re-clamps the Project and workspace-tab *creation* capacities from a refreshed
    /// policy without deleting or truncating any retained Project or tab. Only future
    /// create/import/duplicate actions observe the new bounds; existing over-limit
    /// state is preserved intact.
    func refreshProjectCreationCapacity(with policy: any AppPolicy) {
        projectStore.refreshCapacity(with: policy)
        workspaceStore.refreshCapacity(maxWorkspaces: policy.maxWorkspaceTabs)
    }

    // MARK: - Project Lifecycle

    /// Persists the outgoing snapshot, creates and activates a new Project, then
    /// applies its default tab set and rebuilds. Returns `nil` (with
    /// `lastProjectOperationError` set) on rejection, leaving current state intact.
    @discardableResult
    func createProject(named name: String) -> Project? {
        guard !isClearingSession else {
            lastProjectOperationError = .captureClearInProgress
            return nil
        }
        guard projectStore.isMutable else {
            lastProjectOperationError = .storeNotReady
            return nil
        }
        cacheActiveProjectCaptureState()
        guard flushProjectTabSnapshot() else {
            return nil
        }
        do {
            let project = try projectStore.createProject(name: name)
            activateCurrentProject()
            lastProjectOperationError = nil
            return project
        } catch let error as ProjectMutationError {
            lastProjectOperationError = error
            return nil
        } catch {
            return nil
        }
    }

    /// Deletes a Project. Deleting the active Project applies and rebuilds the
    /// deterministically selected adjacent Project; deleting an inactive Project
    /// preserves the current tabs (only the active Project's durable edits are first
    /// flushed so they are not lost).
    @discardableResult
    func deleteProject(id: UUID) -> Bool {
        guard !isClearingSession else {
            lastProjectOperationError = .captureClearInProgress
            return false
        }
        guard projectStore.isMutable else {
            lastProjectOperationError = .storeNotReady
            return false
        }
        let deletingActive = id == projectStore.activeProjectID
        let deletedProjectID = id
        if deletingActive {
            cacheActiveProjectCaptureState()
        }
        if !deletingActive {
            // Preserve the current active Project's edits; its tabs are untouched.
            guard flushProjectTabSnapshot() else {
                return false
            }
        }
        do {
            try projectStore.deleteProject(id: id)
        } catch let error as ProjectMutationError {
            lastProjectOperationError = error
            return false
        } catch {
            return false
        }
        if deletingActive {
            activateCurrentProject()
        }
        transactionsByProjectID.removeValue(forKey: deletedProjectID)
        logEntriesByProjectID.removeValue(forKey: deletedProjectID)
        sessionProvenanceByProjectID.removeValue(forKey: deletedProjectID)
        captureGenerationByProjectID.removeValue(forKey: deletedProjectID)
        nextSequenceNumberByProjectID.removeValue(forKey: deletedProjectID)
        lastProjectOperationError = nil
        return true
    }

    /// Renames a Project. Never swaps tabs.
    @discardableResult
    func renameProject(id: UUID, to name: String) -> Bool {
        guard projectStore.isMutable else {
            lastProjectOperationError = .storeNotReady
            return false
        }
        do {
            try projectStore.renameProject(id: id, to: name)
            lastProjectOperationError = nil
            return true
        } catch let error as ProjectMutationError {
            lastProjectOperationError = error
            return false
        } catch {
            return false
        }
    }

    /// Reorders Projects. Never swaps tabs.
    @discardableResult
    func reorderProjects(_ orderedIDs: [UUID]) -> Bool {
        guard projectStore.isMutable else {
            lastProjectOperationError = .storeNotReady
            return false
        }
        do {
            try projectStore.reorderProjects(orderedIDs)
            lastProjectOperationError = nil
            return true
        } catch let error as ProjectMutationError {
            lastProjectOperationError = error
            return false
        } catch {
            return false
        }
    }

    // MARK: - Explicit Flush

    /// Captures the active Project's traffic-tab configuration and persists it
    /// through the store. Intended both for the debounced autosave and as an
    /// explicit pre-transition flush the app can call before a known window change.
    /// A snapshot that reproduces the stored tabs is a no-op (no revision bump).
    /// Returns whether the store accepted the snapshot.
    @discardableResult
    func flushProjectTabSnapshot() -> Bool {
        guard projectStore.isMutable else {
            return false
        }
        let snapshots = workspaceStore.captureTabSnapshots()
        let activeTabID = workspaceStore.activeWorkspaceID
        do {
            try projectStore.updateActiveProjectTabs(snapshots, activeTabID: activeTabID)
            lastProjectOperationError = nil
            return true
        } catch let error as ProjectMutationError {
            lastProjectOperationError = error
            return false
        } catch {
            return false
        }
    }

    func flushProjectStateForTermination() async {
        projectTabAutosaveTask?.cancel()
        projectTabAutosaveTask = nil
        _ = flushProjectTabSnapshot()
        await projectStore.waitForPendingPersistence()
    }

    // MARK: - Autosave (Observation-driven)

    /// Arms Observation-driven autosave once the store is hydrated. Idempotent.
    func beginProjectTabObservation() {
        guard hasHydratedProjects, !isObservingProjectTabs else {
            return
        }
        isObservingProjectTabs = true
        armProjectTabObservation()
    }

    /// Schedules a single debounced autosave, cancelling any in-flight one so rapid
    /// edits coalesce into one write. Never accumulates tasks.
    func scheduleProjectTabAutosave() {
        projectTabAutosaveTask?.cancel()
        projectTabAutosaveTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(for: self.projectTabAutosaveDebounce)
            } catch {
                // Cancelled by a newer change: coalesced into the later save.
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self.flushProjectTabSnapshot()
            self.projectTabAutosaveTask = nil
        }
    }

    // MARK: - Private

    private func performProjectHydration() async {
        await projectStore.loadPersistedCatalog()
        guard projectStore.loadState == .ready else {
            // Failed load: keep current workspaces, write nothing, do not arm autosave.
            return
        }
        seedActiveProjectCaptureStateIfNeeded()
        activateCurrentProject()
        // A saved Insights selection can restore a paused, empty report even while capture
        // is already receiving requests. Begin each traffic session at the source list;
        // the user can open Insights when there is something to investigate.
        if activeMainTab == .traffic || activeMainTab == .insights {
            selectSidebarItem(.allApps)
        }
        hasHydratedProjects = true
        beginProjectTabObservation()
    }

    /// Applies the active Project's tabs and isolated capture history to the
    /// workspace store, then cancels
    /// workspace-scoped assistant work orphaned by the tab replacement. All mutation
    /// runs with autosave suppressed.
    func activateCurrentProject() {
        let project = projectStore.activeProject
        cancelWorkspaceScopedAssistantWork()
        restoreActiveProjectCaptureState()
        refreshCaptureContextSnapshot()
        withProjectSnapshotApplication {
            workspaceStore.applyTabSnapshots(project.tabs, activeTabID: project.activeTabID)
            rebuildAllWorkspacesForCaptureReplacement()
        }
    }

    /// Recomputes each workspace's sidebar indexes and filtered rows from only the
    /// active Project's runtime capture projection.
    func rebuildAllWorkspacesForCaptureReplacement() {
        for workspace in workspaceStore.allWorkspaces {
            rebuildSidebarIndexes(for: workspace)
            recomputeFilteredTransactions(for: workspace)
        }
        TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)
    }

    // MARK: - Capture Routing

    /// Stable session identity for the current single-session Project slice. A
    /// distinct `sessionID` remains in the routing contract so adding archived or
    /// named sessions later does not change proxy ownership semantics.
    var activeCaptureContext: TrafficCaptureContext {
        let projectID = projectStore.activeProjectID
        return TrafficCaptureContext(
            projectID: projectID,
            sessionID: projectID,
            generation: captureGenerationByProjectID[projectID, default: 0]
        )
    }

    func refreshCaptureContextSnapshot() {
        captureContextStore.update(activeCaptureContext)
    }

    func cacheActiveProjectCaptureState() {
        let projectID = projectStore.activeProjectID
        transactionsByProjectID[projectID] = transactions
        nextSequenceNumberByProjectID[projectID] = nextSequenceNumber
        logEntriesByProjectID[projectID] = logEntries
        if let sessionProvenance {
            sessionProvenanceByProjectID[projectID] = sessionProvenance
        } else {
            sessionProvenanceByProjectID.removeValue(forKey: projectID)
        }
    }

    func seedActiveProjectCaptureStateIfNeeded() {
        let projectID = projectStore.activeProjectID
        if transactionsByProjectID[projectID] == nil, !transactions.isEmpty {
            let context = activeCaptureContext
            for transaction in transactions {
                transaction.assignCaptureContextIfMissing(context)
            }
            transactionsByProjectID[projectID] = transactions
            nextSequenceNumberByProjectID[projectID] = nextSequenceNumber
        }
        if logEntriesByProjectID[projectID] == nil, !logEntries.isEmpty {
            logEntriesByProjectID[projectID] = logEntries
        }
        if sessionProvenanceByProjectID[projectID] == nil, let sessionProvenance {
            sessionProvenanceByProjectID[projectID] = sessionProvenance
        }
    }

    private func restoreActiveProjectCaptureState() {
        let projectID = projectStore.activeProjectID
        transactions = transactionsByProjectID[projectID] ?? []
        logEntries = logEntriesByProjectID[projectID] ?? []
        sessionProvenance = sessionProvenanceByProjectID[projectID]
        let maximumLiveSequence = transactions.map(\.sequenceNumber).max() ?? -1
        let maximumFavoriteSequence = persistedFavorites.map(\.sequenceNumber).max() ?? -1
        nextSequenceNumber = max(maximumLiveSequence, maximumFavoriteSequence) + 1
        nextSequenceNumberByProjectID[projectID] = nextSequenceNumber
        recomputeErrorCount()
        resetTrafficMetrics()
        recordTrafficMetrics(for: transactions)
        rebuildObservedDomainsByApp()
        debugAssistantTransactionsByHost.removeAll()
        debugAssistantIndexedTransactionIDs.removeAll()
        debugAssistantIndexedLiveCount = 0
        debugAssistantTrafficIndexGeneration &+= 1
        appendToDebugAssistantTrafficIndex(transactions)
        headerColumnStore.updateDiscoveredHeaders(from: transactions)
    }

    private func cancelWorkspaceScopedAssistantWork() {
        for workspaceID in Array(debugAssistantTasks.keys) {
            cancelDebugAssistantTask(for: workspaceID)
        }
    }

    private func withProjectSnapshotApplication(_ body: () -> Void) {
        let previous = isApplyingProjectSnapshot
        isApplyingProjectSnapshot = true
        defer { isApplyingProjectSnapshot = previous }
        body()
    }

    /// Registers Observation dependencies on the durable tab seams and re-arms after
    /// each change. Autosave scheduling is skipped while a snapshot is being applied;
    /// a stray post-application save is additionally a store no-op because
    /// `updateActiveProjectTabs` rejects an unchanged tab set.
    private func armProjectTabObservation() {
        let target = ProjectObservationTarget(self)
        withObservationTracking {
            trackDurableTabConfiguration()
        } onChange: {
            Task { @MainActor in
                guard let coordinator = target.coordinator,
                      coordinator.isObservingProjectTabs else
                {
                    return
                }
                coordinator.armProjectTabObservation()
                guard !coordinator.isApplyingProjectSnapshot else {
                    return
                }
                coordinator.scheduleProjectTabAutosave()
            }
        }
    }

    /// Touches exactly the durable configuration captured into `ProjectTabSnapshot`
    /// so Observation tracks those properties and nothing more. Building the
    /// snapshots is the single source of truth for which seams are durable.
    private func trackDurableTabConfiguration() {
        _ = workspaceStore.activeWorkspaceID
        for workspace in workspaceStore.workspaces {
            _ = ProjectTabSnapshot(capturing: workspace)
        }
    }
}
