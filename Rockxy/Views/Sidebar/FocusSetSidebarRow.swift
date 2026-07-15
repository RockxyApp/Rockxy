import SwiftUI

// MARK: - FocusSetSidebarRow

/// Compact source-list row that keeps a Focus Set scannable while exposing its exact rules on demand.
struct FocusSetSidebarRow: View {
    // MARK: Internal

    let focusSet: FocusSet
    let isActive: Bool
    @Binding var isExpanded: Bool

    let onApply: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                if !focusSet.includedRules.isEmpty {
                    ruleGroup(
                        title: String(localized: "Include · all must match"),
                        systemImage: "checkmark.circle",
                        rules: focusSet.includedRules
                    )
                }
                if !focusSet.excludedRules.isEmpty {
                    ruleGroup(
                        title: String(localized: "Exclude · any match is hidden"),
                        systemImage: "minus.circle",
                        rules: focusSet.excludedRules
                    )
                }
            }
            .padding(.top, 4)
            .padding(.leading, 2)
        } label: {
            Button(action: onApply) {
                HStack(alignment: .top, spacing: 7) {
                    leadingIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(focusSet.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(compactSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 6)

                    Text(ruleCountLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(String(localized: "Active"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isActive
                ? String(localized: "This Focus Set is active. Click to reapply it.")
                : String(localized: "Apply this Focus Set."))
        }
    }

    // MARK: Private

    private var compactSummary: String {
        let includes = focusSet.includedRules.map(compactRule).joined(separator: " · ")
        let excludes = focusSet.excludedRules.map(compactRule).joined(separator: " · ")
        guard !excludes.isEmpty else {
            return includes
        }
        guard !includes.isEmpty else {
            return String(localized: "Exclude \(excludes)")
        }
        return String(localized: "\(includes) · except \(excludes)")
    }

    private var ruleCountLabel: String {
        focusSet.ruleCount == 1
            ? String(localized: "1 rule")
            : String(localized: "\(focusSet.ruleCount) rules")
    }

    @ViewBuilder private var leadingIcon: some View {
        if focusSet.appName.isEmpty {
            Image(systemName: "scope")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)
        } else {
            CapturedApplicationIconView(name: focusSet.appName, size: 20)
        }
    }

    private func ruleGroup(
        title: String,
        systemImage: String,
        rules: [FocusSetRuleDescriptor]
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(rules) { rule in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                    Text(ruleLabel(rule.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(rule.pattern)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(rule.pattern)
                }
            }
        }
    }

    private func compactRule(_ rule: FocusSetRuleDescriptor) -> String {
        "\(ruleLabel(rule.kind)): \(rule.pattern)"
    }

    private func ruleLabel(_ kind: FocusSetRuleDescriptor.Kind) -> String {
        switch kind {
        case .application:
            String(localized: "App")
        case .domain:
            String(localized: "Domain")
        case .pathPrefix:
            String(localized: "Path")
        }
    }
}
