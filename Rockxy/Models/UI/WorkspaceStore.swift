import Foundation
import os

// Persists and coordinates workspace tabs and the active workspace selection.

@MainActor @Observable
final class WorkspaceStore {
    // MARK: Lifecycle

    init(
        maxWorkspaces: Int = 8,
        layoutPreferences: WorkspaceLayoutPreferences = WorkspaceLayoutPreferences()
    ) {
        self.maxWorkspaces = Self.clampCreationCapacity(maxWorkspaces)
        self.layoutPreferences = layoutPreferences
        let defaultWorkspace = Self.makeWorkspace(
            title: ProjectStructuralLimits.defaultTabTitle,
            isClosable: false,
            filter: .empty,
            layoutPreferences: layoutPreferences
        )
        self.workspaces = [defaultWorkspace]
        self.activeWorkspaceID = defaultWorkspace.id
    }

    // MARK: Internal

    /// Effective tab *creation* capacity. Gates new/duplicated tabs only; it never
    /// truncates hydrated tabs, which are retained up to the structural upper bound.
    /// Refreshable at runtime via ``refreshCapacity(maxWorkspaces:)``.
    private(set) var maxWorkspaces: Int

    /// The traffic tabs, in tab-strip order. Split-view companion panes are not tabs and
    /// live in ``splitCompanions`` instead.
    var workspaces: [WorkspaceState]
    /// The selected tab. When that tab's companion pane has focus, ``activeWorkspace`` is the
    /// companion rather than the tab itself.
    var activeWorkspaceID: UUID

    /// Second traffic pane shown beside a tab in split view, keyed by the owning tab's id.
    /// A companion reads the same capture with its own filters and selection, never appears
    /// in the tab strip, and is not saved with the Project.
    private(set) var splitCompanions: [UUID: WorkspaceState] = [:]

    /// Tabs whose companion pane currently has focus.
    private(set) var focusedCompanionTabIDs: Set<UUID> = []

    /// The selected tab, ignoring which of its panes has focus.
    var activeTab: WorkspaceState {
        workspaces.first { $0.id == activeWorkspaceID } ?? workspaces[0]
    }

    /// The pane that commands, filters, and the inspector act on: the selected tab, or its
    /// companion pane when that pane has focus.
    var activeWorkspace: WorkspaceState {
        let tab = activeTab
        if focusedCompanionTabIDs.contains(tab.id), let companion = splitCompanions[tab.id] {
            return companion
        }
        return tab
    }

    /// Every tab and companion pane. Capture updates, eviction, and resets fan out over this
    /// so a companion pane stays live even while it is not focused.
    var allWorkspaces: [WorkspaceState] {
        workspaces + workspaces.compactMap { splitCompanions[$0.id] }
    }

    func workspace(id: UUID) -> WorkspaceState? {
        allWorkspaces.first { $0.id == id }
    }

    func splitCompanion(for tabID: UUID) -> WorkspaceState? {
        splitCompanions[tabID]
    }

    /// The tab that owns a companion pane, or `nil` when `workspaceID` is not a companion.
    func ownerTabID(ofCompanion workspaceID: UUID) -> UUID? {
        splitCompanions.first { $0.value.id == workspaceID }?.key
    }

    /// Opens (or reuses) the companion pane for `tabID` and focuses it. A non-empty `filter`
    /// replaces the companion's filter so a sidebar source can open directly in the pane.
    @discardableResult
    func openSplit(for tabID: UUID, filter: FilterCriteria = .empty) -> WorkspaceState? {
        guard let tab = workspaces.first(where: { $0.id == tabID }) else {
            return nil
        }
        let companion: WorkspaceState
        if let existing = splitCompanions[tabID] {
            companion = existing
            if !filter.isEmpty {
                companion.filterCriteria = filter
            }
        } else {
            companion = WorkspaceState(
                title: tab.title,
                isClosable: true,
                initialFilter: filter,
                inspectorLayout: .bottom,
                isContextDockVisible: false,
                allowsAutomaticInspectorReveal: true
            )
            companion.activeSortDescriptors = tab.activeSortDescriptors
            splitCompanions[tabID] = companion
        }
        if !filter.isEmpty {
            // The sidebar row that produced this filter is not the pane's own selection.
            companion.sidebarSelection = nil
        }
        activeWorkspaceID = tabID
        focusedCompanionTabIDs.insert(tabID)
        return companion
    }

    /// Closes the companion pane of `tabID`; the tab's own pane takes focus again.
    func closeSplit(for tabID: UUID) {
        splitCompanions[tabID] = nil
        focusedCompanionTabIDs.remove(tabID)
    }

    /// Gives focus to a pane: a tab id selects that tab's own pane, a companion id selects its
    /// owning tab with the companion focused. Unknown ids are ignored.
    func focusPane(_ workspaceID: UUID) {
        if workspaces.contains(where: { $0.id == workspaceID }) {
            activeWorkspaceID = workspaceID
            focusedCompanionTabIDs.remove(workspaceID)
        } else if let ownerID = ownerTabID(ofCompanion: workspaceID) {
            activeWorkspaceID = ownerID
            focusedCompanionTabIDs.insert(ownerID)
        }
    }

    var activeWorkspaceIndex: Int {
        workspaces.firstIndex { $0.id == activeWorkspaceID } ?? 0
    }

    var canCreateWorkspace: Bool {
        workspaces.count < maxWorkspaces
    }

    /// Re-sets the effective tab *creation* capacity at runtime. Existing tabs are
    /// never closed or truncated by a lower limit; only future create/duplicate
    /// actions observe the new bound. Clamped into the structural tab range so a
    /// bad or expanded policy can never authorize creating more live tabs than the
    /// structural upper bound (which snapshot persistence would later truncate).
    func refreshCapacity(maxWorkspaces newValue: Int) {
        maxWorkspaces = Self.clampCreationCapacity(newValue)
    }

    @discardableResult
    func createWorkspace(
        title: String = String(localized: "New Tab", bundle: RockxyLocalization.bundle),
        filter: FilterCriteria = .empty
    )
        -> WorkspaceState
    {
        guard canCreateWorkspace else {
            Self.logger.warning("Maximum workspace count (\(self.maxWorkspaces)) reached")
            return activeWorkspace
        }
        guard let normalizedTitle = try? ProjectNormalization.normalizedDisplayName(title) else {
            Self.logger.warning("Refused to create a workspace with an invalid title")
            return activeWorkspace
        }
        let workspace = Self.makeWorkspace(
            title: normalizedTitle,
            isClosable: true,
            filter: filter,
            layoutPreferences: layoutPreferences
        )
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        Self.logger.info("Created workspace: \(normalizedTitle)")
        return workspace
    }

    func closeWorkspace(id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.isClosable else
        {
            return
        }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            return
        }

        let wasActive = id == activeWorkspaceID
        workspaces.remove(at: index)
        closeSplit(for: id)

        if wasActive {
            let newIndex = min(index, workspaces.count - 1)
            activeWorkspaceID = workspaces[newIndex].id
        }
        Self.logger.info("Closed workspace: \(workspace.title)")
    }

    func selectWorkspace(id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else {
            return
        }
        activeWorkspaceID = id
    }

    func selectWorkspace(at index: Int) {
        guard index >= 0, index < workspaces.count else {
            return
        }
        activeWorkspaceID = workspaces[index].id
    }

    func selectPreviousWorkspace() {
        let currentIndex = activeWorkspaceIndex
        let newIndex = currentIndex > 0 ? currentIndex - 1 : workspaces.count - 1
        activeWorkspaceID = workspaces[newIndex].id
    }

    func selectNextWorkspace() {
        let currentIndex = activeWorkspaceIndex
        let newIndex = currentIndex < workspaces.count - 1 ? currentIndex + 1 : 0
        activeWorkspaceID = workspaces[newIndex].id
    }

    func moveWorkspace(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < workspaces.count,
              destinationIndex >= 0, destinationIndex < workspaces.count,
              sourceIndex != destinationIndex else
        {
            return
        }
        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: destinationIndex)
    }

    func reorderWorkspaces(toWorkspaceIDs orderedIDs: [UUID]) {
        guard !orderedIDs.isEmpty else {
            return
        }

        var remaining = workspaces
        var reordered: [WorkspaceState] = []
        reordered.reserveCapacity(workspaces.count)

        for id in orderedIDs {
            guard let index = remaining.firstIndex(where: { $0.id == id }) else {
                continue
            }
            reordered.append(remaining.remove(at: index))
        }

        reordered.append(contentsOf: remaining)
        guard reordered.count == workspaces.count else {
            return
        }
        workspaces = reordered
    }

    func duplicateWorkspace(id: UUID) -> WorkspaceState? {
        guard let source = workspaces.first(where: { $0.id == id }),
              canCreateWorkspace else
        {
            return nil
        }
        let suffix = " " + String(localized: "Copy", bundle: RockxyLocalization.bundle)
        let maximumBaseCount = max(
            1,
            ProjectStructuralLimits.nameGraphemeRange.upperBound - suffix.count
        )
        let candidateTitle = source.title.boundedToGraphemes(maximumBaseCount) + suffix
        guard let normalizedTitle = try? ProjectNormalization.normalizedDisplayName(candidateTitle) else {
            Self.logger.warning("Refused to duplicate a workspace with an invalid title")
            return nil
        }
        let duplicate = WorkspaceState(
            title: normalizedTitle,
            isClosable: true,
            initialFilter: source.filterCriteria
        )
        duplicate.activeMainTab = source.activeMainTab
        duplicate.sidebarSelection = source.sidebarSelection
        duplicate.inspectorLayout = source.inspectorLayout
        duplicate.isContextDockVisible = source.isContextDockVisible
        duplicate.contextDockTab = source.contextDockTab
        duplicate.allowsAutomaticInspectorReveal = source.allowsAutomaticInspectorReveal
        duplicate.focusNavigatorMode = source.focusNavigatorMode
        duplicate.activeTrafficSignal = source.activeTrafficSignal
        duplicate.focusSets = source.focusSets
        duplicate.activeFocusSetID = source.activeFocusSetID
        duplicate.mutedTrafficSources = source.mutedTrafficSources
        duplicate.filterRules = source.filterRules
        duplicate.isFilterBarVisible = source.isFilterBarVisible

        if let sourceIndex = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces.insert(duplicate, at: sourceIndex + 1)
        } else {
            workspaces.append(duplicate)
        }
        activeWorkspaceID = duplicate.id
        return duplicate
    }

    func closeOtherWorkspaces(except id: UUID) {
        workspaces.removeAll { $0.id != id && $0.isClosable }
        let remaining = Set(workspaces.map(\.id))
        for tabID in splitCompanions.keys where !remaining.contains(tabID) {
            closeSplit(for: tabID)
        }
        if !workspaces.contains(where: { $0.id == activeWorkspaceID }) {
            activeWorkspaceID = workspaces[0].id
        }
    }

    func renameWorkspace(id: UUID, to newTitle: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              let normalizedTitle = try? ProjectNormalization.normalizedDisplayName(newTitle) else
        {
            Self.logger.warning("Refused to rename a workspace with an invalid title")
            return
        }
        workspace.title = normalizedTitle
    }

    // MARK: Project snapshot seams

    /// Captures the durable, bounded configuration of the current traffic tabs.
    /// Live transactions, rows, selections, sort descriptors, sidebar indexes,
    /// logs, and assistant state are intentionally excluded.
    func captureTabSnapshots() -> [ProjectTabSnapshot] {
        workspaces.map { ProjectTabSnapshot(capturing: $0) }
    }

    /// Replaces all traffic tabs with hydrated snapshots for a Project switch.
    /// Always restores at least one non-closable default tab and a valid active
    /// ID, even if given an empty or malformed set. Hydration retains up to the
    /// structural tab upper bound — not the lower creation limit — so a Project
    /// carrying more tabs than the current creation capacity is restored intact.
    func applyTabSnapshots(_ snapshots: [ProjectTabSnapshot], activeTabID: UUID) {
        var hydrated = snapshots.map { $0.hydrateWorkspaceState() }

        if hydrated.isEmpty {
            hydrated = [Self.makeWorkspace(
                title: ProjectStructuralLimits.defaultTabTitle,
                isClosable: false,
                filter: .empty,
                layoutPreferences: layoutPreferences
            )]
        } else if !hydrated.contains(where: { !$0.isClosable }) {
            hydrated.insert(
                Self.makeWorkspace(
                    title: ProjectStructuralLimits.defaultTabTitle,
                    isClosable: false,
                    filter: .empty,
                    layoutPreferences: layoutPreferences
                ),
                at: 0
            )
        }

        let retentionCap = ProjectStructuralLimits.tabCountRange.upperBound
        if hydrated.count > retentionCap {
            // Bound only by the structural upper limit: keep the non-closable
            // default and the earliest tabs. The creation limit never truncates
            // retained tabs here.
            let defaultIndex = hydrated.firstIndex { !$0.isClosable } ?? 0
            let keeper = hydrated.remove(at: defaultIndex)
            hydrated = [keeper] + hydrated.prefix(retentionCap - 1)
        }

        workspaces = hydrated
        splitCompanions.removeAll()
        focusedCompanionTabIDs.removeAll()
        activeWorkspaceID = hydrated.contains { $0.id == activeTabID }
            ? activeTabID
            : hydrated[0].id
    }

    func rememberBottomInspectorVisibility(_ isVisible: Bool) {
        layoutPreferences.rememberBottomInspectorVisibility(isVisible)
    }

    func rememberContextDockVisibility(_ isVisible: Bool) {
        layoutPreferences.rememberContextDockVisibility(isVisible)
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "WorkspaceStore")

    private let layoutPreferences: WorkspaceLayoutPreferences

    /// Clamps a requested tab creation capacity into the structural tab range
    /// (`ProjectStructuralLimits.tabCountRange`). Both the lower and upper bound are
    /// enforced: at least one tab is always creatable, and never more than the
    /// structural upper bound that durable snapshots retain.
    private static func clampCreationCapacity(_ value: Int) -> Int {
        let range = ProjectStructuralLimits.tabCountRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func makeWorkspace(
        title: String,
        isClosable: Bool,
        filter: FilterCriteria,
        layoutPreferences: WorkspaceLayoutPreferences
    )
        -> WorkspaceState
    {
        let preferredBottomVisibility = layoutPreferences.preferredBottomInspectorVisibility
        return WorkspaceState(
            title: title,
            isClosable: isClosable,
            initialFilter: filter,
            inspectorLayout: preferredBottomVisibility == true ? .bottom : .hidden,
            isContextDockVisible: layoutPreferences.preferredContextDockVisibility,
            allowsAutomaticInspectorReveal: preferredBottomVisibility == nil
        )
    }
}
