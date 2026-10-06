import SwiftUI

// MARK: - RuleURLTestResult

enum RuleURLTestResult: Equatable {
    case matched
    case notMatched
    case invalidURL
    case invalidPattern(String)
}

// MARK: - RuleURLTester

/// Checks a sample request against a rule's URL pattern and method exactly as the rule engine
/// does. A GraphQL operation filter is not part of the check; the editor shows it separately.
enum RuleURLTester {
    static func evaluate(condition: RuleMatchCondition, method: String, urlText: String) -> RuleURLTestResult {
        let candidate = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else
        {
            return .invalidURL
        }
        guard let pattern = condition.runtimeURLPattern ?? condition.urlPattern else {
            return .invalidPattern(String(localized: "Enter a URL pattern first.", bundle: RockxyLocalization.bundle))
        }
        switch RegexValidator.compile(pattern) {
        case let .failure(error):
            return .invalidPattern(error.localizedDescription)
        case let .success(regex):
            return condition.matches(
                method: method,
                url: url,
                headers: [],
                compiledPattern: regex,
                graphQLOperationName: condition.graphQLOperationName
            ) ? .matched : .notMatched
        }
    }
}

// MARK: - RuleURLTesterSection

/// "Test this rule" box for rule editors: a method, a sample URL, and whether the rule applies.
struct RuleURLTesterSection: View {
    // MARK: Internal

    let toolMetrics: ToolWindowDisplayMetrics
    /// Builds the condition from the editor's current fields.
    let condition: () -> RuleMatchCondition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Test this rule", bundle: RockxyLocalization.bundle))
                .font(toolMetrics.secondaryFont(weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: toolMetrics.controlSpacing) {
                Picker(String(localized: "Test method", bundle: RockxyLocalization.bundle), selection: $method) {
                    ForEach(HTTPMethodFilter.allCases.filter { $0 != .any }) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: toolMetrics.menuWidth(94))

                TextField("https://example.com/api/users", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font(monospaced: true))
                    .accessibilityLabel(String(localized: "Test request URL", bundle: RockxyLocalization.bundle))
                    .onSubmit(runTest)

                Button(String(localized: "Test", bundle: RockxyLocalization.bundle), action: runTest)
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let result {
                resultLabel(result)
            }
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: Private

    @State private var method: HTTPMethodFilter = .get
    @State private var urlText = ""
    @State private var result: RuleURLTestResult?

    private func runTest() {
        result = RuleURLTester.evaluate(condition: condition(), method: method.rawValue, urlText: urlText)
    }

    @ViewBuilder
    private func resultLabel(_ result: RuleURLTestResult) -> some View {
        switch result {
        case .matched:
            Label(
                String(localized: "Matched — this rule applies to the request.", bundle: RockxyLocalization.bundle),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .notMatched:
            Label(
                String(localized: "Not matched — this rule skips the request.", bundle: RockxyLocalization.bundle),
                systemImage: "xmark.circle.fill"
            )
            .foregroundStyle(.secondary)
        case .invalidURL:
            Label(
                String(localized: "Enter a complete HTTP or HTTPS URL.", bundle: RockxyLocalization.bundle),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
        case let .invalidPattern(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
