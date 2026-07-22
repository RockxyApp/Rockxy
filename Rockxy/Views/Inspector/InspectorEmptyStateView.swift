import SwiftUI

/// Centered empty state for inspector panes.
/// Inspector parents are top-leading by default, so plain `ContentUnavailableView`
/// can look accidentally pinned to the upper-left corner.
struct InspectorEmptyStateView: View {
    let title: String
    let systemImage: String
    var description: String?

    init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    /// Shared empty state for inspector surfaces that need a captured request.
    /// Keep this semantic presentation in one place so the horizontal payload
    /// inspector and vertical context inspector remain visually consistent.
    init(requestSelectionDescription description: String) {
        self.init(
            String(localized: "No Selection"),
            systemImage: "doc.text.magnifyingglass",
            description: description
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let description {
                ContentUnavailableView(
                    title,
                    systemImage: systemImage,
                    description: Text(description)
                )
            } else {
                ContentUnavailableView(title, systemImage: systemImage)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
