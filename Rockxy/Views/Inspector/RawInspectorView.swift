import SwiftUI

/// Displays the full HTTP transaction as raw text, reconstructing the wire format
/// with request line, headers, body, and (if available) the response in the same format.
struct RawInspectorView: View {
    // MARK: Internal

    let transaction: HTTPTransaction
    var highlightContext: InspectorHighlightContext = .empty

    var body: some View {
        let snapshot = InspectorTransactionSnapshot(transaction: transaction)
        AsyncInspectorTextEditor(
            renderID: "\(snapshot.id.uuidString)-full-raw-\(snapshot.response?.body?.count ?? 0)",
            fontSize: 12,
            highlightContext: highlightContext
        ) {
            var text = InspectorPayloadFormatter.rawRequest(snapshot.request)
            if let rawResponse = InspectorPayloadFormatter.rawResponse(snapshot.response) {
                text += "\r\n\r\n--- Response ---\r\n"
                text += rawResponse
            }
            return .text(text)
        }
    }
}
