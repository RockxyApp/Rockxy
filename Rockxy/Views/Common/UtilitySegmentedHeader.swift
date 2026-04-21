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
