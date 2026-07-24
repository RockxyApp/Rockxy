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
                        localized: "Rockxy uses 8,192 tokens by default and limits local inference to 32,768 tokens to avoid excessive memory pressure."
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
            set: {
                let valid = AssistantProviderConfiguration.validContextWindowTokens($0)
                    ?? AssistantProviderConfiguration.defaultLocalContextWindowTokens
                configuration.contextWindowTokens = configuration.kind == .ollama
                    ? min(valid, AssistantProviderConfiguration.maxLocalContextWindowTokens)
                    : valid
            }
        )
    }

    private var settingsMetrics: SettingsDisplayMetrics {
        SettingsDisplayMetrics(appMetrics: appMetrics)
    }
}
