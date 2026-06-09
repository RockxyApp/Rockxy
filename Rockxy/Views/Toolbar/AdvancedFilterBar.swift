import SwiftUI

// Renders the advanced filter bar interface for toolbar controls and filtering.

// MARK: - AdvancedFilterBar

/// Multi-rule filter panel that lets users build compound filters with field/operator/value
/// rows. Each rule is independently toggleable. Rules are AND-combined — a transaction must
/// match all enabled rules to pass.
struct AdvancedFilterBar: View {
    // MARK: Internal

    @Binding var rules: [FilterRule]

    var presetStore: FilterPresetStore
    var onSave: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, _ in
                filterRow(at: index, isFirst: index == 0)
            }
            shortcutsHint
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Private

    private var shortcutsHint: some View {
        HStack(spacing: 12) {
            Text("Show: ⌘F")
            Text("New: ⌘N")
            Text("Remove: ⌥⌘N")
            Text("Up: ⌘↑")
            Text("Down: ⌘↓")
            Text("On/Off: ⌘B")
            Text("Hide: ESC")
        }
        .font(.system(size: max(10.5, metrics.secondaryFontSize - 0.5)))
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func filterRow(at index: Int, isFirst: Bool) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rules[index].isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Self.enableToggleWidth, alignment: .center)

            if isFirst {
                Text("Where")
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
            }

            Picker("", selection: $rules[index].field) {
                ForEach(Self.advancedFields, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .frame(width: 138)

            Picker("", selection: $rules[index].filterOperator) {
                ForEach(FilterOperator.allCases, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .frame(width: 120)

            TextField(String(localized: "Text"), text: $rules[index].value)
                .textFieldStyle(.roundedBorder)
                .font(metrics.swiftUIFont())

            Button {
                removeRule(at: index)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                addRule(after: index)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

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
        guard rules.count > 1 else {
            return
        }
        rules.remove(at: index)
    }

    private static let advancedFields: [FilterField] = [
        .url, .method, .statusCode, .requestHeader, .responseHeader, .requestBody,
        .responseBody, .clientApp, .domain, .contentType, .queryString, .cookies,
        .comment, .color,
    ]

    private static let enableToggleWidth: CGFloat = 22
    private static let connectorWidth: CGFloat = 76

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var presetMenu: some View {
        Menu {
            Button {
                _ = presetStore.saveGeneratedPreset(rules: rules)
                onSave()
            } label: {
                Label(String(localized: "Save Current Filter"), systemImage: "square.and.arrow.down")
            }
            .disabled(FilterRuleEvaluator.activeRules(in: rules, isFilterBarVisible: true).isEmpty)

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
                Menu(String(localized: "Delete Preset")) {
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
            Label(String(localized: "Presets"), systemImage: "chevron.down")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
    }
}
