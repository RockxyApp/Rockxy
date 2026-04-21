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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    content
                }
                .padding(.vertical, 4)
                .padding(.leading, 4)
                .frame(minWidth: 0, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingContent
                .padding(.leading, 4)
                .padding(.trailing, 4)
        }
    }
}
