import SwiftUI

/// Displays parsed GraphQL operation details when a transaction is detected as GraphQL.
/// Shows the operation name, type (query/mutation/subscription), query string, and variables.
struct GraphQLInspectorView: View {
    let transaction: HTTPTransaction

    var body: some View {
        if let info = transaction.graphQLInfo {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let name = info.operationName {
                        LabeledContent("Operation") {
                            Text(name)
                                .font(.system(size: metrics.primaryFontSize, design: .monospaced))
                        }
                    }

                    LabeledContent("Type") {
                        Text(info.operationType.rawValue.capitalized)
                    }

                    Text("Query")
                        .fontWeight(.semibold)
                    Text(info.query)
                        .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.quaternary)
                        .cornerRadius(4)

                    if let variables = info.variables {
                        Text("Variables")
                            .fontWeight(.semibold)
                        Text(variables)
                            .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(4)
                    }
                }
                .padding()
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
}
