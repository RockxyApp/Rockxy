import SwiftUI

// MARK: - PersistenceFailureBanner

/// Inline, non-modal band shown above a list the user edits when writing that list to disk
/// failed. The edit still applies for this session, so without this the list looks saved and
/// is silently gone next launch.
///
/// Styled like the HTTPS Decryption info banner's warning state (orange wash, triangle glyph,
/// secondary text) so the settings tools share one inline-warning look. The retry button is
/// in the normal tab order; VoiceOver reads the message as one element, and an announcement is
/// posted when the banner appears because it arrives without focus moving.
struct PersistenceFailureBanner: View {
    // MARK: Lifecycle

    /// `detail` defaults to the save-failure guidance; `reason` is omitted when `detail` already
    /// carries it. `actionTitle` defaults to the save retry label.
    init(
        title: String,
        detail: String? = nil,
        reason: String? = nil,
        actionTitle: String? = nil,
        retry: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail ?? Self.guidance
        self.reason = reason
        self.actionTitle = actionTitle ?? String(localized: "Try Saving Again", bundle: RockxyLocalization.bundle)
        self.retry = retry
    }

    // MARK: Internal

    let title: String
    let detail: String
    let reason: String?
    let actionTitle: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(toolMetrics.secondaryFont(weight: .semibold))
                Text(detail)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let reason {
                    Text(reason)
                        .font(toolMetrics.metadataFont())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue([detail, reason].compactMap { $0 }.joined(separator: " "))

            Spacer(minLength: 0)

            Button(actionTitle, action: retry)
                .font(toolMetrics.secondaryFont())
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color.orange.opacity(0.12))
        .accessibilityIdentifier("persistenceFailureBanner")
        .onAppear {
            AccessibilityNotification.Announcement("\(title). \(detail)").post()
        }
    }

    // MARK: Private

    private static var guidance: String {
        String(
            localized: """
            Your change applies until you quit Rockxy, but the saved copy was not updated, so the list will \
            come back as it was on the next launch. Make sure the disk has free space and Rockxy's data folder \
            is writable, then try again.
            """,
            bundle: RockxyLocalization.bundle
        )
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
