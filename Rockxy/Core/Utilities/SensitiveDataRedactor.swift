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

    static let sensitiveHeaders: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "www-authenticate",
        "proxy-authenticate",
        "x-api-key",
        "x-auth-token",
        "x-access-token",
        "x-csrf-token",
        "x-xsrf-token",
        "x-payment",
        "x-payment-response",
    ]

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
            guard Self.sensitiveHeaders.contains(header.name.lowercased()) else {
                return header
            }
            return HTTPHeader(name: header.name, value: redactedPlaceholder)
        }
    }

    func redactURL(_ url: URL) -> URL {
        guard isEnabled else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else {
            return url
        }

        components.queryItems = queryItems.map { item in
            guard Self.sensitiveQueryParams.contains(item.name.lowercased()) else {
                return item
            }
            return URLQueryItem(name: item.name, value: redactedPlaceholder)
        }
        return components.url ?? url
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

        let request = HTTPRequestData(
            method: transaction.request.method,
            url: redactURL(transaction.request.url),
            httpVersion: transaction.request.httpVersion,
            headers: redactHeaders(transaction.request.headers),
            body: redactBody(transaction.request.body, contentType: transaction.request.contentType),
            contentType: transaction.request.contentType
        )
        let response = transaction.response.map { response in
            HTTPResponseData(
                statusCode: response.statusCode,
                statusMessage: response.statusMessage,
                headers: redactHeaders(response.headers),
                body: redactBody(response.body, contentType: response.contentType),
                bodyTruncated: response.bodyTruncated,
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
        redacted.isTLSFailure = transaction.isTLSFailure
        redacted.webSocketFrameVersion = transaction.webSocketFrameVersion
        redacted.matchedRuleID = transaction.matchedRuleID
        redacted.matchedRuleName = transaction.matchedRuleName
        redacted.matchedRuleActionSummary = transaction.matchedRuleActionSummary
        redacted.matchedRulePattern = transaction.matchedRulePattern
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
        return result
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
            if Self.sensitiveQueryParams.contains(decodedKey.lowercased()) {
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
                if Self.sensitiveBodyKeys.contains(key.lowercased()) {
                    return (key, redactedPlaceholder)
                }
                return (key, redactJSONObject(value))
            }
            return Dictionary(uniqueKeysWithValues: entries)
        }

        if let array = object as? [Any] {
            return array.map { redactJSONObject($0) }
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
