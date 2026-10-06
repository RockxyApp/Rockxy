import SwiftUI

// MARK: - TrafficControlShelf

/// The top-level functional layer for traffic commands and filtering.
///
/// Liquid Glass belongs to this shared navigation/control surface, while the request table below
/// remains an opaque, high-density content layer. Every native and custom glass control lives in
/// one `GlassEffectContainer`, giving nearby elements a shared sampling region instead of painting
/// opaque capsules over the functional layer.
struct TrafficControlShelf: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator
    let advancedRuleCount: Int
    let onOpenToolWindow: (String) -> Void

    var body: some View {
        RockxyGlassEffectGroup(spacing: Theme.Glass.shelfSectionSpacing) {
            VStack(spacing: Theme.Glass.shelfSectionSpacing) {
                shelfSurface {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Layout.controlSpacing) {
                            trafficCommandBar

                            Divider()
                                .frame(height: 22)

                            searchFilterBar
                                .layoutPriority(1)
                        }

                        VStack(spacing: 0) {
                            trafficCommandBar
                            Divider()
                                .opacity(Theme.Glass.separatorOpacity)
                            searchFilterBar
                        }
                    }
                }

                shelfSurface {
                    ProtocolFilterBar(
                        activeFilters: Binding(
                            get: { coordinator.filterCriteria.activeProtocolFilters },
                            set: {
                                coordinator.filterCriteria.activeProtocolFilters = $0
                                coordinator.recomputeFilteredTransactions()
                            }
                        ),
                        isEmbeddedInControlShelf: true
                    )
                }

                if coordinator.isFilterBarVisible {
                    shelfSurface {
                        AdvancedFilterBar(
                            rules: Binding(
                                get: { coordinator.filterRules },
                                set: {
                                    coordinator.filterRules = $0
                                    coordinator.recomputeFilteredTransactions()
                                }
                            ),
                            presetStore: coordinator.filterPresetStore,
                            onHide: {
                                coordinator.isFilterBarVisible = false
                                coordinator.recomputeFilteredTransactions()
                            },
                            isEmbeddedInControlShelf: true
                        )
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if hasActiveFilterSummary {
                    shelfSurface {
                        ActiveFilterSummaryBar(
                            coordinator: coordinator,
                            isEmbeddedInControlShelf: true
                        )
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, Theme.Glass.shelfOuterPadding)
        .padding(.top, Theme.Glass.shelfOuterPadding)
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.18), value: coordinator.isFilterBarVisible)
        .animation(.easeInOut(duration: 0.18), value: hasActiveFilterSummary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    private var hasActiveFilterSummary: Bool {
        coordinator.activeWorkspace.activeTrafficSignal != nil
            || coordinator.activeWorkspace.activeFocusSet != nil
            || !coordinator.activeWorkspace.mutedTrafficSources.isEmpty
            || coordinator.filterCriteria.sidebarDomain != nil
            || coordinator.filterCriteria.sidebarPathPrefix != nil
            || coordinator.filterCriteria.sidebarApp != nil
            || coordinator.filterCriteria.sidebarScope == .saved
            || coordinator.filterCriteria.sidebarScope == .pinned
            || coordinator.filterCriteria.sidebarScope == .notes
    }

    private func shelfSurface<Content: View>(
        @ViewBuilder content: () -> Content
    )
        -> some View
    {
        content()
            .rockxyGlassEffect(
                in: RoundedRectangle(
                    cornerRadius: Theme.Glass.shelfCornerRadius,
                    style: .continuous
                )
            )
    }

    private var trafficCommandBar: some View {
        TrafficCommandBar(
            coordinator: coordinator,
            onOpenToolWindow: onOpenToolWindow,
            isEmbeddedInControlShelf: true,
            showsQuickTools: false
        )
    }

    private var searchFilterBar: some View {
        SearchFilterBar(
            searchText: Binding(
                get: { coordinator.filterCriteria.searchText },
                set: {
                    coordinator.filterCriteria.searchText = $0
                    coordinator.recomputeFilteredTransactions()
                }
            ),
            filterField: Binding(
                get: { coordinator.filterCriteria.searchField },
                set: {
                    coordinator.filterCriteria.searchField = $0
                    coordinator.recomputeFilteredTransactions()
                }
            ),
            isEnabled: Binding(
                get: { coordinator.filterCriteria.isSearchEnabled },
                set: {
                    coordinator.filterCriteria.isSearchEnabled = $0
                    coordinator.recomputeFilteredTransactions()
                }
            ),
            isAdvancedFilterVisible: coordinator.isFilterBarVisible,
            advancedFilterCount: advancedRuleCount,
            onAddFilter: coordinator.addAdvancedFilterRule,
            onToggleAdvancedFilters: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    coordinator.isFilterBarVisible.toggle()
                }
                coordinator.recomputeFilteredTransactions()
            },
            isEmbeddedInControlShelf: true
        )
    }
}
