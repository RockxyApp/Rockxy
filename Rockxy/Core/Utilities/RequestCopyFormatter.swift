import Foundation

// Formats captured requests for copy actions such as URLs, cURL commands, and table
// values.

enum RequestCopyFormatter {
    // MARK: Internal

    // MARK: - URL

    static func url(for transaction: HTTPTransaction) -> String {
        transaction.request.url.absoluteString
    }

    // MARK: - cURL

    static func curl(for transaction: HTTPTransaction) -> String {
        let request = transaction.request
        var parts = ["curl"]
        parts.append(shellQuote(request.url.absoluteString))
        parts.append("-X \(request.method)")
        for header in request.headers {
            parts.append("-H \(shellQuote("\(header.name): \(header.value)"))")
        }
        if let body = request.body {
            if let bodyString = String(data: body, encoding: .utf8) {
                parts.append("-d \(shellQuote(bodyString))")
            } else {
                parts.append("--data-binary @- # <binary data, \(SizeFormatter.format(bytes: body.count))>")
            }
        }
        return parts.joined(separator: " \\\n  ")
    }

    // MARK: - Cell Value

    static func cellValue(for transaction: HTTPTransaction, column: String) -> String {
        switch column {
        case "url":
            return transaction.request.host + transaction.request.path
        case "client":
            return transaction.clientApp ?? ""
        case "method":
            return transaction.request.method
        case "code":
            return transaction.response.map { "\($0.statusCode)" } ?? ""
        case "duration":
            return transaction.timingInfo.map { DurationFormatter.format(seconds: $0.totalDuration) } ?? ""
        case "size":
            return transaction.response?.body.map { SizeFormatter.format(bytes: $0.count) } ?? ""
        case "queryName":
            return web3RPCMethodDescription(transaction.web3RPCInfo) ?? transaction.graphQLInfo?.operationName ?? ""
        default:
            if column.hasPrefix("reqHeader.") || column.hasPrefix("resHeader.") {
                return HeaderColumnStore.resolveValue(for: column, transaction: transaction)
            }
            return transaction.request.url.absoluteString
        }
    }

    // MARK: - Headers

    static func requestHeaders(for transaction: HTTPTransaction) -> String {
        transaction.request.headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")
    }

    static func responseHeaders(for transaction: HTTPTransaction) -> String? {
        guard let response = transaction.response else {
            return nil
        }
        return response.headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")
    }

    // MARK: - Body

    static func requestBody(for transaction: HTTPTransaction) -> String? {
        guard let body = transaction.request.body else {
            return nil
        }
        if let text = String(data: body, encoding: .utf8) {
            return text
        }
        return "<binary data, \(SizeFormatter.format(bytes: body.count))>"
    }

    static func responseBody(for transaction: HTTPTransaction) -> String? {
        guard let body = transaction.response?.body else {
            return nil
        }
        if let text = String(data: body, encoding: .utf8) {
            return text
        }
        return "<binary data, \(SizeFormatter.format(bytes: body.count))>"
    }

    // MARK: - Cookies

    static func requestCookies(for transaction: HTTPTransaction) -> String {
        let cookies = transaction.request.cookies
        guard !cookies.isEmpty else {
            return ""
        }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    static func responseCookies(for transaction: HTTPTransaction) -> String {
        let setCookieHeaders = transaction.response?.headers
            .filter { $0.name.lowercased() == "set-cookie" } ?? []
        guard !setCookieHeaders.isEmpty else {
            return ""
        }
        return setCookieHeaders.map(\.value).joined(separator: "\n")
    }

    // MARK: - Raw Formats

    static func rawRequest(for transaction: HTTPTransaction) -> String {
        let request = transaction.request
        var raw = "\(request.method) \(request.path) \(request.httpVersion)\r\n"
        raw += "Host: \(request.host)\r\n"
        for header in request.headers {
            raw += "\(header.name): \(header.value)\r\n"
        }
        raw += "\r\n"
        if let body = request.body, let bodyString = String(data: body, encoding: .utf8) {
            raw += bodyString
        }
        return raw
    }

    static func rawResponse(for transaction: HTTPTransaction) -> String? {
        guard let response = transaction.response else {
            return nil
        }
        var raw = "HTTP/1.1 \(response.statusCode) \(response.statusMessage)\r\n"
        for header in response.headers {
            raw += "\(header.name): \(header.value)\r\n"
        }
        raw += "\r\n"
        if let body = response.body, let bodyString = String(data: body, encoding: .utf8) {
            raw += bodyString
        }
        return raw
    }

    // MARK: - JSON

    static func json(for transaction: HTTPTransaction) -> String? {
        var dict: [String: Any] = [
            "url": transaction.request.url.absoluteString,
            "method": transaction.request.method,
            "headers": transaction.request.headers.map { ["name": $0.name, "value": $0.value] },
            "timestamp": ISO8601DateFormatter().string(from: transaction.timestamp),
        ]
        if let body = transaction.request.body, let bodyString = String(data: body, encoding: .utf8) {
            dict["body"] = bodyString
        }
        if let response = transaction.response {
            var respDict: [String: Any] = [
                "statusCode": response.statusCode,
                "headers": response.headers.map { ["name": $0.name, "value": $0.value] },
            ]
            if let body = response.body, let bodyString = String(data: body, encoding: .utf8) {
                respDict["body"] = bodyString
            }
            dict["response"] = respDict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - HAR Entry

    static func harEntry(for transaction: HTTPTransaction) -> String? {
        let exporter = HARExporter()
        guard let data = try? exporter.export(transactions: [transaction]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Private

    // MARK: - Shell Quoting

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func web3RPCMethodDescription(_ info: Web3RPCInfo?) -> String? {
        guard let info else {
            return nil
        }
        if let method = info.method {
            return method
        }
        guard let batch = info.batch else {
            return nil
        }
        if let first = batch.methods.first {
            return batch.methods.count > 1 ? "\(first) + \(batch.methods.count - 1)" : first
        }
        return "\(batch.web3RequestCount) calls"
    }
}
