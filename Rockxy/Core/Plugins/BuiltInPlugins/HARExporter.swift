import Foundation
import os

// Exports captured HTTP transactions to the HTTP Archive (HAR) 1.2 format.
// HAR is the standard interchange format supported by Chrome DevTools,
// Firefox, and other proxy tools — enabling cross-tool session sharing.

// MARK: - HARExporter

struct HARExporter: ExporterPlugin {
    // MARK: Internal

    let name = "HAR Exporter"
    let fileExtension = "har"

    func export(transactions: [HTTPTransaction]) throws -> Data {
        let log = HARLog(transactions: transactions)
        let root: [String: Any] = ["log": log.toDictionary()]

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        Self.logger.info("Exported \(transactions.count) transactions to HAR")
        return data
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HARExporter"
    )
}

// MARK: - HARLog

private struct HARLog {
    // MARK: Lifecycle

    init(transactions: [HTTPTransaction]) {
        self.entries = transactions.map { HAREntry(transaction: $0) }
    }

    // MARK: Internal

    let version = "1.2"
    let creator = HARCreator()
    let entries: [HAREntry]

    func toDictionary() -> [String: Any] {
        [
            "version": version,
            "creator": creator.toDictionary(),
            "entries": entries.map { $0.toDictionary() }
        ]
    }
}

// MARK: - HARCreator

private struct HARCreator {
    let name = "Rockxy"
    let version = "1.0"

    func toDictionary() -> [String: Any] {
        ["name": name, "version": version]
    }
}

// MARK: - HAREntry

private struct HAREntry {
    // MARK: Internal

    let transaction: HTTPTransaction

    func toDictionary() -> [String: Any] {
        let startedDateTime = ISO8601DateFormatter.harFormatter.string(
            from: transaction.timestamp
        )
        let timeMs = (transaction.timingInfo?.totalDuration ?? 0) * 1000.0

        var dict: [String: Any] = [
            "startedDateTime": startedDateTime,
            "time": timeMs,
            "request": requestDictionary(),
            "response": responseDictionary(),
            "cache": [String: Any](),
            "timings": timingsDictionary()
        ]

        let host = transaction.request.host
        if !host.isEmpty {
            dict["pageref"] = host
        }

        return dict
    }

    // MARK: Private

    private func requestDictionary() -> [String: Any] {
        let req = transaction.request
        let queryItems = URLComponents(url: req.url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        // +4 accounts for ": " separator and "\r\n" line ending per header
        let headersSize = req.headers.reduce(0) { $0 + $1.name.count + $1.value.count + 4 }

        return [
            "method": req.method,
            "url": req.url.absoluteString,
            "httpVersion": req.httpVersion,
            "cookies": req.cookies.map { ["name": $0.name, "value": $0.value] },
            "headers": req.headers.map { headerToDict($0) },
            "queryString": queryItems.map { ["name": $0.name, "value": $0.value ?? ""] },
            "headersSize": headersSize,
            "bodySize": req.body?.count ?? 0,
            "postData": postDataDictionary(body: req.body, contentType: req.contentType)
        ]
    }

    private func responseDictionary() -> [String: Any] {
        guard let resp = transaction.response else {
            return [
                "status": 0,
                "statusText": "",
                "httpVersion": "HTTP/1.1",
                "cookies": [[String: Any]](),
                "headers": [[String: Any]](),
                "content": contentDictionary(body: nil, contentType: nil),
                "redirectURL": "",
                "headersSize": -1,
                "bodySize": -1
            ]
        }

        let headersSize = resp.headers.reduce(0) { $0 + $1.name.count + $1.value.count + 4 }

        return [
            "status": resp.statusCode,
            "statusText": resp.statusMessage,
            "httpVersion": "HTTP/1.1",
            "cookies": resp.setCookies.map { ["name": $0.name, "value": $0.value] },
            "headers": resp.headers.map { headerToDict($0) },
            "content": contentDictionary(body: resp.body, contentType: resp.contentType),
            "redirectURL": redirectURL(from: resp),
            "headersSize": headersSize,
            "bodySize": resp.body?.count ?? -1
        ]
    }

    private func timingsDictionary() -> [String: Any] {
        guard let timing = transaction.timingInfo else {
            return [
                "dns": -1,
                "connect": -1,
                "ssl": -1,
                "send": 0,
                "wait": 0,
                "receive": 0
            ]
        }

        return [
            "dns": timing.dnsLookup * 1000.0,
            "connect": timing.tcpConnection * 1000.0,
            "ssl": timing.tlsHandshake * 1000.0,
            "send": 0,
            "wait": timing.timeToFirstByte * 1000.0,
            "receive": timing.contentTransfer * 1000.0
        ]
    }

    /// HAR spec requires binary content to be base64-encoded with an `encoding` field,
    /// while text content is stored as plain UTF-8 strings.
    private func contentDictionary(body: Data?, contentType: ContentType?) -> [String: Any] {
        let mimeType = contentType?.rawValue ?? "application/octet-stream"
        let size = body?.count ?? 0
        let isText = contentType.map { [.json, .xml, .html, .text, .form].contains($0) } ?? false

        var dict: [String: Any] = [
            "size": size,
            "mimeType": mimeType
        ]

        if let body, isText {
            dict["text"] = String(data: body, encoding: .utf8) ?? ""
        } else if let body {
            dict["text"] = body.base64EncodedString()
            dict["encoding"] = "base64"
        }

        return dict
    }

    private func postDataDictionary(body: Data?, contentType: ContentType?) -> [String: Any] {
        let mimeType = contentType?.rawValue ?? ""
        guard let body else {
            return ["mimeType": mimeType, "text": ""]
        }
        let text = String(data: body, encoding: .utf8) ?? body.base64EncodedString()
        return ["mimeType": mimeType, "text": text]
    }

    private func headerToDict(_ header: HTTPHeader) -> [String: String] {
        ["name": header.name, "value": header.value]
    }

    private func redirectURL(from response: HTTPResponseData) -> String {
        response.headers.first { $0.name.lowercased() == "location" }?.value ?? ""
    }
}

// MARK: - ISO8601 Formatter

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let harFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
