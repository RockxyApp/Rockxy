import SwiftUI

// Renders the active filter summary bar interface for toolbar controls and filtering.

// MARK: - ActiveFilterSummaryBar

/// Compact horizontal bar displaying removable chips for each active filter dimension.
/// Only visible when at least one filter is active, providing at-a-glance filter state
/// and one-tap clearing of individual or all filters.
struct ActiveFilterSummaryBar: View {
    // MARK: Internal

    let coordinator: MainContentCoordinator

    var body: some View {
        if hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let domain = coordinator.filterCriteria.sidebarDomain {
                        let pathPrefix = coordinator.filterCriteria.sidebarPathPrefix ?? ""
                        FilterChip(
                            label: String(localized: "Domain: \(domain)\(pathPrefix)"),
                            onRemove: {
                                coordinator.filterCriteria.sidebarDomain = nil
                                coordinator.filterCriteria.sidebarPathPrefix = nil
                                coordinator.sidebarSelection = nil
                                coordinator.recomputeFilteredTransactions()
                            }
                        )
                    }

                    if let app = coordinator.filterCriteria.sidebarApp {
                        FilterChip(
                            label: String(localized: "App: \(app)"),
                            onRemove: {
                                coordinator.filterCriteria.sidebarApp = nil
                                coordinator.sidebarSelection = nil
                                coordinator.recomputeFilteredTransactions()
                            }
                        )
                    }

                    if coordinator.filterCriteria.sidebarScope == .saved {
                        FilterChip(label: String(localized: "Saved")) {
                            coordinator.filterCriteria.sidebarScope = .allTraffic
                            coordinator.filterCriteria.exactTransactionID = nil
                            coordinator.sidebarSelection = nil
                            coordinator.recomputeFilteredTransactions()
                        }
                    }

                    if coordinator.filterCriteria.sidebarScope == .pinned {
                        FilterChip(label: String(localized: "Pinned")) {
                            coordinator.filterCriteria.sidebarScope = .allTraffic
                            coordinator.filterCriteria.exactTransactionID = nil
                            coordinator.sidebarSelection = nil
                            coordinator.recomputeFilteredTransactions()
                        }
                    }

                    if coordinator.filterCriteria.isSearchEnabled,
                       !coordinator.filterCriteria.searchText.isEmpty
                    {
                        let field = coordinator.filterCriteria.searchField.displayName
                        let text = coordinator.filterCriteria.searchText
                        FilterChip(
                            label: "\(field): \(text)",
                            onRemove: {
                                coordinator.filterCriteria.searchText = ""
                                coordinator.recomputeFilteredTransactions()
                            }
                        )
                    }

                    if !coordinator.filterCriteria.activeProtocolFilters.isEmpty {
                        let count = coordinator.filterCriteria.activeProtocolFilters.count
                        FilterChip(
                            label: String(localized: "\(count) protocol filters"),
                            onRemove: {
                                coordinator.filterCriteria.activeProtocolFilters.removeAll()
                                coordinator.recomputeFilteredTransactions()
                            }
                        )
                    }

                    if coordinator.isFilterBarVisible,
                       coordinator.filterRules.contains(where: { $0.isEnabled && !$0.value.isEmpty })
                    {
                        let count = coordinator.filterRules.filter { $0.isEnabled && !$0.value.isEmpty }.count
                        FilterChip(
                            label: String(localized: "\(count) rules active"),
                            onRemove: {
                                coordinator.isFilterBarVisible = false
                                coordinator.recomputeFilteredTransactions()
                            }
                        )
                    }

                    Button(String(localized: "Clear All")) {
                        clearAllFilters()
                    }
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
            }
            .frame(height: metrics.filterBarHeight)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var hasActiveFilters: Bool {
        coordinator.filterCriteria.sidebarDomain != nil
            || coordinator.filterCriteria.sidebarPathPrefix != nil
            || coordinator.filterCriteria.sidebarApp != nil
            || coordinator.filterCriteria.sidebarScope == .saved
            || coordinator.filterCriteria.sidebarScope == .pinned
            || (coordinator.filterCriteria.isSearchEnabled && !coordinator.filterCriteria.searchText.isEmpty)
            || !coordinator.filterCriteria.activeProtocolFilters.isEmpty
            || (coordinator.isFilterBarVisible
                && coordinator.filterRules.contains(where: { $0.isEnabled && !$0.value.isEmpty }))
    }

    private func clearAllFilters() {
        coordinator.filterCriteria = .empty
        coordinator.filterCriteria.sidebarScope = .allTraffic
        coordinator.sidebarSelection = nil
        coordinator.isFilterBarVisible = false
        coordinator.filterRules = [FilterRule()]
        coordinator.recomputeFilteredTransactions()
    }
}

// MARK: - FilterChip

/// Removable pill displaying a single active filter with an X button.
private struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: metrics.secondaryFontSize))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: metrics.badgeFontSize))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
        )
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
