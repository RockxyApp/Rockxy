import CryptoKit
import Foundation

// Renders the diff interface for the diff workflow.

// MARK: - CompareTarget

enum CompareTarget: String, CaseIterable, Sendable {
    case request = "Request"
    case response = "Response"
    case timing = "Timing"

    // MARK: Internal

    var title: String {
        switch self {
        case .request: String(localized: "Request", bundle: RockxyLocalization.bundle)
        case .response: String(localized: "Response", bundle: RockxyLocalization.bundle)
        case .timing: String(localized: "Timing", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - PresentationMode

enum PresentationMode: String, CaseIterable, Sendable {
    case sideBySide = "Side by Side"
    case unified = "Unified"

    // MARK: Internal

    var title: String {
        switch self {
        case .sideBySide: String(localized: "Side by Side", bundle: RockxyLocalization.bundle)
        case .unified: String(localized: "Unified", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - DiffTransactionSnapshot

struct DiffTransactionSnapshot: Sendable {
    // MARK: Lifecycle

    init(transaction: HTTPTransaction) {
        request = transaction.request
        response = transaction.response
        timingInfo = transaction.timingInfo
        measuredDuration = transaction.measuredDuration
    }

    // MARK: Internal

    let request: HTTPRequestData
    let response: HTTPResponseData?
    let timingInfo: TimingInfo?
    let measuredDuration: TimeInterval?
}

// MARK: - DiffFormatter

/// Formats HTTPTransaction data into structured sections for diffing.
/// Produces named section pairs that DiffEngine can compare.
enum DiffFormatter {
    // MARK: Internal

    static let maximumBodyPreviewBytes = 512 * 1_024

    /// Formats a transaction into named sections based on the compare target.
    static func format(
        transaction: HTTPTransaction,
        target: CompareTarget
    )
        -> [(title: String, content: String)]
    {
        format(snapshot: DiffTransactionSnapshot(transaction: transaction), target: target)
    }

    static func format(
        snapshot: DiffTransactionSnapshot,
        target: CompareTarget
    )
        -> [(title: String, content: String)]
    {
        switch target {
        case .request:
            formatRequest(snapshot)
        case .response:
            formatResponse(snapshot)
        case .timing:
            formatTiming(snapshot)
        }
    }

    /// Computes a structured diff between two transactions for the given compare target.
    static func diff(
        left: HTTPTransaction,
        right: HTTPTransaction,
        target: CompareTarget
    )
        -> DiffResult
    {
        let leftSections = format(transaction: left, target: target)
        let rightSections = format(transaction: right, target: target)
        return DiffEngine.diffSections(leftSections: leftSections, rightSections: rightSections)
    }

    static func diff(
        left: DiffTransactionSnapshot,
        right: DiffTransactionSnapshot,
        target: CompareTarget
    )
        -> DiffResult
    {
        let leftSections = format(snapshot: left, target: target)
        let rightSections = format(snapshot: right, target: target)
        return DiffEngine.diffSections(leftSections: leftSections, rightSections: rightSections)
    }

    // MARK: Private

    // MARK: - Body Formatting

    private static var captureTruncationNotice: String {
        String(
            localized: "Capture truncated — comparison covers captured bytes only.", bundle: RockxyLocalization.bundle
        )
    }

    // MARK: - Request Formatting

    private static func formatRequest(_ transaction: DiffTransactionSnapshot) -> [(String, String)] {
        var sections: [(String, String)] = []

        // Request line
        sections.append((
            String(localized: "Request Line", bundle: RockxyLocalization.bundle),
            "\(transaction.request.method) \(transaction.request.url.path) \(normalizeHTTPVersion(transaction.request.httpVersion))"
        ))

        // Host
        sections.append((
            String(localized: "Host", bundle: RockxyLocalization.bundle),
            transaction.request.url.host ?? "—"
        ))

        // Query
        let queryItems = URLComponents(url: transaction.request.url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        if !queryItems.isEmpty {
            let queryText = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "\n")
            sections.append((String(localized: "Query", bundle: RockxyLocalization.bundle), queryText))
        } else {
            sections.append((
                String(localized: "Query", bundle: RockxyLocalization.bundle),
                String(localized: "(no query parameters)", bundle: RockxyLocalization.bundle)
            ))
        }

        // Request headers
        let headersText = transaction.request.headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")
        sections.append((
            String(localized: "Headers", bundle: RockxyLocalization.bundle),
            headersText.isEmpty ? String(localized: "(no headers)", bundle: RockxyLocalization.bundle) : headersText
        ))

        // Request body
        if let body = transaction.request.body {
            sections.append((
                String(localized: "Body", bundle: RockxyLocalization.bundle),
                formatBody(body, contentType: transaction.request.contentType?.rawValue)
            ))
        } else {
            sections.append((
                String(localized: "Body", bundle: RockxyLocalization.bundle),
                String(localized: "No request body", bundle: RockxyLocalization.bundle)
            ))
        }

        return sections
    }

    // MARK: - Response Formatting

    private static func formatResponse(_ transaction: DiffTransactionSnapshot) -> [(String, String)] {
        var sections: [(String, String)] = []

        guard let response = transaction.response else {
            return [
                (
                    String(localized: "Status Line", bundle: RockxyLocalization.bundle),
                    String(localized: "No response", bundle: RockxyLocalization.bundle)
                ),
                (
                    String(localized: "Headers", bundle: RockxyLocalization.bundle),
                    String(localized: "(no headers)", bundle: RockxyLocalization.bundle)
                ),
                (
                    String(localized: "Body", bundle: RockxyLocalization.bundle),
                    String(localized: "No response body", bundle: RockxyLocalization.bundle)
                ),
            ]
        }

        // Status line
        sections.append((
            String(localized: "Status Line", bundle: RockxyLocalization.bundle),
            "HTTP/1.1 \(response.statusCode) \(response.statusMessage)"
        ))

        // Response headers
        let headersText = response.headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")
        sections.append((
            String(localized: "Headers", bundle: RockxyLocalization.bundle),
            headersText.isEmpty ? String(localized: "(no headers)", bundle: RockxyLocalization.bundle) : headersText
        ))

        // Response body — decoded through `Content-Encoding` like the inspector, so two
        // gzip JSON responses diff as text instead of two opaque binary summaries.
        if let rawBody = response.body {
            let contentType = response.headers.first { $0.name.lowercased() == "content-type" }?.value
            let contentEncoding = response.headers.first { $0.name.lowercased() == "content-encoding" }?.value
            sections.append((
                String(localized: "Body", bundle: RockxyLocalization.bundle),
                formatBody(
                    BodyDecoder.decode(rawBody, encoding: contentEncoding),
                    contentType: contentType,
                    captureWasTruncated: response.bodyTruncated
                )
            ))
        } else {
            let bodyText = response.bodyTruncated
                ? "\(String(localized: "No response body", bundle: RockxyLocalization.bundle))\n\(captureTruncationNotice)"
                : String(localized: "No response body", bundle: RockxyLocalization.bundle)
            sections.append((String(localized: "Body", bundle: RockxyLocalization.bundle), bodyText))
        }

        return sections
    }

    // MARK: - Timing Formatting

    private static func formatTiming(_ transaction: DiffTransactionSnapshot) -> [(String, String)] {
        guard let timing = transaction.timingInfo else {
            if let measuredDuration = transaction.measuredDuration {
                return [(
                    String(localized: "Timing", bundle: RockxyLocalization.bundle),
                    "\(String(localized: "Total measured duration", bundle: RockxyLocalization.bundle)): \(formatMs(measuredDuration))\n"
                        + String(localized: "Detailed phase timing unavailable", bundle: RockxyLocalization.bundle)
                )]
            }
            return [(
                String(localized: "Timing", bundle: RockxyLocalization.bundle),
                String(localized: "No timing data", bundle: RockxyLocalization.bundle)
            )]
        }

        let content = """
        \(String(localized: "DNS Lookup", bundle: RockxyLocalization.bundle)): \(formatMs(timing.dnsLookup))
        \(String(localized: "TCP Connection", bundle: RockxyLocalization.bundle)): \(formatMs(timing.tcpConnection))
        \(String(localized: "TLS Handshake", bundle: RockxyLocalization.bundle)): \(formatMs(timing.tlsHandshake))
        \(String(
            localized: "Time to First Byte",
            bundle: RockxyLocalization.bundle
        )): \(formatMs(timing.timeToFirstByte))
        \(String(localized: "Content Transfer", bundle: RockxyLocalization.bundle)): \(formatMs(timing.contentTransfer))
        \(String(localized: "Total", bundle: RockxyLocalization.bundle)): \(formatMs(timing.totalDuration))
        """

        return [(String(localized: "Timing", bundle: RockxyLocalization.bundle), content)]
    }

    private static func formatBody(
        _ data: Data,
        contentType: String?,
        captureWasTruncated: Bool = false
    )
        -> String
    {
        let bodyIsLimited = data.count > maximumBodyPreviewBytes
        let previewData = validUTF8Prefix(of: data, limit: maximumBodyPreviewBytes)
        let shouldTreatAsBinary = isBinaryContentType(contentType)
            || containsBinaryControlBytes(previewData)
            || String(data: previewData, encoding: .utf8) == nil

        if shouldTreatAsBinary {
            return binaryDescription(
                data,
                contentType: contentType,
                captureWasTruncated: captureWasTruncated
            )
        }

        guard let text = String(data: previewData, encoding: .utf8) else {
            return binaryDescription(
                data,
                contentType: contentType,
                captureWasTruncated: captureWasTruncated
            )
        }

        // Try JSON pretty-print
        let renderedText: String = if !bodyIsLimited,
                                      let jsonObject = try? JSONSerialization.jsonObject(with: previewData),
                                      let prettyData = try? JSONSerialization.data(
                                          withJSONObject: jsonObject,
                                          options: [.prettyPrinted, .sortedKeys]
                                      ),
                                      let prettyText = String(data: prettyData, encoding: .utf8)
        {
            prettyText
        } else {
            text
        }

        var lines = [renderedText]
        if bodyIsLimited {
            lines.append(
                String(
                    localized:
                    "Body preview limited to \(previewData.count) of \(data.count) captured bytes.",
                    bundle: RockxyLocalization.bundle
                )
            )
            lines.append(
                "\(String(localized: "SHA-256 (all captured bytes)", bundle: RockxyLocalization.bundle)): \(sha256(data))"
            )
        }
        if captureWasTruncated {
            lines.append(captureTruncationNotice)
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizeHTTPVersion(_ version: String) -> String {
        version.uppercased().hasPrefix("HTTP/") ? version : "HTTP/\(version)"
    }

    /// Deliberately not `DurationFormatter`: a diff puts two timing blocks side by side, so every
    /// phase has to render in one fixed unit. Adaptive units would print "1.23 s" against "980 ms"
    /// for values the reader is trying to subtract.
    private static func formatMs(_ seconds: TimeInterval) -> String {
        "\(DecimalFormatter.format(seconds * 1_000, fractionDigits: 1))ms"
    }

    private static func sha256(_ data: Data) -> String {
        let chunkSize = 64 * 1_024
        var hasher = SHA256()
        var offset = data.startIndex

        while offset < data.endIndex {
            guard !Task.isCancelled else {
                return ""
            }
            let end = min(offset + chunkSize, data.endIndex)
            hasher.update(data: data[offset ..< end])
            offset = end
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func binaryDescription(
        _ data: Data,
        contentType: String?,
        captureWasTruncated: Bool
    )
        -> String
    {
        var lines = [
            String(localized: "Binary body", bundle: RockxyLocalization.bundle),
            "\(String(localized: "Size", bundle: RockxyLocalization.bundle)): \(data.count) \(String(localized: "bytes", bundle: RockxyLocalization.bundle))",
            "\(String(localized: "Content-Type", bundle: RockxyLocalization.bundle)): \(contentType ?? String(localized: "unknown", bundle: RockxyLocalization.bundle))",
            "\(String(localized: "SHA-256 (captured bytes)", bundle: RockxyLocalization.bundle)): \(sha256(data))",
        ]
        if captureWasTruncated {
            lines.append(captureTruncationNotice)
        }
        return lines.joined(separator: "\n")
    }

    private static func validUTF8Prefix(of data: Data, limit: Int) -> Data {
        var prefix = Data(data.prefix(limit))
        guard data.count > limit else {
            return prefix
        }
        for _ in 0 ..< 4 where String(data: prefix, encoding: .utf8) == nil && !prefix.isEmpty {
            prefix.removeLast()
        }
        return prefix
    }

    private static func isBinaryContentType(_ contentType: String?) -> Bool {
        guard let contentType = contentType?.lowercased() else {
            return false
        }
        if contentType.hasPrefix("text/")
            || contentType.contains("json")
            || contentType.contains("xml")
            || contentType.contains("javascript")
            || contentType.contains("x-www-form-urlencoded")
        {
            return false
        }
        return contentType.hasPrefix("image/")
            || contentType.hasPrefix("audio/")
            || contentType.hasPrefix("video/")
            || contentType.hasPrefix("font/")
            || contentType.contains("octet-stream")
            || contentType.contains("pdf")
            || contentType.contains("zip")
            || contentType.contains("gzip")
            || contentType.contains("protobuf")
    }

    private static func containsBinaryControlBytes(_ data: Data) -> Bool {
        for (index, byte) in data.enumerated() {
            if index.isMultiple(of: 64 * 1_024), Task.isCancelled {
                return false
            }
            if byte == 0 || byte < 0x09 || (byte > 0x0D && byte < 0x20) {
                return true
            }
        }
        return false
    }
}
