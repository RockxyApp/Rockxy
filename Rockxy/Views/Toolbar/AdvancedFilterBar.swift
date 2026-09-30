import AppKit
import SwiftUI

// Renders the advanced filter bar interface for toolbar controls and filtering.

// MARK: - AdvancedFilterBar

/// Multi-rule filter panel that lets users build compound filters with field/operator/value
/// rows. Each rule is independently toggleable and joined to the previous one with AND or OR;
/// AND binds tighter than OR.
struct AdvancedFilterBar: View {
    // MARK: Internal

    @Binding var rules: [FilterRule]

    var presetStore: FilterPresetStore
    var onSave: () -> Void = {}
    var onHide: () -> Void = {}
    var isEmbeddedInControlShelf = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, _ in
                filterRow(at: index, isFirst: index == 0)
            }
            shortcutsHint
        }
        .onExitCommand(perform: onHide)
        .background {
            // Keyboard access to the row buttons, active while the bar is on screen. Option-Command
            // keeps clear of the main menu's New and Delete shortcuts.
            Group {
                Button(String(localized: "Add filter below", bundle: RockxyLocalization.bundle)) {
                    addRule(after: focusedIndex ?? max(0, rules.count - 1))
                }
                .keyboardShortcut("=", modifiers: [.command, .option])
                Button(String(localized: "Remove filter", bundle: RockxyLocalization.bundle)) {
                    removeRule(at: focusedIndex ?? max(0, rules.count - 1))
                }
                .keyboardShortcut("-", modifiers: [.command, .option])
            }
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .onAppear {
            focusedRuleID = rules.last?.id
        }
        .background {
            if !isEmbeddedInControlShelf {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .overlay(alignment: .bottom) {
            if !isEmbeddedInControlShelf {
                Divider()
            }
        }
    }

    // MARK: Private

    private static let advancedFields: [FilterField] = [
        .all, .url, .method, .statusCode, .requestHeader, .responseHeader, .requestBody,
        .responseBody, .clientApp, .domain, .contentType, .queryString, .cookies,
        .graphQLOperation, .comment, .color,
    ]

    private static let enableToggleWidth: CGFloat = 22
    private static let connectorWidth: CGFloat = 76

    @Environment(\.appUIDisplayMetrics) private var metrics
    @FocusState private var focusedRuleID: UUID?

    private var shortcutsHint: some View {
        HStack(spacing: 12) {
            Text(String(localized: "Show or Hide: ⇧⌘F", bundle: RockxyLocalization.bundle))
            Text(String(localized: "Search: ⌘F", bundle: RockxyLocalization.bundle))
            Text(String(localized: "Hide: Esc", bundle: RockxyLocalization.bundle))
            Text(String(localized: "Add or Remove Row: ⌥⌘= / ⌥⌘-", bundle: RockxyLocalization.bundle))
        }
        .font(.system(size: max(10.5, metrics.secondaryFontSize - 0.5)))
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// The row whose value field has focus, so the keyboard shortcuts act on it.
    private var focusedIndex: Int? {
        focusedRuleID.flatMap { id in rules.firstIndex { $0.id == id } }
    }

    private var hasActiveRules: Bool {
        !FilterRuleEvaluator.activeRules(in: rules, isFilterBarVisible: true).isEmpty
    }

    private var presetMenu: some View {
        Menu {
            Button {
                if let name = PresetNamePrompt.ask(
                    title: String(localized: "Save Filter Preset", bundle: RockxyLocalization.bundle),
                    initialName: presetStore.suggestedName(for: rules)
                ) {
                    _ = presetStore.savePreset(name: name, rules: rules)
                    onSave()
                }
            } label: {
                Label(
                    String(localized: "Save Current Filter As…", bundle: RockxyLocalization.bundle),
                    systemImage: "square.and.arrow.down"
                )
            }
            .disabled(!hasActiveRules)

            if !presetStore.presets.isEmpty {
                Divider()
                ForEach(presetStore.presets) { preset in
                    Button {
                        rules = preset.rules.isEmpty ? [FilterRule()] : preset.rules
                    } label: {
                        Label(preset.name, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                Divider()
                Menu(String(localized: "Update Preset with Current Filter", bundle: RockxyLocalization.bundle)) {
                    ForEach(presetStore.presets) { preset in
                        Button(preset.name) {
                            presetStore.overwritePreset(id: preset.id, with: rules)
                        }
                    }
                }
                .disabled(!hasActiveRules)
                Menu(String(localized: "Rename Preset", bundle: RockxyLocalization.bundle)) {
                    ForEach(presetStore.presets) { preset in
                        Button(preset.name) {
                            if let name = PresetNamePrompt.ask(
                                title: String(localized: "Rename Filter Preset", bundle: RockxyLocalization.bundle),
                                initialName: preset.name
                            ) {
                                presetStore.renamePreset(id: preset.id, to: name)
                            }
                        }
                    }
                }
                Divider()
                Menu(String(localized: "Delete Preset", bundle: RockxyLocalization.bundle)) {
                    ForEach(presetStore.presets) { preset in
                        Button(role: .destructive) {
                            presetStore.deletePreset(id: preset.id)
                        } label: {
                            Text(preset.name)
                        }
                    }
                }
            }
        } label: {
            Label(String(localized: "Presets", bundle: RockxyLocalization.bundle), systemImage: "chevron.down")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
    }

    private func filterRow(at index: Int, isFirst: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rules[index].isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Self.enableToggleWidth, alignment: .center)
                .accessibilityLabel(String(localized: "Enable filter", bundle: RockxyLocalization.bundle))

            if isFirst {
                Text(String(localized: "Where", bundle: RockxyLocalization.bundle))
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.connectorWidth, alignment: .leading)
            } else {
                Picker("", selection: $rules[index].connector) {
                    ForEach(FilterLogicConnector.allCases, id: \.self) { connector in
                        Text(connector.displayName).tag(connector)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: Self.connectorWidth)
                .accessibilityLabel(String(localized: "Combine with previous filter", bundle: RockxyLocalization.bundle))
            }

            Picker("", selection: $rules[index].field) {
                ForEach(Self.advancedFields, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .frame(width: max(184, metrics.fontSize * 14))
            .accessibilityLabel(String(localized: "Filter field", bundle: RockxyLocalization.bundle))

            Picker("", selection: $rules[index].filterOperator) {
                ForEach(FilterOperator.allCases, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .frame(width: 120)
            .accessibilityLabel(String(localized: "Filter operator", bundle: RockxyLocalization.bundle))

            TextField(String(localized: "Text", bundle: RockxyLocalization.bundle), text: $rules[index].value)
                .textFieldStyle(.roundedBorder)
                .font(metrics.swiftUIFont())
                .focused($focusedRuleID, equals: rules[index].id)
                .accessibilityLabel(String(localized: "Filter value", bundle: RockxyLocalization.bundle))
                .overlay {
                    // An unfinished regular expression matches nothing; say so instead of
                    // silently emptying the table.
                    if rules[index].filterOperator == .regex, !rules[index].value.isEmpty,
                       !FilterRegexCache.isValid(rules[index].value)
                    {
                        RoundedRectangle(cornerRadius: 5).stroke(Color.red, lineWidth: 1)
                            .help(String(localized: "This regular expression is not valid yet.", bundle: RockxyLocalization.bundle))
                    }
                }

            Button {
                removeRule(at: index)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: metrics.controlFontSize, weight: .medium))
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)
            .accessibilityLabel(String(localized: "Remove filter", bundle: RockxyLocalization.bundle))

            Button {
                addRule(after: index)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: metrics.controlFontSize, weight: .medium))
            }
            .rockxyGlassButtonStyle()
            .controlSize(.small)
            .accessibilityLabel(String(localized: "Add filter below", bundle: RockxyLocalization.bundle))

            if isFirst {
                presetMenu
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, index == 0 ? 8 : 4)
        .padding(.bottom, 0)
        .frame(minHeight: max(30, metrics.fontSize + 18))
        .opacity(rules[index].isEnabled ? 1.0 : 0.5)
    }

    private func addRule(after index: Int) {
        let newRule = FilterRule()
        rules.insert(newRule, at: index + 1)
    }

    private func removeRule(at index: Int) {
        // The only row cannot be removed, so it is cleared instead of doing nothing.
        guard rules.count > 1 else {
            rules[index].value = ""
            return
        }
        rules.remove(at: index)
    }
}

// MARK: - PresetNamePrompt

/// Asks for a filter preset name in a standard alert with a text field.
@MainActor
enum PresetNamePrompt {
    static func ask(title: String, initialName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: String(localized: "Save", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initialName
        field.placeholderString = String(localized: "Preset Name", bundle: RockxyLocalization.bundle)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
