import Foundation

// MARK: - PostmanCollectionExporter

/// Writes captured requests as a Postman Collection (format v2.1) so they can be imported
/// into Postman and compatible API clients. Each request becomes an item, grouped in one
/// folder per host, and its captured response is attached as a saved example.
enum PostmanCollectionExporter {
    // MARK: Internal

    static let schemaURL = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"

    /// Tunnels and WebSocket upgrades are not requests an API client can resend.
    static func isEligible(_ transaction: HTTPTransaction) -> Bool {
        let method = transaction.request.method.uppercased()
        guard method != "CONNECT", transaction.webSocketConnection == nil else {
            return false
        }
        let scheme = transaction.request.url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    static func export(
        transactions: [HTTPTransaction],
        name: String = "Rockxy Export",
        collectionID: UUID = UUID()
    )
        throws -> Data
    {
        var folders: [(host: String, items: [[String: Any]])] = []
        for transaction in transactions where isEligible(transaction) {
            let host = transaction.request.url.host() ?? "requests"
            let item = self.item(for: transaction)
            if let index = folders.firstIndex(where: { $0.host == host }) {
                folders[index].items.append(item)
            } else {
                folders.append((host, [item]))
            }
        }
        let collection: [String: Any] = [
            "info": [
                "_postman_id": collectionID.uuidString.lowercased(),
                "name": name,
                "schema": schemaURL,
            ],
            "item": folders.map { ["name": $0.host, "item": $0.items] },
        ]
        return try JSONSerialization.data(withJSONObject: collection, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: Private

    /// Headers the client library sets from the URL and body; copying them breaks edited
    /// requests, and `Proxy-*` only meant something between the client and Rockxy.
    private static let transportHeaders: Set<String> = [
        "content-length", "host", "connection", "proxy-connection", "proxy-authorization", "transfer-encoding",
    ]

    private static func item(for transaction: HTTPTransaction) -> [String: Any] {
        let request = transaction.request
        var item: [String: Any] = [
            "name": "\(request.method) \(request.url.path(percentEncoded: false).isEmpty ? "/" : request.url.path(percentEncoded: false))",
            "request": requestObject(request),
        ]
        if let response = transaction.response, transaction.state != .failed {
            var example: [String: Any] = [
                "name": "\(response.statusCode) \(response.statusMessage)",
                "originalRequest": requestObject(request),
                "code": response.statusCode,
                "status": response.statusMessage,
                "header": response.headers.map { ["key": $0.name, "value": $0.value] },
            ]
            if let body = response.body, let text = String(data: body, encoding: .utf8) {
                example["body"] = text
                if let language = language(for: response.headers) {
                    example["_postman_previewlanguage"] = language
                }
            }
            item["response"] = [example]
        } else {
            item["response"] = [[String: Any]]()
        }
        return item
    }

    private static func requestObject(_ request: HTTPRequestData) -> [String: Any] {
        var object: [String: Any] = [
            "method": request.method.uppercased(),
            "header": request.headers
                .filter { !transportHeaders.contains($0.name.lowercased()) }
                .map { ["key": $0.name, "value": $0.value] },
            "url": urlObject(request.url),
        ]
        if let body = request.body, !body.isEmpty {
            if let text = String(data: body, encoding: .utf8) {
                var bodyObject: [String: Any] = ["mode": "raw", "raw": text]
                if let language = language(for: request.headers) {
                    bodyObject["options"] = ["raw": ["language": language]]
                }
                object["body"] = bodyObject
            } else {
                // Postman's raw mode holds text only; say so instead of writing corrupt bytes.
                object["description"] = "The captured request body is binary (\(body.count) bytes) and was not included."
            }
        }
        return object
    }

    private static func urlObject(_ url: URL) -> [String: Any] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var object: [String: Any] = [
            "raw": url.absoluteString,
            "protocol": url.scheme ?? "https",
            "host": (url.host() ?? "").split(separator: ".").map(String.init),
            "path": url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init),
        ]
        if let port = url.port {
            object["port"] = String(port)
        }
        if let items = components?.queryItems, !items.isEmpty {
            object["query"] = items.map { ["key": $0.name, "value": $0.value ?? NSNull()] as [String: Any] }
        }
        return object
    }

    private static func language(for headers: [HTTPHeader]) -> String? {
        guard let type = headers.first(where: { $0.name.lowercased() == "content-type" })?.value.lowercased() else {
            return nil
        }
        if type.contains("json") {
            return "json"
        }
        if type.contains("xml") {
            return "xml"
        }
        if type.contains("html") {
            return "html"
        }
        if type.contains("javascript") {
            return "javascript"
        }
        return "text"
    }
}
