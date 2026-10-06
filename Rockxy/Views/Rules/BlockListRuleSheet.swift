import SwiftUI

// The Add / Edit sheet for Block List rules, extracted from `BlockListWindowView.swift`
// to keep that file within the length limit.

// MARK: - BlockRuleSaveHandler

/// Name, pattern, method, match type, action, include subpaths, GraphQL operation, hide, application.
typealias BlockRuleSaveHandler = (
    String, String, HTTPMethodFilter, BlockMatchType, BlockActionType, Bool, String, Bool, String
) -> Void

// MARK: - AddBlockRuleSheet

struct AddBlockRuleSheet: View {
    // MARK: Lifecycle

    init(
        session: BlockListEditorSession,
        onSave: @escaping BlockRuleSaveHandler
    ) {
        self.session = session
        self.onSave = onSave
        switch session.mode {
        case let .create(context):
            _ruleName = State(initialValue: context?.suggestedName ?? "")
            _urlPattern = State(initialValue: context?.defaultPattern ?? "")
            _httpMethod = State(initialValue: context?.httpMethod ?? .any)
            _matchType = State(initialValue: context?.defaultMatchType ?? .wildcard)
            _blockAction = State(initialValue: context?.defaultAction ?? .returnForbidden)
            _includeSubpaths = State(initialValue: context?.includeSubpaths ?? true)
            _graphQLOperationName = State(initialValue: context?.graphQLOperationName ?? "")
            _hidesMatchedTraffic = State(initialValue: false)
            _clientApplication = State(initialValue: "")
        case let .edit(rule):
            _ruleName = State(initialValue: rule.name)
            _hidesMatchedTraffic = State(initialValue: rule.hidesMatchedTraffic)
            _clientApplication = State(initialValue: rule.matchCondition.clientApplication ?? "")
            _graphQLOperationName = State(initialValue: rule.matchCondition.graphQLOperationName ?? "")
            let normalizedMethod = rule.matchCondition.method?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            _httpMethod = State(
                initialValue: normalizedMethod.flatMap(HTTPMethodFilter.init(rawValue:)) ?? .any
            )
            if let sourcePattern = rule.matchCondition.sourceURLPattern {
                _urlPattern = State(initialValue: sourcePattern)
                _matchType = State(initialValue: rule.matchCondition.matchType ?? .regex)
                _includeSubpaths = State(
                    initialValue: rule.matchCondition.matchType == .wildcard
                        ? rule.matchCondition.includeSubpaths ?? false
                        : false
                )
            } else {
                _urlPattern = State(initialValue: rule.matchCondition.urlPattern ?? "")
                _matchType = State(initialValue: .regex)
                _includeSubpaths = State(initialValue: false)
            }
            _blockAction = State(initialValue: rule.blockActionType)
        }
    }

    // MARK: Internal

    let session: BlockListEditorSession
    let onSave: BlockRuleSaveHandler

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                Text(isEditing ? String(localized: "Edit Block Rule", bundle: RockxyLocalization.bundle) : String(
                    localized: "New Block Rule",
                    bundle: RockxyLocalization.bundle
                ))
                .font(
                    .system(
                        size: max(15, toolMetrics.bodyFontSize + 2),
                        weight: .semibold
                    )
                )

                provenanceBanner

                ruleDetailsSection
                decisionSection
                RuleURLTesterSection(toolMetrics: toolMetrics) {
                    let subpaths = matchType == .wildcard ? includeSubpaths : false
                    return RuleMatchCondition(
                        urlPattern: RulePatternBuilder.regexSource(
                            rawPattern: trimmedPattern,
                            matchType: matchType,
                            includeSubpaths: subpaths
                        ),
                        sourceURLPattern: trimmedPattern,
                        method: httpMethod.methodValue,
                        matchType: matchType,
                        includeSubpaths: subpaths,
                        clientApplication: clientApplication
                    )
                }
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.top, toolMetrics.formVerticalPadding)
            .padding(.bottom, toolMetrics.formVerticalPadding)

            Divider()

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    footerButtonLabel(String(localized: "Cancel", bundle: RockxyLocalization.bundle))
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    onSave(
                        trimmedName,
                        trimmedPattern,
                        httpMethod,
                        matchType,
                        blockAction,
                        matchType == .wildcard ? includeSubpaths : false,
                        graphQLOperationName,
                        hidesMatchedTraffic,
                        clientApplication
                    )
                    dismiss()
                } label: {
                    footerButtonLabel(primaryButtonTitle)
                }
                .keyboardShortcut(.defaultAction)
                .rockxyGlassButtonStyle(prominent: true)
                .disabled(trimmedPattern.isEmpty)
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding)
            .padding(.vertical, toolMetrics.controlSpacing)
        }
        .font(toolMetrics.font())
        .frame(minWidth: max(720, toolMetrics.bodyFontSize * 24 + 408))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @State private var ruleName: String
    @State private var urlPattern: String
    @State private var hidesMatchedTraffic: Bool
    @State private var httpMethod: HTTPMethodFilter
    @State private var matchType: BlockMatchType
    @State private var blockAction: BlockActionType
    @State private var includeSubpaths: Bool
    @State private var graphQLOperationName: String
    @State private var clientApplication: String

    private var isEditing: Bool {
        if case .edit = session.mode {
            return true
        }
        return false
    }

    private var primaryButtonTitle: String {
        isEditing ? String(localized: "Save", bundle: RockxyLocalization.bundle) : String(
            localized: "Add",
            bundle: RockxyLocalization.bundle
        )
    }

    private var trimmedName: String {
        ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPattern: String {
        urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var actionDescription: String {
        switch blockAction {
        case .returnForbidden:
            String(localized: "Send an HTTP 403 response to the client.", bundle: RockxyLocalization.bundle)
        case .dropConnection:
            String(
                localized: "Close the matching client connection without a response.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    @ViewBuilder private var provenanceBanner: some View {
        if case let .create(context?) = session.mode {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                Group {
                    switch context.origin {
                    case .selectedTransaction:
                        if let method = context.sourceMethod {
                            Text(String(
                                localized: "Created from: \(method) \(context.sourceHost)\(context.sourcePath ?? "")",
                                bundle: RockxyLocalization.bundle
                            ))
                        } else {
                            Text(String(
                                localized: "Created from: \(context.sourceHost)\(context.sourcePath ?? "")",
                                bundle: RockxyLocalization.bundle
                            ))
                        }
                    case .domainQuickCreate:
                        Text(String(
                            localized: "Created from domain: \(context.sourceHost)",
                            bundle: RockxyLocalization.bundle
                        ))
                    }
                }
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var ruleDetailsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Rule Details", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing) {
                identityFields
                methodAndMatchRow
                conditionalFields
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var identityFields: some View {
        HStack(alignment: .top, spacing: toolMetrics.controlSpacing) {
            fieldGroup(String(localized: "Name", bundle: RockxyLocalization.bundle)) {
                TextField(String(localized: "Untitled", bundle: RockxyLocalization.bundle), text: $ruleName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "Rule name", bundle: RockxyLocalization.bundle))
            }
            .frame(width: max(250, toolMetrics.fieldWidth(250)))

            fieldGroup(String(localized: "URL pattern", bundle: RockxyLocalization.bundle)) {
                TextField("https://example.com/api/*", text: $urlPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .accessibilityLabel(String(localized: "URL pattern", bundle: RockxyLocalization.bundle))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var methodAndMatchRow: some View {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
            inlineField(String(localized: "Method", bundle: RockxyLocalization.bundle)) {
                Menu {
                    ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                        Button {
                            httpMethod = method
                        } label: {
                            menuCheckmarkLabel(method.rawValue, isSelected: httpMethod == method)
                        }
                    }
                } label: {
                    dataEntryMenuLabel(httpMethod.rawValue, width: toolMetrics.menuWidth(90))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "HTTP Method", bundle: RockxyLocalization.bundle))
                .frame(width: toolMetrics.menuWidth(90))
            }

            inlineField(String(localized: "Match type", bundle: RockxyLocalization.bundle)) {
                Menu {
                    ForEach(BlockMatchType.allCases, id: \.self) { type in
                        Button {
                            matchType = type
                        } label: {
                            menuCheckmarkLabel(type.rawValue, isSelected: matchType == type)
                        }
                    }
                } label: {
                    dataEntryMenuLabel(matchType.rawValue, width: toolMetrics.menuWidth(175))
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Match Type", bundle: RockxyLocalization.bundle))
                .frame(width: toolMetrics.menuWidth(175))
            }

            if matchType == .wildcard {
                Text(String(localized: "Support wildcard * and ?.", bundle: RockxyLocalization.bundle))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    @ViewBuilder private var conditionalFields: some View {
        if matchType == .wildcard {
            Toggle(
                String(localized: "Include all subpaths of this URL", bundle: RockxyLocalization.bundle),
                isOn: $includeSubpaths
            )
            .toggleStyle(.checkbox)
            .font(toolMetrics.font())
        }
        inlineField(String(localized: "GraphQL Operation", bundle: RockxyLocalization.bundle)) {
            TextField(
                String(localized: "Any operation", bundle: RockxyLocalization.bundle),
                text: $graphQLOperationName
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: max(220, toolMetrics.fieldWidth(220)))
            .accessibilityLabel(String(
                localized: "GraphQL operation name to match",
                bundle: RockxyLocalization.bundle
            ))
            .help(String(
                localized: "Block only GraphQL requests with this exact operation name. Leave empty to block every request to the URL.",
                bundle: RockxyLocalization.bundle
            ))
        }
        applicationField
    }

    private var applicationField: some View {
        inlineField(String(localized: "Client Application", bundle: RockxyLocalization.bundle)) {
            TextField(
                String(localized: "Any application", bundle: RockxyLocalization.bundle),
                text: $clientApplication
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: max(220, toolMetrics.fieldWidth(220)))
            .accessibilityLabel(String(
                localized: "Client application name to match",
                bundle: RockxyLocalization.bundle
            ))
            .help(String(
                localized: "Block only requests made by this app, by name or bundle identifier. Applies to apps on this Mac; leave empty to block every client.",
                bundle: RockxyLocalization.bundle
            ))
        }
    }

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Decision", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.font(weight: .semibold))

            HStack(alignment: .center, spacing: toolMetrics.controlSpacing * 2) {
                inlineField(String(localized: "When matched", bundle: RockxyLocalization.bundle)) {
                    Menu {
                        ForEach(BlockActionType.allCases, id: \.self) { action in
                            Button {
                                blockAction = action
                            } label: {
                                menuCheckmarkLabel(action.rawValue, isSelected: blockAction == action)
                            }
                        }
                    } label: {
                        dataEntryMenuLabel(blockAction.rawValue, width: toolMetrics.menuWidth(220))
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Block action", bundle: RockxyLocalization.bundle))
                    .frame(width: toolMetrics.menuWidth(220))
                }

                Text(actionDescription)
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle(
                    String(localized: "Hide blocked requests", bundle: RockxyLocalization.bundle),
                    isOn: $hidesMatchedTraffic
                )
                .toggleStyle(.checkbox)
                .help(String(
                    localized: "Requests this rule blocks are not added to the traffic list.",
                    bundle: RockxyLocalization.bundle
                ))
            }
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private func inlineField(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .center, spacing: toolMetrics.controlSpacing) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func fieldGroup(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(toolMetrics.font())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .font(toolMetrics.font())
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
        }
    }

    private func dataEntryMenuLabel(_ title: String, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .frame(width: width, height: toolMetrics.formControlHeight, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }

    private func menuCheckmarkLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            if isSelected {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private func footerButtonLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                width: max(64, toolMetrics.footerButtonWidth - toolMetrics.controlSpacing * 3),
                height: max(16, toolMetrics.footerControlHeight - toolMetrics.controlSpacing)
            )
    }
}

extension ProxyRule {
    var blockActionType: BlockActionType {
        guard case let .block(statusCode) = action else {
            return .returnForbidden
        }
        return statusCode == 0 ? .dropConnection : .returnForbidden
    }
}
