import SwiftUI

// Renders the filter pill button interface for toolbar controls and filtering.

// MARK: - FilterPillButton

/// Compact toggle-style pill button used in the protocol filter bar. Renders with themed
/// active/inactive colors from `Theme.FilterPill`.
struct FilterPillButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: metrics.secondaryFontSize, weight: isActive ? .semibold : .regular))
                .foregroundStyle(
                    isActive
                        ? Theme.FilterPill.activeForeground
                        : Theme.FilterPill.inactiveForeground
                )
                .padding(.horizontal, 8)
                .padding(.vertical, max(3, (metrics.fontSize - 10) / 3))
                .background(
                    isActive
                        ? Theme.FilterPill.activeBackground
                        : Theme.FilterPill.inactiveBackground
                )
                .cornerRadius(4)
        }
        .buttonStyle(.borderless)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
