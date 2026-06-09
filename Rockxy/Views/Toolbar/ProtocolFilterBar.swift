import SwiftUI

// Renders the protocol filter bar interface for toolbar controls and filtering.

// MARK: - ProtocolFilterBar

/// Horizontal row of filter pills for narrowing traffic by content type (JSON, HTML, Image, etc.)
/// and HTTP status category (2xx, 3xx, 4xx, 5xx). Content filters and status filters are applied
/// independently — a request must match at least one active filter in each group.
struct ProtocolFilterBar: View {
    // MARK: Internal

    @Binding var activeFilters: Set<ProtocolFilter>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ProtocolFilter.contentFilters, id: \.self) { filter in
                    FilterPillButton(
                        title: filter.displayName,
                        isActive: isActive(filter),
                        action: { toggle(filter) }
                    )
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                ForEach(ProtocolFilter.statusFilters, id: \.self) { filter in
                    FilterPillButton(
                        title: filter.displayName,
                        isActive: isActive(filter),
                        action: { toggle(filter) }
                    )
                }

                Spacer()

                if !activeFilters.isEmpty {
                    Button(String(localized: "Reset Filters")) {
                        activeFilters.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: metrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, max(4, (metrics.fontSize - 10) / 3))
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private func isActive(_ filter: ProtocolFilter) -> Bool {
        if filter == .all {
            let contentActive = activeFilters.filter { !$0.isStatusFilter }
            return contentActive.isEmpty
        }
        return activeFilters.contains(filter)
    }

    private func toggle(_ filter: ProtocolFilter) {
        if filter == .all {
            let statusFilters = activeFilters.filter(\.isStatusFilter)
            activeFilters = statusFilters
            return
        }

        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
            activeFilters.remove(.all)
        }
    }
}
