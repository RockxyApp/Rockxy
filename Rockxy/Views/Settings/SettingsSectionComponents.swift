import SwiftUI

// MARK: - SettingsSectionCard

/// Shared visual grouping for dense Settings panes.
/// Matches the section title, inset card, and field alignment used by General Settings.
struct SettingsSectionCard<Content: View>: View {
    // MARK: Lifecycle

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    // MARK: Internal

    let title: String
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(settingsMetrics.font(weight: .medium))

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.primary.opacity(0.035))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.62), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.07), radius: 1, y: 1)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - SettingsFieldRow

struct SettingsFieldRow<Content: View>: View {
    // MARK: Lifecycle

    init(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.content = content()
    }

    // MARK: Internal

    let label: String
    let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(settingsMetrics.font(weight: .medium))
                .frame(width: settingsMetrics.labelWidth, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.top, 3)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}

// MARK: - SettingsIndentedContent

struct SettingsIndentedContent<Content: View>: View {
    // MARK: Internal

    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: settingsMetrics.rowLeading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
