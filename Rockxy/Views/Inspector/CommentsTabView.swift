import SwiftUI

/// Editable comments tab for annotating individual HTTP transactions.
struct CommentsTabView: View {
    // MARK: Internal

    let transaction: HTTPTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $commentText)
                .font(.system(size: metrics.primaryFontSize))
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .onAppear {
            commentText = transaction.comment ?? ""
        }
        .onChange(of: commentText) { _, newValue in
            transaction.comment = newValue.isEmpty ? nil : newValue
        }
    }

    // MARK: Private

    @State private var commentText: String = ""
    @Environment(\.appUIDisplayMetrics) private var metrics
}
