import SwiftUI

// Drop affordance shown over the main workspace while a capture document is dragged in.

// MARK: - CaptureDocumentDropHighlight

/// Dashed accent outline plus a short hint, drawn while a HAR or session file
/// hovers over the workspace. Purely visual: it never takes hit testing, so the
/// drop still lands on the workspace's drop destination.
struct CaptureDocumentDropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.DropTarget.cornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(Theme.DropTarget.fillOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.DropTarget.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: Theme.DropTarget.lineWidth, dash: Theme.DropTarget.dash)
                    )
            }
            .overlay {
                Label(
                    String(localized: "Drop a HAR or Rockxy session to open it", bundle: RockxyLocalization.bundle),
                    systemImage: "tray.and.arrow.down"
                )
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
            }
            .padding(Theme.DropTarget.inset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
    }
}
