import SwiftUI

// Bandwidth and packet-loss fields shown when the Custom Network Conditions
// profile is selected. Empty bandwidth means unlimited in that direction.

struct NetworkCustomProfileFields: View {
    @Binding var profile: NetworkCustomProfile

    var body: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            field(
                String(localized: "Download", bundle: RockxyLocalization.bundle),
                unit: String(localized: "kbps", bundle: RockxyLocalization.bundle)
            ) {
                TextField(
                    String(localized: "Unlimited", bundle: RockxyLocalization.bundle),
                    value: $profile.downloadKbps,
                    format: .number
                )
                .accessibilityLabel(String(
                    localized: "Custom download bandwidth in kilobits per second",
                    bundle: RockxyLocalization.bundle
                ))
            }
            field(
                String(localized: "Upload", bundle: RockxyLocalization.bundle),
                unit: String(localized: "kbps", bundle: RockxyLocalization.bundle)
            ) {
                TextField(
                    String(localized: "Unlimited", bundle: RockxyLocalization.bundle),
                    value: $profile.uploadKbps,
                    format: .number
                )
                .accessibilityLabel(String(
                    localized: "Custom upload bandwidth in kilobits per second",
                    bundle: RockxyLocalization.bundle
                ))
            }
            field(String(localized: "Packet Loss", bundle: RockxyLocalization.bundle), unit: "%") {
                TextField(Self.zeroPlaceholder, value: $profile.packetLossPercent, format: .number)
                    .accessibilityLabel(String(
                        localized: "Custom packet loss percentage",
                        bundle: RockxyLocalization.bundle
                    ))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Private

    private static let zeroPlaceholder = "0"

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private func field(
        _ label: String,
        unit: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                content()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: toolMetrics.fieldWidth(100))
                Text(unit)
                    .foregroundStyle(.secondary)
            }
            .font(toolMetrics.font())
            .controlSize(.regular)
            .frame(height: toolMetrics.formControlHeight)
        }
    }
}
