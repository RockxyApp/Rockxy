import SwiftUI

/// Parses and displays URL query parameters from the request URL in a name/value grid.
struct QueryInspectorView: View {
    let transaction: HTTPTransaction

    var body: some View {
        let components = URLComponents(url: transaction.request.url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        Group {
            if queryItems.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Query Parameters"),
                    systemImage: "questionmark.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 100, maximum: 200), alignment: .topLeading),
                        GridItem(.flexible(), alignment: .topLeading),
                    ], spacing: 4) {
                        Text(String(localized: "Name"))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Value"))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        ForEach(Array(queryItems.enumerated()), id: \.offset) { _, item in
                            Text(item.name)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                            Text(item.value ?? "")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
