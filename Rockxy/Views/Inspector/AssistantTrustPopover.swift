import SwiftUI

/// Compact native explanation of the Assistant's local trust boundary.
struct AssistantTrustPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Read-only by default"), systemImage: "lock.shield.fill")
                .font(.headline)

            trustRow(
                String(localized: "Selected traffic only"),
                detail: String(localized: "Related requests are included only when you opt in."),
                systemImage: "checkmark.circle"
            )
            trustRow(
                String(localized: "Review before model access"),
                detail: String(localized: "You see the exact redacted snapshot before it is processed."),
                systemImage: "eye"
            )
            trustRow(
                String(localized: "Actions stay under your control"),
                detail: String(localized: "Compose, replay, export, and sharing open a native review step."),
                systemImage: "hand.raised"
            )
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    private func trustRow(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
