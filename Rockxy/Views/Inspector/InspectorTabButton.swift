import SwiftUI

/// Reusable tab button for the inspector tab bars. Renders as a plain text button
/// with bold/regular weight to indicate active state, styled via `Theme.Inspector`.
struct InspectorTabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .bold : .regular))
                .foregroundStyle(isActive ? Theme.Inspector.tabActive : Theme.Inspector.tabInactive)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}
