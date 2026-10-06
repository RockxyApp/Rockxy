import Foundation

// MARK: - CharlesJSONSessionImporter

/// Reads a Charles JSON session (`.chlsj`): a top-level array with one object per request,
/// carrying the request and response header blocks and bodies, timings in milliseconds, the
/// remote address, and TLS details. Binary `.chls` sessions are not readable outside Charles.
enum CharlesJSONSessionImporter {
    // MARK: Internal

    /// A JSON array whose objects look like Charles entries (`scheme`, `host`, `request`).
    static func looksLikeSession(_ root: Any) -> Bool {
        guard let entries = root as? [[String: Any]] else {
            return false
        }
        return entries.isEmpty || entries.contains { $0["host"] is String && $0["request"] is [String: Any] }
    }

    static func importEntries(_ root: Any) throws -> [HTTPTransaction] {
        guard let entries = root as? [[String: Any]], looksLikeSession(root) else {
            throw HARImportError.invalidFormat("Not a Charles JSON session")
        }
        return entries.enumerated().compactMap { index, entry in transaction(from: entry, index: index) }
    }

    // MARK: Private

    private static let timestampFormatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return [fractional, whole]
    }()

    private static func transaction(from entry: [String: Any], index: Int) -> HTTPTransaction? {
        guard let host = entry["host"] as? String, !host.isEmpty else {
            return nil
        }
        let method = (entry["method"] as? String)?.uppercased() ?? "GET"
        let scheme = ((entry["scheme"] as? String) ?? "http").lowercased()
        let port = (entry["actualPort"] as? Int) ?? (entry["port"] as? Int)
        let isTunnel = (entry["tunnel"] as? Bool) == true || method == "CONNECT"

        var components = URLComponents()
        components.scheme = isTunnel ? "https" : scheme
        components.host = host
        let defaultPort = scheme == "https" ? 443 : 80
        if let port, port != defaultPort || isTunnel {
            components.port = port
        }
        if !isTunnel {
            components.percentEncodedPath = (entry["path"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "/"
            if let query = entry["query"] as? String, !query.isEmpty {
                components.percentEncodedQuery = query
            }
        }
        guard let url = components.url else {
            return nil
        }

        let requestObject = entry["request"] as? [String: Any]
        let requestHeaders = headers(in: requestObject)
        let requestBody = body(in: requestObject)
        let request = HTTPRequestData(
            method: method,
            url: url,
            httpVersion: (entry["protocolVersion"] as? String) ?? "HTTP/1.1",
            headers: requestHeaders,
            body: requestBody,
            contentType: ContentTypeDetector.detect(headers: requestHeaders, body: requestBody)
        )

        let status = (entry["status"] as? String)?.uppercased()
        let responseObject = entry["response"] as? [String: Any]
        let response = responseObject.flatMap { object -> HTTPResponseData? in
            guard let code = object["status"] as? Int else {
                return nil
            }
            let responseHeaders = headers(in: object)
            let responseBody = body(in: object)
            return HTTPResponseData(
                statusCode: code,
                statusMessage: reasonPhrase(in: object) ?? HTTPReasonPhrase.standard(for: code),
                headers: responseHeaders,
                body: responseBody,
                contentType: ContentTypeDetector.detect(headers: responseHeaders, body: responseBody)
            )
        }

        let times = entry["times"] as? [String: Any]
        let timestamp = (times?["start"] as? String).flatMap(parseDate) ?? Date()
        let transaction = HTTPTransaction(
            timestamp: timestamp,
            request: request,
            response: response,
            state: status == "COMPLETE" || (status == nil && response != nil) ? .completed : .failed,
            timingInfo: timing(from: entry["durations"] as? [String: Any])
        )
        transaction.clientApp = UpstreamResponseHandler.extractAppFromUserAgent(request.headers)
        if let total = (entry["durations"] as? [String: Any])?["total"] as? Double {
            transaction.measuredDuration = total / 1_000
        }
        transaction.connectionLog = connectionLog(from: entry, host: host, port: port ?? defaultPort)
        if isTunnel {
            transaction.sslCapture = .tunneled
        }
        return transaction
    }

    private static func headers(in object: [String: Any]?) -> [HTTPHeader] {
        let header = object?["header"] as? [String: Any]
        let list = header?["headers"] as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let name = item["name"] as? String else {
                return nil
            }
            return HTTPHeader(name: name, value: (item["value"] as? String) ?? "")
        }
    }

    /// Text bodies are stored decoded; binary ones base64 under `encoded`.
    private static func body(in object: [String: Any]?) -> Data? {
        guard let body = object?["body"] as? [String: Any] else {
            return nil
        }
        if let encoded = body["encoded"] as? String {
            return Data(base64Encoded: encoded)
        }
        if let text = body["text"] as? String {
            return Data(text.utf8)
        }
        return nil
    }

    /// "HTTP/1.1 404 Not Found" → "Not Found".
    private static func reasonPhrase(in object: [String: Any]) -> String? {
        guard let firstLine = (object["header"] as? [String: Any])?["firstLine"] as? String else {
            return nil
        }
        let parts = firstLine.split(separator: " ", maxSplits: 2)
        return parts.count == 3 ? String(parts[2]) : nil
    }

    private static func timing(from durations: [String: Any]?) -> TimingInfo? {
        guard let durations else {
            return nil
        }
        func seconds(_ key: String) -> TimeInterval {
            max(0, (durations[key] as? Double) ?? 0) / 1_000
        }
        return TimingInfo(
            dnsLookup: seconds("dns"),
            tcpConnection: seconds("connect"),
            tlsHandshake: seconds("ssl"),
            timeToFirstByte: seconds("latency"),
            contentTransfer: seconds("response")
        )
    }

    /// `remoteAddress` is "name/ip"; TLS and ALPN come from `ssl` and `alpn`.
    private static func connectionLog(from entry: [String: Any], host: String, port: Int) -> ConnectionLog? {
        guard let remote = entry["remoteAddress"] as? String, !remote.isEmpty else {
            return nil
        }
        var log = ConnectionLog(host: host, port: port)
        log.remoteAddress = remote.split(separator: "/").last.map(String.init)
        log.remotePort = (entry["actualPort"] as? Int) ?? port
        if let ssl = entry["ssl"] as? [String: Any] {
            var tls = ConnectionLog.TLS()
            tls.version = ssl["protocol"] as? String
            tls.negotiatedProtocol = (entry["alpn"] as? [String: Any])?["protocol"] as? String
            log.tls = tls
        }
        if (entry["status"] as? String)?.uppercased() == "FAILED" {
            let message = (entry["errorMessage"] as? String) ?? "The request failed"
            log.failure = ConnectionLog.Failure(stage: .response, message: message)
        }
        return log
    }

    private static func parseDate(_ text: String) -> Date? {
        for formatter in timestampFormatters {
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
