import Foundation
import os

// Implements har importer behavior for the plugin and scripting subsystem.

// MARK: - HARImportError

enum HARImportError: LocalizedError {
    case invalidFormat(String)
    case unsupportedVersion(String)
    case malformedEntry(index: Int, reason: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidFormat(detail):
            String(localized: "Invalid HAR format: \(detail)", bundle: RockxyLocalization.bundle)
        case let .unsupportedVersion(version):
            String(localized: "Unsupported HAR version: \(version) (expected 1.x)", bundle: RockxyLocalization.bundle)
        case let .malformedEntry(index, reason):
            String(
                localized: "Malformed HAR entry at index \(index): \(reason)",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}

// MARK: - HARImporter

struct HARImporter {
    // MARK: Internal

    func importData(_ data: Data) throws -> [HTTPTransaction] {
        try importReportingSkips(data).transactions
    }

    /// Imports every entry it can. An entry that cannot be read (a `blob:` URL, a missing
    /// method) is skipped and counted instead of losing the whole file; the import only
    /// fails when no entry at all could be read.
    func importReportingSkips(_ data: Data) throws -> (transactions: [HTTPTransaction], skipped: Int) {
        let parsed = try? JSONSerialization.jsonObject(with: data)
        // Charles JSON sessions (.chlsj) are an array of entries rather than a HAR log.
        if let parsed, CharlesJSONSessionImporter.looksLikeSession(parsed) {
            let transactions = try CharlesJSONSessionImporter.importEntries(parsed)
            Self.logger.info("Imported \(transactions.count) transactions from a Charles JSON session")
            return (transactions, 0)
        }
        guard let root = parsed as? [String: Any] else {
            throw HARImportError.invalidFormat("Root object is not a JSON dictionary")
        }

        guard let log = root["log"] as? [String: Any] else {
            throw HARImportError.invalidFormat("Missing 'log' object")
        }

        if let version = log["version"] as? String, !version.hasPrefix("1.") {
            throw HARImportError.unsupportedVersion(version)
        }

        guard let entries = log["entries"] as? [[String: Any]] else {
            throw HARImportError.invalidFormat("Missing or invalid 'entries' array")
        }

        var transactions = [HTTPTransaction]()
        transactions.reserveCapacity(entries.count)
        var firstError: Error?
        var skipped = 0

        for (index, entry) in entries.enumerated() {
            do {
                transactions.append(try parseEntry(entry, at: index))
            } catch {
                firstError = firstError ?? error
                skipped += 1
            }
        }

        if transactions.isEmpty, let firstError {
            throw firstError
        }

        Self.logger.info("Imported \(transactions.count) transactions from HAR (\(skipped) skipped)")
        return (transactions, skipped)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "HARImporter"
    )

    /// HAR 1.2 only requires an ISO 8601 `startedDateTime`; fractional seconds are
    /// optional, so both shapes must parse or imported entries silently collapse
    /// onto the import time.
    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Entry Parsing

    private func parseEntry(_ entry: [String: Any], at index: Int) throws -> HTTPTransaction {
        let timestamp = parseTimestamp(entry["startedDateTime"] as? String) ?? Date()

        guard let requestDict = entry["request"] as? [String: Any] else {
            throw HARImportError.malformedEntry(index: index, reason: "Missing 'request' object")
        }

        let request = try parseRequest(requestDict, entryIndex: index)
        let response = parseResponse(entry["response"] as? [String: Any])
        let timingInfo = parseTimings(entry["timings"] as? [String: Any])

        let transaction = HTTPTransaction(
            id: UUID(),
            timestamp: timestamp,
            request: request,
            response: response,
            state: response == nil ? .failed : .completed,
            timingInfo: timingInfo
        )
        // HAR has no client field; name the client from the User-Agent like live capture does.
        transaction.clientApp = UpstreamResponseHandler.extractAppFromUserAgent(request.headers)
        return transaction
    }

    // MARK: - Request Parsing

    private func parseRequest(_ dict: [String: Any], entryIndex: Int) throws -> HTTPRequestData {
        guard let method = dict["method"] as? String else {
            throw HARImportError.malformedEntry(index: entryIndex, reason: "Missing request method")
        }

        guard let urlString = dict["url"] as? String, let url = URL(string: urlString) else {
            throw HARImportError.malformedEntry(index: entryIndex, reason: "Missing or invalid request URL")
        }

        let httpVersion = Self.normalizedHTTPVersion(dict["httpVersion"] as? String)
        var headers = parseHeaders(dict["headers"] as? [[String: Any]])
        let postData = dict["postData"] as? [String: Any]
        let body = parseRequestBody(postData)
        // Browser HARs can omit the request's Content-Type header and keep the type only in
        // `postData.mimeType`; restore it so a repeat sends the body with its real type.
        if body != nil, let mimeType = (postData?["mimeType"] as? String)?.trimmingCharacters(in: .whitespaces),
           !mimeType.isEmpty, !headers.contains(where: { $0.name.lowercased() == "content-type" })
        {
            headers.append(HTTPHeader(name: "Content-Type", value: mimeType))
        }
        let contentType = ContentTypeDetector.detect(headers: headers, body: body)

        return HTTPRequestData(
            method: method,
            url: url,
            httpVersion: httpVersion,
            headers: headers,
            body: body,
            contentType: contentType
        )
    }

    /// Browsers write `http/2.0` (Chrome), `HTTP/2` (Firefox) or ALPN ids (`h2`, `h3`); live
    /// capture stores `HTTP/x.y`, which is what the list, diff, and exporters expect.
    static func normalizedHTTPVersion(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespaces) ?? ""
        switch trimmed.lowercased() {
        case "":
            return "HTTP/1.1"
        case "h2",
             "http/2",
             "http/2.0":
            return "HTTP/2.0"
        case "h3",
             "http/3",
             "http/3.0":
            return "HTTP/3.0"
        default:
            if trimmed.lowercased().hasPrefix("http/") {
                return "HTTP/" + trimmed.dropFirst(5)
            }
            return trimmed
        }
    }

    // MARK: - Response Parsing

    private func parseResponse(_ dict: [String: Any]?) -> HTTPResponseData? {
        guard let dict, let statusCode = dict["status"] as? Int, statusCode > 0 else {
            return nil
        }

        let statusMessage = dict["statusText"] as? String ?? ""
        let headers = parseHeaders(dict["headers"] as? [[String: Any]])
        let body = parseResponseBody(dict["content"] as? [String: Any])
        let contentType = ContentTypeDetector.detect(headers: headers, body: body)

        return HTTPResponseData(
            statusCode: statusCode,
            statusMessage: statusMessage,
            headers: headers,
            body: body,
            contentType: contentType
        )
    }

    // MARK: - Timings Parsing

    private func parseTimings(_ dict: [String: Any]?) -> TimingInfo? {
        guard let dict else {
            return nil
        }

        return TimingInfo(
            dnsLookup: harMillisToSeconds(dict["dns"]),
            tcpConnection: harMillisToSeconds(dict["connect"]),
            tlsHandshake: harMillisToSeconds(dict["ssl"]),
            timeToFirstByte: harMillisToSeconds(dict["wait"]),
            contentTransfer: harMillisToSeconds(dict["receive"])
        )
    }

    // MARK: - Helpers

    private func parseHeaders(_ headerArray: [[String: Any]]?) -> [HTTPHeader] {
        guard let headerArray else {
            return []
        }
        return headerArray.compactMap { dict in
            // HTTP/2 pseudo-headers (`:authority`, `:path`, ...) describe the request line,
            // not header fields; sending one on replay is invalid.
            guard let name = dict["name"] as? String, !name.hasPrefix(":"),
                  let value = dict["value"] as? String else
            {
                return nil
            }
            return HTTPHeader(name: name, value: value)
        }
    }

    private func parseRequestBody(_ postData: [String: Any]?) -> Data? {
        guard let postData, let text = postData["text"] as? String, !text.isEmpty else {
            return nil
        }
        if let encoding = postData["encoding"] as? String, encoding.lowercased() == "base64" {
            return Data(base64Encoded: text)
        }
        return text.data(using: .utf8)
    }

    private func parseResponseBody(_ content: [String: Any]?) -> Data? {
        guard let content, let text = content["text"] as? String, !text.isEmpty else {
            return nil
        }
        if let encoding = content["encoding"] as? String, encoding.lowercased() == "base64" {
            return Data(base64Encoded: text)
        }
        return text.data(using: .utf8)
    }

    private func parseTimestamp(_ string: String?) -> Date? {
        guard let string else {
            return nil
        }
        return Self.fractionalDateFormatter.date(from: string)
            ?? Self.wholeSecondDateFormatter.date(from: string)
    }

    private func harMillisToSeconds(_ value: Any?) -> TimeInterval {
        guard let number = value as? Double, number >= 0 else {
            return 0
        }
        return number / 1_000.0
    }
}
