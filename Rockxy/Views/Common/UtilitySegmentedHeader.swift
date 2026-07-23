import SwiftUI

// MARK: - UtilitySegmentedHeader

struct UtilitySegmentedHeader<Content: View>: View {
    let width: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content()
                .frame(maxWidth: width)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - WorkspaceModeSwitcherStyle

extension View {
    /// Shared native presentation for the primary mode switchers in the workspace sidebar
    /// and Context Dock.
    func workspaceModeSwitcherStyle() -> some View {
        modifier(WorkspaceModeSwitcherModifier())
    }
}

private struct WorkspaceModeSwitcherModifier: ViewModifier {
    @Environment(\.appUIDisplayMetrics) private var metrics

    func body(content: Content) -> some View {
        content
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.regular)
            .font(.system(size: metrics.workspaceTabFontSize, weight: .medium))
            .frame(height: metrics.inspectorTabHeight)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}
