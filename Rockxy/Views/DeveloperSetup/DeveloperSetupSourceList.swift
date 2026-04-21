import SwiftUI

// MARK: - DeveloperSetupSourceList

struct DeveloperSetupSourceList: View {
    // MARK: Internal

    let selectedTarget: SetupTarget
    let sections: [SetupTargetSection]
    let isPinned: (SetupTarget) -> Bool
    let onSelect: (SetupTarget) -> Void
    let onTogglePinned: (SetupTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if sections.isEmpty {
                        emptySearchState
                    } else {
                        ForEach(sections) { section in
                            sectionView(category: section.category, targets: section.targets)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    // MARK: Private

    private var emptySearchState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "No matching setups"))
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "Try another runtime, browser, framework, environment, or category name."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func sectionView(category: SetupTargetCategory, targets: [SetupTarget]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 8)

            if targets.isEmpty {
                Text(emptySectionTitle(for: category))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ForEach(targets, id: \.id) { target in
                    HStack(spacing: 10) {
                        Image(systemName: target.iconName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selectedTarget.id == target.id ? .primary : .secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(target.title)
                                .font(.system(size: 13, weight: selectedTarget.id == target.id ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(target.supportStatus.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        pinButton(for: target)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedTarget.id == target.id ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.45) : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture {
                        onSelect(target)
                    }
                    .contextMenu {
                        Button(pinActionTitle(for: target)) {
                            onTogglePinned(target)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pinButton(for target: SetupTarget) -> some View {
        Button {
            onTogglePinned(target)
        } label: {
            Image(systemName: isPinned(target) ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPinned(target) ? Color(nsColor: .systemBlue) : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(isPinned(target) ? Color(nsColor: .systemBlue).opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(pinActionTitle(for: target))
    }

    private func pinActionTitle(for target: SetupTarget) -> String {
        if isPinned(target) {
            return String(localized: "Remove from Pinned")
        }

        return String(localized: "Pin to Pinned")
    }

    private func emptySectionTitle(for category: SetupTargetCategory) -> String {
        switch category {
        case .pinned:
            String(localized: "No pinned setups yet")
        case .savedProfile:
            String(localized: "No saved profiles yet")
        default:
            String(localized: "No setups in this section")
        }
    }
}
