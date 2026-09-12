import SwiftUI

// Renders the system proxy warning banner interface for toolbar controls and filtering.

// MARK: - SystemProxyWarningBanner

/// Inline warning banner shown when proxy/runtime configuration needs user attention.
/// Styled like Xcode's build warning bar with an orange tint and compact macOS controls.
struct SystemProxyWarningBanner: View {
    let message: String
    var primaryActionTitle: String?
    var isActionInProgress = false
    var onPrimaryAction: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: metrics.chromeIconFontSize))

            Text(message)
                .font(.system(size: metrics.chromeSecondaryFontSize))
                .foregroundStyle(.secondary)

            Spacer()

            if let primaryActionTitle, let onPrimaryAction {
                Button(action: onPrimaryAction) {
                    if isActionInProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(primaryActionTitle)
                    }
                }
                    .font(.system(size: metrics.chromeBadgeFontSize))
                    .rockxyGlassButtonStyle()
                    .controlSize(.small)
                    .disabled(isActionInProgress)
                    .accessibilityLabel(primaryActionTitle)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: metrics.badgeFontSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
}
