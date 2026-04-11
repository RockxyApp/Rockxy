import SwiftUI

// MARK: - AddBreakpointRuleSheet

struct AddBreakpointRuleSheet: View {
    // MARK: Lifecycle

    init(
        editorContext: BreakpointEditorContext? = nil,
        editingRule: ProxyRule? = nil,
        onSave: @escaping (String, String, HTTPMethodFilter, RuleMatchType, Bool, Bool, Bool) -> Void
    ) {
        self.editorContext = editorContext
        self.editingRule = editingRule
        self.onSave = onSave

        if let rule = editingRule {
            let decoded = Self.decode(rule: rule)
            _ruleName = State(initialValue: rule.name)
            _urlPattern = State(initialValue: decoded.displayPattern)
            _httpMethod = State(initialValue: decoded.httpMethod)
            _matchType = State(initialValue: decoded.matchType)
            _breakpointRequest = State(initialValue: decoded.breakpointRequest)
            _breakpointResponse = State(initialValue: decoded.breakpointResponse)
            _includeSubpaths = State(initialValue: decoded.includeSubpaths)
        } else {
            _ruleName = State(initialValue: editorContext?.suggestedName ?? "")
            _urlPattern = State(initialValue: editorContext?.defaultPattern ?? "")
            _httpMethod = State(initialValue: editorContext?.httpMethod ?? .any)
            _matchType = State(initialValue: editorContext?.defaultMatchType ?? .wildcard)
            _breakpointRequest = State(initialValue: editorContext?.breakpointRequest ?? true)
            _breakpointResponse = State(initialValue: editorContext?.breakpointResponse ?? true)
            _includeSubpaths = State(initialValue: editorContext?.includeSubpaths ?? true)
        }
    }

    // MARK: Internal

    // MARK: - Decode

    struct Decoded {
        let displayPattern: String
        let matchType: RuleMatchType
        let includeSubpaths: Bool
        let httpMethod: HTTPMethodFilter
        let breakpointRequest: Bool
        let breakpointResponse: Bool
    }

    let editorContext: BreakpointEditorContext?
    let editingRule: ProxyRule?
    let onSave: (String, String, HTTPMethodFilter, RuleMatchType, Bool, Bool, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                provenanceBanner

                formRow(String(localized: "Name:")) {
                    TextField("", text: $ruleName, prompt: Text(String(localized: "Untitled")))
                        .textFieldStyle(.roundedBorder)
                }

                formRow(String(localized: "Matching Rule:")) {
                    TextField("", text: $urlPattern, prompt: Text("https://example.com"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                methodAndMatchRow

                conditionalFields

                formRow(String(localized: "Breakpoint:")) {
                    Toggle(String(localized: "Request"), isOn: $breakpointRequest)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                    Toggle(String(localized: "Response"), isOn: $breakpointResponse)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                    Text(String(localized: "Select at least one phase to intercept."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Done")) {
                    onSave(
                        ruleName,
                        urlPattern,
                        httpMethod,
                        matchType,
                        breakpointRequest,
                        breakpointResponse,
                        includeSubpaths
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlPattern.isEmpty || (!breakpointRequest && !breakpointResponse))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Reverse-engineers form state from a persisted `ProxyRule` so the sheet can edit it.
    /// Rules that were created via wildcard mode carry regex-escaped patterns; this tries
    /// to recover a friendly wildcard form. If the pattern cannot be decoded as wildcard,
    /// it falls back to regex mode with the raw pattern.
    static func decode(rule: ProxyRule) -> Decoded {
        let rawPattern = rule.matchCondition.urlPattern ?? ""
        let method = HTTPMethodFilter.allCases.first {
            $0.rawValue == rule.matchCondition.method
        } ?? .any

        let (phaseRequest, phaseResponse): (Bool, Bool) = {
            if case let .breakpoint(phase) = rule.action {
                switch phase {
                case .request: return (true, false)
                case .response: return (false, true)
                case .both: return (true, true)
                }
            }
            return (true, true)
        }()

        let (displayPattern, matchType, includeSubpaths) = decodePattern(rawPattern)

        return Decoded(
            displayPattern: displayPattern,
            matchType: matchType,
            includeSubpaths: includeSubpaths,
            httpMethod: method,
            breakpointRequest: phaseRequest,
            breakpointResponse: phaseResponse
        )
    }

    // MARK: Private

    private static let labelWidth: CGFloat = 110

    @Environment(\.dismiss) private var dismiss
    @State private var ruleName: String
    @State private var urlPattern: String
    @State private var httpMethod: HTTPMethodFilter
    @State private var matchType: RuleMatchType
    @State private var breakpointRequest: Bool
    @State private var breakpointResponse: Bool
    @State private var includeSubpaths: Bool

    @ViewBuilder private var provenanceBanner: some View {
        if let context = editorContext {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                    switch context.origin {
                    case .selectedTransaction:
                        if let method = context.sourceMethod {
                            Text(
                                String(
                                    localized: "Created from: \(method) \(context.sourceHost)\(context.sourcePath ?? "")"
                                )
                            )
                        } else {
                            Text(
                                String(
                                    localized: "Created from: \(context.sourceHost)\(context.sourcePath ?? "")"
                                )
                            )
                        }
                    case .domainQuickCreate:
                        Text(String(localized: "Created from domain: \(context.sourceHost)"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var methodAndMatchRow: some View {
        HStack(spacing: 8) {
            Spacer()
                .frame(width: Self.labelWidth + Theme.Layout.sectionSpacing)
            Picker("", selection: $httpMethod) {
                ForEach(HTTPMethodFilter.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: "HTTP Method"))
            .frame(width: 90)

            Picker("", selection: $matchType) {
                ForEach(RuleMatchType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Match Type"))
            .frame(width: 175)

            if matchType == .wildcard {
                Text(String(localized: "Support wildcard * and ?."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var conditionalFields: some View {
        if matchType == .wildcard {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: Self.labelWidth + Theme.Layout.sectionSpacing)
                Toggle(String(localized: "Include all subpaths of this URL"), isOn: $includeSubpaths)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
        }
    }

    private func formRow(
        _ label: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        HStack(alignment: .top, spacing: Theme.Layout.sectionSpacing) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: Self.labelWidth, alignment: .trailing)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
    }

    /// Attempts to recover a wildcard pattern from a regex-escaped pattern produced by
    /// `BreakpointRulesViewModel.compilePattern`. Returns the display pattern plus the
    /// match type and include-subpaths flag to reproduce the original form state.
    ///
    /// The encoding path converts wildcard `*` → `.*` and wildcard `?` → `.` after
    /// first regex-escaping the raw pattern, so an escaped literal dot `\.` is
    /// indistinguishable from a wildcard `.` once `\.` is naively unescaped.
    /// To preserve round-trip fidelity we stage each wildcard substitution into
    /// Unicode private-use-area placeholders before collapsing escapes, then
    /// restore the original user-facing wildcard characters at the end.
    private static func decodePattern(_ pattern: String) -> (String, RuleMatchType, Bool) {
        var working = pattern
        var includeSubpaths = true

        if working.hasSuffix(".*") {
            working = String(working.dropLast(2))
            includeSubpaths = true
        } else if working.hasSuffix("($|[?#])") {
            working = String(working.dropLast("($|[?#])".count))
            includeSubpaths = false
        }

        // Private-use-area placeholders — guaranteed not to collide with any
        // character a user would type in a URL pattern.
        let wildcardStarMarker = "\u{E000}"
        let literalDotMarker = "\u{E001}"
        let wildcardAnyMarker = "\u{E002}"

        // Order matters:
        //  1. `.*` must be staged first so its `.` isn't mistaken for a wildcard `?`.
        //  2. `\.` is then staged so the remaining bare `.` can only be the wildcard `?`.
        //  3. Bare `.` → wildcard `?` marker.
        //  4. Other backslash escapes (`\/`, `\-`, `\_`) are unescaped last.
        let staged = working
            .replacingOccurrences(of: ".*", with: wildcardStarMarker)
            .replacingOccurrences(of: "\\.", with: literalDotMarker)
            .replacingOccurrences(of: ".", with: wildcardAnyMarker)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\-", with: "-")
            .replacingOccurrences(of: "\\_", with: "_")

        // Heuristic: if any regex metacharacter remains after wildcard substitution,
        // this pattern wasn't produced by our wildcard encoder — fall back to regex mode.
        let regexMetaScalars = CharacterSet(charactersIn: "^$|()[]{}+?\\")
        if staged.unicodeScalars.contains(where: { regexMetaScalars.contains($0) }) {
            return (pattern, .regex, true)
        }

        let decoded = staged
            .replacingOccurrences(of: wildcardStarMarker, with: "*")
            .replacingOccurrences(of: literalDotMarker, with: ".")
            .replacingOccurrences(of: wildcardAnyMarker, with: "?")

        return (decoded, .wildcard, includeSubpaths)
    }
}
