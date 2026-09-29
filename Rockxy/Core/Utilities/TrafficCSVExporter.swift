import Foundation

// Writes a spreadsheet-friendly summary of captured transactions.

// MARK: - TrafficCSVExporter

/// One row per transaction with the columns people sort and chart in a
/// spreadsheet. Headers and bodies are deliberately left out; the file still
/// carries full URLs (including query strings), client apps, and notes.
///
/// Cells follow RFC 4180 quoting, and any cell that a spreadsheet would treat
/// as a formula (leading `=`, `+`, `-`, `@`, tab, or carriage return) is
/// prefixed with an apostrophe so opening the file never executes captured text.
enum TrafficCSVExporter {
    static let columns = [
        "#", "Start Time", "Method", "URL", "Host", "Path", "Status", "Duration (ms)",
        "Request Bytes", "Response Bytes", "Response Content Type", "Client", "Note",
    ]

    static func export(transactions: [HTTPTransaction]) -> Data {
        var lines = [columns.map(escape).joined(separator: ",")]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (index, transaction) in transactions.enumerated() {
            let response = transaction.response
            let durationMilliseconds = transaction.displayDuration.map { String(Int(($0 * 1_000).rounded())) } ?? ""
            let row = [
                String(index + 1),
                formatter.string(from: transaction.timestamp),
                transaction.request.method,
                transaction.request.url.absoluteString,
                transaction.request.host,
                transaction.request.path,
                response.map { String($0.statusCode) } ?? "",
                durationMilliseconds,
                String(transaction.request.body?.count ?? 0),
                response.map { String($0.body?.count ?? 0) } ?? "",
                response?.headers.first {
                    $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame
                }?.value ?? "",
                transaction.clientApp ?? "",
                transaction.comment ?? "",
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func escape(_ value: String) -> String {
        var cell = value
        if let first = cell.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) {
            cell = "'" + cell
        }
        if cell.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            cell = "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return cell
    }
}
