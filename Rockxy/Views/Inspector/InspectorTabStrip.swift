import SwiftUI

/// Single-line, horizontally scrollable tab strip used by the request/response inspector.
/// Keeps dense native macOS tab labels readable in narrow split panes without wrapping.
struct InspectorTabStrip<Content: View, TrailingContent: View>: View {
    let content: Content
    let trailingContent: TrailingContent

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.content = content()
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    content
                }
                .padding(.leading, 4)
                .frame(minWidth: 0, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            trailingContent
                .layoutPriority(1)
                .padding(.leading, 4)
                .padding(.trailing, 4)
        }
        .frame(minHeight: metrics.inspectorTabHeight)
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
