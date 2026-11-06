import SwiftUI

// MARK: - FocusSidebarList

/// Focus mode's navigator list: the workspace's Focus Sets, and the Noise Control sources that
/// are currently hiding captured rows.
///
/// Split out of `SidebarView` so each navigator mode owns its own file.
struct FocusSidebarList: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let filterText: String

    @Binding var editingFocusSet: FocusSet?
    @Binding var isMutedSourcesPresented: Bool
    @Binding var expandedFocusSetIDs: Set<UUID>

    var body: some View {
        focusList
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    /// One identified row per state — see the comment on the Focus Sets section.
    private enum FocusSetRow: Identifiable {
        case empty
        case focusSet(FocusSet)

        var id: String {
            switch self {
            case .empty: "focus-sets-empty"
            case let .focusSet(focusSet): focusSet.id.uuidString
            }
        }
    }

    /// One identified row per state, so the section never switches between a bare view and a
    /// `ForEach` (see the comment on the Noise Control section).
    private enum NoiseControlRow: Identifiable {
        case empty
        case source(MutedTrafficSource)

        var id: String {
            switch self {
            case .empty: "noise-control-empty"
            case let .source(source): source.id
            }
        }
    }

    private var focusSets: [FocusSet] {
        SidebarSearchFilter.focusSets(coordinator.activeWorkspace.focusSets, query: filterText)
    }

    private var visibleMutedSources: [MutedTrafficSource] {
        let sorted = coordinator.activeWorkspace.mutedTrafficSources.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return SidebarSearchFilter.mutedSources(sorted, query: filterText)
    }

    private var focusSetRows: [FocusSetRow] {
        let sets = focusSets
        return sets.isEmpty ? [.empty] : sets.map(FocusSetRow.focusSet)
    }

    private var emptyFocusSetRow: some View {
        Label(
            SidebarSearchFilter.hasQuery(filterText)
                ? String(localized: "No Matching Focus Sets", bundle: RockxyLocalization.bundle)
                : String(localized: "No Focus Sets", bundle: RockxyLocalization.bundle),
            systemImage: "scope"
        )
        .font(.system(size: metrics.sidebarNavigationFontSize, weight: .medium))
        .help(String(localized: "Create a reusable app, domain, or path scope.", bundle: RockxyLocalization.bundle))
        .padding(.vertical, 4)
    }

    private func focusSetRow(_ focusSet: FocusSet) -> some View {
        FocusSetSidebarRow(
            focusSet: focusSet,
            isActive: coordinator.activeWorkspace.activeFocusSetID == focusSet.id,
            isExpanded: focusSetExpansionBinding(for: focusSet.id),
            onApply: { applyFocusSetFromSidebar(focusSet) }
        )
        .listRowBackground(
            coordinator.activeWorkspace.activeFocusSetID == focusSet.id
                ? Color.accentColor.opacity(0.09)
                : Color.clear
        )
        .contextMenu {
            Button(String(localized: "Apply", bundle: RockxyLocalization.bundle)) {
                applyFocusSetFromSidebar(focusSet)
            }
            Button(expandedFocusSetIDs.contains(focusSet.id)
                ? String(localized: "Collapse Rules", bundle: RockxyLocalization.bundle)
                : String(localized: "Expand Rules", bundle: RockxyLocalization.bundle))
            {
                toggleFocusSetExpansion(focusSet.id)
            }
            Divider()
            Button(String(localized: "Edit…", bundle: RockxyLocalization.bundle)) {
                editingFocusSet = focusSet
            }
            Button(String(localized: "Duplicate", bundle: RockxyLocalization.bundle)) {
                coordinator.duplicateFocusSet(focusSet)
            }
            Divider()
            Button(String(localized: "Delete", bundle: RockxyLocalization.bundle), role: .destructive) {
                coordinator.deleteFocusSet(focusSet)
            }
        }
    }

    private var noiseControlRows: [NoiseControlRow] {
        let sources = visibleMutedSources
        return sources.isEmpty ? [.empty] : sources.map(NoiseControlRow.source)
    }

    private var emptyNoiseControlRow: some View {
        Label(
            SidebarSearchFilter.hasQuery(filterText)
                ? String(localized: "No Matching Muted Sources", bundle: RockxyLocalization.bundle)
                : String(localized: "No Muted Sources", bundle: RockxyLocalization.bundle),
            systemImage: "speaker.wave.2"
        )
        .font(.system(size: metrics.sidebarNavigationFontSize, weight: .medium))
        .help(String(
            localized: "Hide a recurring host or path from this Traffic Tab without stopping capture.",
            bundle: RockxyLocalization.bundle
        ))
        .padding(.vertical, 4)
    }

    private var focusList: some View {
        List {
            Section {
                // One `ForEach` over identified rows in both states, for the same reason the
                // Noise Control section below does it: a section that switches its children
                // between a bare view and a `ForEach` stays blank until the list is rebuilt.
                ForEach(focusSetRows) { row in
                    switch row {
                    case .empty:
                        emptyFocusSetRow
                    case let .focusSet(focusSet):
                        focusSetRow(focusSet)
                    }
                }
            } header: {
                sidebarSectionHeader(
                    title: String(localized: "Focus Sets", bundle: RockxyLocalization.bundle),
                    actionTitle: nil,
                    actionSystemImage: "plus",
                    actionLabel: String(localized: "Create Focus Set", bundle: RockxyLocalization.bundle),
                    action: { editingFocusSet = coordinator.makeFocusSetFromCurrentScope() }
                )
                .padding(.top, 4)
            }

            Section {
                // A muted source hides rows that were captured, so leaving this section empty
                // meant the only trace of a mute lived inside its own sheet: a request that
                // never appeared looked like a request that was never made.
                //
                // Both states come from one `ForEach` over identified rows on purpose. Switching
                // a section's children between a bare view and a `ForEach` changes their
                // structural identity, and `List` then keeps the section blank until the whole
                // list is rebuilt — muting a host left the section showing nothing at all until
                // the navigator mode was switched away and back.
                ForEach(noiseControlRows) { row in
                    switch row {
                    case .empty:
                        emptyNoiseControlRow
                    case let .source(source):
                        mutedSourceRow(source)
                    }
                }
            } header: {
                sidebarSectionHeader(
                    title: String(localized: "Noise Control", bundle: RockxyLocalization.bundle),
                    actionTitle: nil,
                    actionSystemImage: "slider.horizontal.3",
                    actionLabel: String(localized: "Configure Noise Control", bundle: RockxyLocalization.bundle),
                    action: { isMutedSourcesPresented = true }
                )
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Measured on the built app: this `List` renders both sections correctly on first paint,
        // but muting or unmuting a source while Focus mode is on screen left the Noise Control
        // section blank until the navigator mode was switched away and back — macOS's `List` does
        // not reload a section whose rows changed identity under a custom `header:`. Keying the
        // list on its own row identities rebuilds it instead of diffing it. Focus mode holds a
        // handful of rows and no scroll position worth preserving, so the rebuild is free.
        .id(rowIdentityToken)
    }

    /// Changes exactly when a row appears, disappears, or swaps identity.
    private var rowIdentityToken: String {
        (focusSetRows.map(\.id) + noiseControlRows.map(\.id)).joined(separator: "|")
    }

    /// Mirrors `FocusSetSidebarRow`: the muted source, how many captured requests it is
    /// currently hiding, and a context menu that can undo the mute without opening the sheet.
    private func mutedSourceRow(_ source: MutedTrafficSource) -> some View {
        // Counted once. Both the badge and the accessibility value need it, and each
        // call scans the whole retained capture.
        let hidden = coordinator.mutedTransactionCount(for: source)
        return HStack(spacing: 7) {
            Image(systemName: source.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            Text(source.title)
                .font(.system(size: metrics.sidebarNavigationFontSize))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if hidden > 0 {
                Text(CountFormatter.format(hidden))
                    .font(.system(size: metrics.sidebarSecondaryFontSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .help(String(
            localized: "Muted. Requests matching this source stay captured but are hidden from the list.",
            bundle: RockxyLocalization.bundle
        ))
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            String(AttributedString(
                localized: "^[\(hidden) hidden request](inflect: true)",
                bundle: RockxyLocalization.bundle,
                locale: RockxyLocalization.locale
            ).characters)
        )
        .contextMenu {
            Button(String(localized: "Unmute", bundle: RockxyLocalization.bundle)) {
                coordinator.unmuteTrafficSource(source)
            }
            Divider()
            Button(String(localized: "Configure Noise Control…", bundle: RockxyLocalization.bundle)) {
                isMutedSourcesPresented = true
            }
        }
    }

    private func sidebarSectionHeader(
        title: String,
        actionTitle: String?,
        actionSystemImage: String?,
        actionLabel: String,
        action: @escaping () -> Void
    )
        -> some View
    {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            Button(action: action) {
                if let actionSystemImage {
                    Image(systemName: actionSystemImage)
                        .frame(width: 18, height: 18)
                } else if let actionTitle {
                    Text(actionTitle)
                        .font(.caption.weight(.medium))
                }
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .help(actionLabel)
            .accessibilityLabel(actionLabel)
        }
        .frame(maxWidth: .infinity)
    }

    private func focusSetExpansionBinding(for id: UUID) -> Binding<Bool> {
        Binding {
            SidebarSearchFilter.hasQuery(filterText) || expandedFocusSetIDs.contains(id)
        } set: { isExpanded in
            if isExpanded {
                expandedFocusSetIDs.insert(id)
            } else {
                expandedFocusSetIDs.remove(id)
            }
        }
    }

    private func toggleFocusSetExpansion(_ id: UUID) {
        if expandedFocusSetIDs.contains(id) {
            expandedFocusSetIDs.remove(id)
        } else {
            expandedFocusSetIDs.insert(id)
        }
    }

    private func applyFocusSetFromSidebar(_ focusSet: FocusSet) {
        expandedFocusSetIDs.insert(focusSet.id)
        coordinator.applyFocusSet(focusSet)
    }
}
