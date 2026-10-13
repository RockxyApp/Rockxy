import SwiftUI

/// Displays parsed GraphQL operation details when a transaction is detected as GraphQL.
/// Shows the operation name, type (query/mutation/subscription), query string, variables, and
/// any errors the server reported in the response body.
struct GraphQLInspectorView: View {
    let transaction: HTTPTransaction

    var body: some View {
        if let info = transaction.graphQLInfo {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Operation") {
                        if let name = info.operationName {
                            Text(name)
                                .font(.system(size: metrics.primaryFontSize, design: .monospaced))
                        } else {
                            Text(String(localized: "Anonymous", bundle: RockxyLocalization.bundle))
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Type") {
                        Text(info.operationType.rawValue.capitalized)
                    }

                    Text(String(localized: "Query", bundle: RockxyLocalization.bundle))
                        .fontWeight(.semibold)
                    Text(info.query)
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.quaternary)
                        .cornerRadius(4)

                    if let variables = info.variables {
                        Text(String(localized: "Variables", bundle: RockxyLocalization.bundle))
                            .fontWeight(.semibold)
                        Text(variables)
                            .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(4)
                    }

                    if let errorSummary {
                        GraphQLResponseErrorsSection(summary: errorSummary)
                    }
                }
                .padding()
            }
            .task(id: responseKey) {
                errorSummary = nil
                let response = transaction.response
                // Decompression and parsing stay off the main actor.
                let summary = await Task.detached(priority: .userInitiated) {
                    GraphQLResponseErrorSummary.parse(
                        response?.decodedBody(limit: GraphQLResponseErrorSummary.maxPayloadBytes)
                    )
                }.value
                guard !Task.isCancelled else {
                    return
                }
                errorSummary = summary
            }
        } else {
            InspectorEmptyStateView(
                "No GraphQL Data",
                systemImage: "circle.hexagongrid",
                description: "This request is not a GraphQL operation"
            )
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics
    @State private var errorSummary: GraphQLResponseErrorSummary?

    /// Re-parse when the selection changes or the response arrives or grows.
    private var responseKey: String {
        "\(transaction.id.uuidString)-\(transaction.response?.statusCode ?? 0)-\(transaction.response?.body?.count ?? 0)"
    }
}

// MARK: - GraphQLResponseErrorsSection

/// Lists the `errors` a GraphQL server returned, which usually arrive with HTTP 200.
private struct GraphQLResponseErrorsSection: View {
    let summary: GraphQLResponseErrorSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)

            if summary.hasPartialData {
                Text(String(
                    localized: "The response also returned data, so the operation partly succeeded.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            ForEach(Array(summary.errors.enumerated()), id: \.offset) { _, error in
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.message.isEmpty
                        ? String(localized: "No message", bundle: RockxyLocalization.bundle)
                        : error.message)
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                    if let detail = detail(for: error) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary)
                .cornerRadius(4)
                .accessibilityElement(children: .combine)
            }

            if summary.totalCount > summary.errors.count {
                Text(String(
                    localized: "Showing the first \(summary.errors.count) of \(summary.totalCount) errors.",
                    bundle: RockxyLocalization.bundle
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var title: String {
        String(
            AttributedString(
                localized: "^[\(summary.totalCount) Response Error](inflect: true)",
                bundle: RockxyLocalization.bundle
            ).characters
        )
    }

    private func detail(for error: GraphQLResponseError) -> String? {
        switch (error.code, error.path) {
        case let (code?, path?):
            String(localized: "\(code) at \(path)", bundle: RockxyLocalization.bundle)
        case let (code?, nil):
            code
        case let (nil, path?):
            String(localized: "At \(path)", bundle: RockxyLocalization.bundle)
        case (nil, nil):
            nil
        }
    }
}
