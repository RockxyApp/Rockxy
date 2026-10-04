import Foundation

// MARK: - SensitiveDataRedactor

/// Shared redaction vocabulary for user-facing export/share surfaces.
/// The defaults intentionally match the MCP redaction policy so traffic leaves
/// Rockxy with the same sensitive header, query, and body handling.
struct SensitiveDataRedactor {
    // MARK: Lifecycle

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    // MARK: Internal

    /// Largest captured (wire) body decompressed so its text can be redacted.
    static let maxDecodableBodyBytes = 10 * 1_024 * 1_024

    static let sensitiveHeaders: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "www-authenticate",
        "proxy-authenticate",
        "api-key",
        "ocp-apim-subscription-key",
        "x-api-key",
        "x-auth-token",
        "x-access-token",
        "x-csrf-token",
        "x-goog-api-key",
        "x-xsrf-token",
        "x-payment",
        "x-payment-response",
    ]

    /// Name fragments that mark a credential even when the exact name is not listed
    /// (`X-Refresh-Token`, `id_token`, `session_id`, `x-amz-security-token`).
    static let sensitiveNameFragments: [String] = [
        "token", "secret", "password", "passwd", "apikey", "api-key", "api_key",
        "session", "signature", "credential", "private-key", "private_key",
    ]

    static func isSensitiveName(_ name: String, exact: Set<String>) -> Bool {
        let lowered = name.lowercased()
        return exact.contains(lowered) || sensitiveNameFragments.contains { lowered.contains($0) }
    }

    /// Whether a JSON key holds a credential: body-key names, header names that servers echo
    /// into bodies (`Authorization`, `X-Api-Key`), and credential-like names. `token` only
    /// counts at the end of a key, so usage counters such as `total_tokens` stay readable.
    static func isSensitiveBodyKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        if sensitiveBodyKeys.contains(lowered) || sensitiveHeaders.contains(lowered) {
            return true
        }
        if lowered.hasSuffix("token") {
            return true
        }
        return bodyKeyFragments.contains { lowered.contains($0) }
    }

    /// Redacts credentials carried inside a JSON string value: sensitive query parameters
    /// of an embedded URL and `Bearer`/`Basic` authorization values.
    static func redactedStringValue(_ value: String, placeholder: String) -> String {
        var result = value
        if result.contains("?"), result.contains("="), var components = URLComponents(string: result),
           components.scheme != nil, let items = components.queryItems, !items.isEmpty
        {
            components.queryItems = items.map { item in
                isSensitiveName(item.name, exact: sensitiveQueryParams)
                    ? URLQueryItem(name: item.name, value: placeholder)
                    : item
            }
            result = components.string ?? result
        }
        let range = NSRange(result.startIndex ..< result.endIndex, in: result)
        return authorizationValueRegex.stringByReplacingMatches(
            in: result,
            range: range,
            withTemplate: "$1\(NSRegularExpression.escapedTemplate(for: placeholder))"
        )
    }

    static let sensitiveQueryParams: Set<String> = [
        "api_key",
        "apikey",
        "api-key",
        "token",
        "access_token",
        "auth_token",
        "refresh_token",
        "secret",
        "password",
        "passwd",
        "pwd",
        "private_key",
        "private-key",
        "privatekey",
        "seed",
        "seed_phrase",
        "seed-phrase",
        "seedphrase",
        "mnemonic",
        "recovery_phrase",
        "recovery-phrase",
        "recoveryphrase",
        "signature",
        "client_secret",
        "clientsecret",
        "provider_key",
        "provider-key",
        "providerkey",
        "rpc_key",
        "rpc-key",
        "rpckey",
        "rpc_url",
        "rpc-url",
        "rpcurl",
        "wallet_key",
        "wallet-key",
        "walletkey",
        "wallet_secret",
        "wallet-secret",
        "walletsecret",
        "payment",
        "payment_payload",
        "payment-payload",
        "paymentpayload",
        "payment_header",
        "payment-header",
        "paymentheader",
        "payment_proof",
        "payment-proof",
        "paymentproof",
        "x-payment",
        "x-payment-response",
        "maxamountrequired",
        "max_amount_required",
        "max-amount-required",
        "key",
    ]

    /// Name fragments for JSON keys; narrower than `sensitiveNameFragments` so that keys such
    /// as `session_count` or `prompt_tokens` are not hidden.
    static let bodyKeyFragments: [String] = [
        "secret", "password", "passwd", "apikey", "api-key", "api_key", "private-key", "private_key",
        "credential", "authorization",
    ]

    // swiftlint:disable:next force_try
    static let authorizationValueRegex = try! NSRegularExpression(
        pattern: #"\b((?:Bearer|Basic)\s+)[A-Za-z0-9._~+/=-]+"#,
        options: [.caseInsensitive]
    )

    static let sensitiveBodyKeys: Set<String> = sensitiveQueryParams
        .subtracting(["key"])
        .union([
            "credentials",
            "id_token",
            "prompt",
            "prompts",
            "messages",
            "input",
            "instructions",
            "system_prompt",
            "system-prompt",
            "systemprompt",
            "developer_message",
            "developer-message",
            "developermessage",
            "tools",
            "tool",
            "tool_calls",
            "tool-calls",
            "toolcalls",
            "tool_call",
            "tool-call",
            "toolcall",
            "function_call",
            "function-call",
            "functioncall",
            "arguments",
            "args",
            "retrieved_context",
            "retrieved-context",
            "retrievedcontext",
            "rag_context",
            "rag-context",
            "ragcontext",
            "context",
            "snippet",
            "embedding",
            "embeddings",
            "vector",
            "vectors",
        ])

    let isEnabled: Bool

    var redactedPlaceholder: String {
        "[REDACTED]"
    }

    func redactHeaders(_ headers: [HTTPHeader]) -> [HTTPHeader] {
        guard isEnabled else {
            return headers
        }
        return headers.map { header in
            guard Self.isSensitiveName(header.name, exact: Self.sensitiveHeaders) else {
                return header
            }
            return HTTPHeader(name: header.name, value: redactedPlaceholder)
        }
    }

    func redactURL(_ url: URL) -> URL {
        guard isEnabled else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var didRedact = false
        if components.user != nil || components.password != nil {
            components.user = nil
            components.password = nil
            didRedact = true
        }

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.map { item in
                guard Self.isSensitiveName(item.name, exact: Self.sensitiveQueryParams) else {
                    return item
                }
                didRedact = true
                return URLQueryItem(name: item.name, value: redactedPlaceholder)
            }
        }

        return didRedact ? (components.url ?? url) : url
    }

    /// Decodes a bounded compressed body so redaction can inspect its text.
    private static func readableBody(_ body: Data?, headers: [HTTPHeader]) -> (body: Data?, didDecode: Bool) {
        guard let body, !body.isEmpty, body.count <= maxDecodableBodyBytes else {
            return (body, false)
        }
        let contentEncoding = headers.first { $0.name.lowercased() == "content-encoding" }?.value
        let decoded = BodyDecoder.decodeReportingChange(body, encoding: contentEncoding)
        return decoded.didDecode ? (decoded.data, true) : (body, false)
    }

    private func redactedBodyAndHeaders(
        body: Data?,
        headers: [HTTPHeader],
        contentType: ContentType?
    ) -> (body: Data?, headers: [HTTPHeader], omitted: Bool) {
        let readable = Self.readableBody(body, headers: headers)
        let hasContentEncoding = headers.contains { $0.name.lowercased() == "content-encoding" }
        let omitUninspectableBody = hasContentEncoding && body != nil
            && (!readable.didDecode || readable.body.flatMap { String(data: $0, encoding: .utf8) } == nil)
        let retainedHeaders = (readable.didDecode || omitUninspectableBody)
            ? headers.filter { header in
                let name = header.name.lowercased()
                return name != "content-encoding" && name != "content-length"
            }
            : headers
        return (
            omitUninspectableBody ? nil : redactBody(readable.body, contentType: contentType),
            redactHeaders(retainedHeaders),
            omitUninspectableBody
        )
    }

    func redactBody(_ body: Data?, contentType: ContentType?) -> Data? {
        guard isEnabled, let body else {
            return body
        }
        guard let text = String(data: body, encoding: .utf8) else {
            return body
        }
        return redactBodyText(text, contentType: contentType).data(using: .utf8) ?? body
    }

    func redactBodyText(_ text: String, contentType: ContentType?) -> String {
        guard isEnabled else {
            return text
        }
        if contentType == .json || looksLikeJSON(text) {
            return redactJSONBody(text)
        }
        if contentType == .form {
            return redactFormBody(text)
        }
        if contentType == .xml {
            return redactXMLBody(text)
        }
        return redactGenericText(text)
    }

    func redactTransaction(_ transaction: HTTPTransaction) -> HTTPTransaction {
        guard isEnabled else {
            return transaction
        }

        let redactedRequest = redactedBodyAndHeaders(
            body: transaction.request.body,
            headers: transaction.request.headers,
            contentType: transaction.request.contentType
        )
        let request = HTTPRequestData(
            method: transaction.request.method,
            url: redactURL(transaction.request.url),
            httpVersion: transaction.request.httpVersion,
            headers: redactedRequest.headers,
            body: redactedRequest.body,
            contentType: transaction.request.contentType
        )
        let response = transaction.response.map { response in
            // Redaction can only see into text, so a compressed body is decoded first and the
            // headers that described the compressed representation are dropped to keep the
            // published transaction coherent. An encoded body that cannot be decoded is
            // omitted rather than exported with secrets that redaction could not inspect.
            let redactedResponse = redactedBodyAndHeaders(
                body: response.body,
                headers: response.headers,
                contentType: response.contentType
            )
            return HTTPResponseData(
                statusCode: response.statusCode,
                statusMessage: response.statusMessage,
                headers: redactedResponse.headers,
                body: redactedResponse.body,
                bodyTruncated: response.bodyTruncated || redactedResponse.omitted,
                contentType: response.contentType
            )
        }
        let redacted = HTTPTransaction(
            id: transaction.id,
            timestamp: transaction.timestamp,
            request: request,
            response: response,
            state: transaction.state,
            timingInfo: transaction.timingInfo,
            webSocketConnection: transaction.webSocketConnection,
            graphQLInfo: transaction.graphQLInfo,
            web3RPCInfo: transaction.web3RPCInfo
        )
        redacted.measuredDuration = transaction.measuredDuration
        redacted.sourcePort = transaction.sourcePort
        redacted.clientApp = transaction.clientApp
        redacted.comment = transaction.comment
        redacted.highlightColor = transaction.highlightColor
        redacted.isPinned = transaction.isPinned
        redacted.isSaved = transaction.isSaved
        redacted.isStruckThrough = transaction.isStruckThrough
        redacted.isTLSFailure = transaction.isTLSFailure
        redacted.webSocketFrameVersion = transaction.webSocketFrameVersion
        redacted.matchedRuleID = transaction.matchedRuleID
        redacted.matchedRuleName = transaction.matchedRuleName
        redacted.matchedRuleActionSummary = transaction.matchedRuleActionSummary
        redacted.matchedRulePattern = transaction.matchedRulePattern
        redacted.appliedScriptNames = transaction.appliedScriptNames
        redacted.noCachingApplied = transaction.noCachingApplied
        redacted.serverHTTPVersion = transaction.serverHTTPVersion
        // The local socket address identifies the capturing machine on its network.
        redacted.connectionLog = transaction.connectionLog.map {
            var log = $0
            log.localAddress = nil
            log.localPort = nil
            return log
        }
        redacted.sequenceNumber = transaction.sequenceNumber
        return redacted
    }

    // MARK: Private

    // swiftlint:disable force_try
    private static let jsonScalarPattern =
        #""(?:\\.|[^"\\])*"|true|false|null|-?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?"#

    private static let bodyTokenPatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"("(?:token|access_token|auth_token|refresh_token|id_token|api_key|apikey|api_token)")\s*:\s*\#(jsonScalarPattern)"#,
        options: [.caseInsensitive]
    )

    private static let bodySecretKeyPattern = [
        sensitiveBodyKeys,
        sensitiveQueryParams.subtracting(["key"]),
    ]
    .flatMap { $0 }
    .map { NSRegularExpression.escapedPattern(for: $0) }
    .joined(separator: "|")

    private static let bodySecretPatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"("(?:\#(bodySecretKeyPattern))")\s*:\s*\#(jsonScalarPattern)"#,
        options: [.caseInsensitive]
    )

    /// Header names echoed as JSON keys, for bodies too truncated to parse.
    private static let bodyHeaderKeyPatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"("(?:\#(sensitiveHeaders.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")))")\s*:\s*\#(jsonScalarPattern)"#,
        options: [.caseInsensitive]
    )

    private static let xmlSensitivePatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"<(\#(bodySecretKeyPattern))>([^<]*)</"#,
        options: [.caseInsensitive]
    )

    private static let genericBearerPatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(Bearer\s+)\S+"#,
        options: [.caseInsensitive]
    )

    private static let genericKeyValuePatternRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(?i)((?:\#(bodySecretKeyPattern))[\s]*[:=][\s]*)\S+"#,
        options: []
    )
    // swiftlint:enable force_try

    private func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            return false
        }
        guard let data = trimmed.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func redactJSONBody(_ body: String) -> String {
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object)
        {
            let redactedObject = redactJSONObject(object)
            if JSONSerialization.isValidJSONObject(redactedObject),
               let redactedData = try? JSONSerialization.data(withJSONObject: redactedObject),
               let redactedBody = String(data: redactedData, encoding: .utf8)
            {
                return redactedBody
            }
        }

        var result = body
        result = applyRegex(Self.bodyTokenPatternRegex, to: result)
        result = applyRegex(Self.bodySecretPatternRegex, to: result)
        result = applyRegex(Self.bodyHeaderKeyPatternRegex, to: result)
        let range = NSRange(result.startIndex ..< result.endIndex, in: result)
        return Self.authorizationValueRegex.stringByReplacingMatches(
            in: result,
            range: range,
            withTemplate: "$1\(redactedPlaceholder)"
        )
    }

    private func redactFormBody(_ body: String) -> String {
        let pairs = body.components(separatedBy: "&")
        let redacted = pairs.map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                return pair
            }
            let key = String(parts[0])
            let decodedKey = key.removingPercentEncoding ?? key
            if Self.isSensitiveName(decodedKey, exact: Self.sensitiveQueryParams) {
                return "\(key)=\(redactedPlaceholder)"
            }
            return pair
        }
        return redacted.joined(separator: "&")
    }

    private func redactXMLBody(_ body: String) -> String {
        let range = NSRange(body.startIndex ..< body.endIndex, in: body)
        return Self.xmlSensitivePatternRegex.stringByReplacingMatches(
            in: body,
            range: range,
            withTemplate: "<$1>[REDACTED]</"
        )
    }

    private func redactGenericText(_ body: String) -> String {
        var result = body
        let range = NSRange(result.startIndex ..< result.endIndex, in: result)
        result = Self.genericBearerPatternRegex.stringByReplacingMatches(
            in: result,
            range: range,
            withTemplate: "$1[REDACTED]"
        )
        let range2 = NSRange(result.startIndex ..< result.endIndex, in: result)
        result = Self.genericKeyValuePatternRegex.stringByReplacingMatches(
            in: result,
            range: range2,
            withTemplate: "$1[REDACTED]"
        )
        return result
    }

    private func redactJSONObject(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            let entries: [(String, Any)] = dictionary.map { element in
                let (key, value) = element
                if Self.isSensitiveBodyKey(key) {
                    return (key, redactedPlaceholder)
                }
                return (key, redactJSONObject(value))
            }
            return Dictionary(uniqueKeysWithValues: entries)
        }

        if let array = object as? [Any] {
            return array.map { redactJSONObject($0) }
        }

        if let string = object as? String {
            return Self.redactedStringValue(string, placeholder: redactedPlaceholder)
        }

        return object
    }

    private func applyRegex(_ regex: NSRegularExpression, to input: String) -> String {
        let range = NSRange(input.startIndex ..< input.endIndex, in: input)
        return regex.stringByReplacingMatches(
            in: input,
            range: range,
            withTemplate: "$1: \"\(redactedPlaceholder)\""
        )
    }
}
