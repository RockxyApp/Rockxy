import SwiftUI

/// Model-aware context control kept separate from the provider form's general connection fields.
struct AssistantContextWindowSettingsField: View {
    @Binding var configuration: AssistantProviderConfiguration
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    var body: some View {
        SettingsFieldRow(String(localized: "Context Window")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField(
                        String(localized: "Context window tokens"),
                        value: contextWindow,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: settingsMetrics.fieldWidth(120))
                    Text(String(localized: "tokens"))
                        .foregroundStyle(.secondary)
                }
                Text(
                    String(
                        localized: "Detected from Ollama when available. Rockxy reserves space for instructions and output before attaching traffic."
                    )
                )
                .font(settingsMetrics.metadataFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var contextWindow: Binding<Int> {
        Binding(
            get: {
                configuration.effectiveContextWindowTokens
                    ?? AssistantProviderConfiguration.defaultLocalContextWindowTokens
            },
            set: { configuration.contextWindowTokens = $0 }
        )
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
