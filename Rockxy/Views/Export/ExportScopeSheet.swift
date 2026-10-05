import SwiftUI

// Renders the native export-scope review sheet. Membership is frozen in the
// `ExportScopeContext` before this view appears, so the picker only chooses
// which already-captured set to write — it can never widen the export.

// MARK: - ExportScopeSheet

/// Scope review sheet for traffic export. The normal flow offers a native
/// radio-group picker over the available scopes; a selection-locked context
/// (Assistant / Context Dock handoffs) shows a single locked summary instead of
/// a misleading set of choices.
struct ExportScopeSheet: View {
    // MARK: Lifecycle

    init(
        context: ExportScopeContext,
        onExport: @escaping (ExportScope, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.onExport = onExport
        self.onCancel = onCancel

        let initial = context.availableScopes.contains(context.initialScope)
            ? context.initialScope
            : (context.availableScopes.first ?? context.initialScope)
        _selectedScope = State(initialValue: initial)
    }

    // MARK: Internal

    let context: ExportScopeContext
    /// The chosen scope and whether recognized secrets are redacted in the written file.
    var onExport: (ExportScope, Bool) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if context.restrictsToSelection {
                lockedSelectionSummary
            } else {
                scopeSection
            }

            privacyNote

            if context.format.supportsRedaction {
                redactionToggle
            }

            footer
        }
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .font(toolMetrics.font())
        .frame(width: sheetWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exportScope.sheet")
    }

    // MARK: Private

    @State private var selectedScope: ExportScope
    @State private var redactsSensitiveData = false
    @Environment(\.appUIDisplayMetrics) private var appMetrics

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private var footerActionWidth: CGFloat {
        max(140, toolMetrics.bodyFontSize * 8)
    }

    private var sheetWidth: CGFloat {
        max(
            440,
            footerActionWidth * 2
                + toolMetrics.controlSpacing
                + 80
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(context.format.title)
                .font(toolMetrics.font(weight: .semibold))
            Text(context.format.subtitle)
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exportScope.header")
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Traffic to export", bundle: RockxyLocalization.bundle))

            if context.availableScopes.isEmpty {
                Text(String(
                    localized: "Nothing in this workspace can be exported in this format.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("exportScope.empty")
            } else {
                Picker(String(localized: "Scope", bundle: RockxyLocalization.bundle), selection: $selectedScope) {
                    ForEach(ExportScope.allCases, id: \.self) { scope in
                        Text(optionLabel(for: scope))
                            .tag(scope)
                            .disabled(!context.isEnabled(scope))
                            .accessibilityLabel(context.label(for: scope))
                            .accessibilityValue(context.countSummary(for: scope))
                            .accessibilityIdentifier("exportScope.option.\(scope.rawValue)")
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityIdentifier("exportScope.picker")
            }

            if let skippedNote = context.skippedNote(for: selectedScope),
               context.availableScopes.contains(selectedScope)
            {
                noteRow(skippedNote, systemImage: "scissors", identifier: "exportScope.skipped")
            }

            ForEach(context.unavailableScopes, id: \.self) { scope in
                if let reason = context.reason(for: scope) {
                    noteRow(
                        String(
                            localized: "\(context.label(for: scope)) — \(reason)",
                            bundle: RockxyLocalization.bundle
                        ),
                        systemImage: "minus.circle",
                        identifier: "exportScope.unavailable.\(scope.rawValue)"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var lockedSelectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Traffic to export", bundle: RockxyLocalization.bundle))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: toolMetrics.bodyFontSize + 4, height: toolMetrics.tableRowHeight)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(context.label(for: .selected))
                            .font(toolMetrics.font(weight: .medium))
                            .foregroundStyle(Color(nsColor: .labelColor))

                        Spacer()

                        Text(context.lockedSelectionSummary)
                            .font(toolMetrics.secondaryFont())
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }

                    Text(
                        String(
                            localized: "This review is limited to the selected requests. Other traffic will not be included.",
                            bundle: RockxyLocalization.bundle
                        )
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("exportScope.restriction")

            if let skippedNote = context.skippedNote(for: .selected) {
                noteRow(skippedNote, systemImage: "scissors", identifier: "exportScope.skipped")
            }

            if let reason = context.reason(for: .selected) {
                noteRow(reason, systemImage: "exclamationmark.circle", identifier: "exportScope.restrictionReason")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var privacyNote: some View {
        Text(context.format.privacyNote)
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("exportScope.privacy")
    }

    private var redactionToggle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(
                String(localized: "Redact sensitive data", bundle: RockxyLocalization.bundle),
                isOn: $redactsSensitiveData
            )
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("exportScope.redact")
            Text(String(
                localized: """
                Replaces recognized secrets such as Authorization, Cookie, API keys, and URL tokens with \
                [REDACTED] in the file. Best effort; review the file before sharing.
                """,
                bundle: RockxyLocalization.bundle
            ))
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
        }
    }

    private var footer: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Spacer()

            Button {
                onCancel()
            } label: {
                Text(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                    .frame(width: footerActionWidth)
            }
            .rockxyGlassButtonStyle()
            .frame(minHeight: toolMetrics.formControlHeight)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("exportScope.cancelButton")

            Button {
                onExport(selectedScope, context.format.supportsRedaction && redactsSensitiveData)
            } label: {
                Text(String(localized: "Export\u{2026}", bundle: RockxyLocalization.bundle))
                    .frame(width: footerActionWidth)
            }
            .rockxyGlassButtonStyle(prominent: true)
            .frame(minHeight: toolMetrics.formControlHeight)
            .keyboardShortcut(.defaultAction)
            .disabled(!context.isEnabled(selectedScope))
            .accessibilityIdentifier("exportScope.exportButton")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(toolMetrics.font(weight: .medium))
            .foregroundStyle(Color(nsColor: .labelColor))
    }

    private func noteRow(_ text: String, systemImage: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(toolMetrics.secondaryFont())
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func optionLabel(for scope: ExportScope) -> String {
        "\(context.label(for: scope)) · \(context.countSummary(for: scope))"
    }
}
