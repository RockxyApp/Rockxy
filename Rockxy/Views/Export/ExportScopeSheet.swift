import SwiftUI

// Renders the export scope sheet interface for session export.

// MARK: - ExportScopeSheet

/// Scope picker sheet for HAR export. Shows radio-style selection for All/Filtered/Selected
/// transaction scopes with counts, plus a privacy note. Matches the Figma design at file
/// BmxrbvKOU3Q2wZUe2NT87Y node 8:4.
struct ExportScopeSheet: View {
    // MARK: Lifecycle

    init(
        context: ExportScopeContext,
        onExport: @escaping (ExportScope) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.onExport = onExport
        self.onCancel = onCancel
        _selectedScope = State(initialValue: context.initialScope)
    }

    // MARK: Internal

    let context: ExportScopeContext
    var onExport: (ExportScope) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title

            sectionLabel(String(localized: "SCOPE"))

            scopePicker

            privacyNote

            bottomBar
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .font(toolMetrics.font())
        .frame(width: max(420, toolMetrics.fieldWidth(420)))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Private

    @State private var selectedScope: ExportScope = .all

    private var title: some View {
        Text(context.format.title)
            .font(toolMetrics.font(weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var scopePicker: some View {
        VStack(spacing: 0) {
            scopeRow(
                scope: .all,
                label: context.label(for: .all),
                count: context.eligibleCount(for: .all),
                isDisabled: !context.isEnabled(.all)
            )

            dividerLine

            scopeRow(
                scope: .filtered,
                label: context.label(for: .filtered),
                count: context.eligibleCount(for: .filtered),
                isDisabled: !context.isEnabled(.filtered)
            )

            dividerLine

            scopeRow(
                scope: .selected,
                label: context.label(for: .selected),
                count: context.eligibleCount(for: .selected),
                isDisabled: !context.isEnabled(.selected)
            )
        }
    }

    private var privacyNote: some View {
        Text(context.format.privacyNote)
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            dividerLine

            HStack(spacing: 8) {
                Spacer()

                Button(String(localized: "Cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .frame(width: toolMetrics.footerButtonWidth)
                .frame(minHeight: toolMetrics.formControlHeight)

                Button {
                    onExport(selectedScope)
                } label: {
                    Text(String(localized: "Export\u{2026}"))
                        .font(toolMetrics.font(weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: toolMetrics.footerButtonWidth)
                        .frame(minHeight: toolMetrics.formControlHeight)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!context.isEnabled(selectedScope))
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(toolMetrics.metadataFont(weight: .medium))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .tracking(0.3)
            .textCase(.uppercase)
    }

    private func scopeRow(
        scope: ExportScope,
        label: String,
        count: Int,
        isDisabled: Bool
    )
        -> some View
    {
        let isSelected = selectedScope == scope

        return Button {
            if !isDisabled {
                selectedScope = scope
            }
        } label: {
            HStack(spacing: 0) {
                radioIndicator(isSelected: isSelected, isDisabled: isDisabled)

                Spacer()
                    .frame(width: 8)

                Text(label)
                    .font(toolMetrics.font())
                    .foregroundStyle(
                        isSelected
                            ? .white
                            : isDisabled
                            ? Color(nsColor: .tertiaryLabelColor)
                            : Color(nsColor: .labelColor)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(count)")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(
                        isSelected
                            ? .white
                            : Color(nsColor: .secondaryLabelColor)
                    )
            }
            .padding(.horizontal, 12)
            .frame(minHeight: toolMetrics.formControlHeight)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func radioIndicator(isSelected: Bool, isDisabled: Bool) -> some View {
        Circle()
            .strokeBorder(
                isSelected
                    ? Color.white
                    : isDisabled
                    ? Color(nsColor: .tertiaryLabelColor)
                    : Color(nsColor: .secondaryLabelColor),
                lineWidth: isSelected ? 4 : 1.5
            )
            .background(
                Circle()
                    .fill(isSelected ? Color.white : Color.clear)
                    .padding(isSelected ? 3 : 0)
            )
            .frame(width: 14, height: 14)
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }
}
