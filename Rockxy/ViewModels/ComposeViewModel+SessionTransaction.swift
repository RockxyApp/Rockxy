import Foundation

// MARK: - ComposeViewModel + Session Row

extension ComposeViewModel {
    /// Builds the session row for a Compose send. Compose bypasses the proxy (no rules apply),
    /// so, like a Repeat, the row is attributed to Rockxy itself.
    static func makeSessionTransaction(
        url: URL,
        method: String,
        headers: [EditableReplayHeader],
        requestBody: String,
        response: HTTPURLResponse?,
        body: Data?,
        startedAt: Date,
        now: Date = Date()
    )
        -> HTTPTransaction
    {
        let requestHeaders = headers
            .filter { $0.isEnabled && !$0.name.isEmpty }
            .map { HTTPHeader(name: $0.name, value: $0.value) }
        let bodyData = requestBody.isEmpty ? nil : Data(requestBody.utf8)
        let requestData = HTTPRequestData(
            method: method,
            url: url,
            httpVersion: "HTTP/1.1",
            headers: requestHeaders,
            body: bodyData,
            contentType: ContentTypeDetector.detect(headers: requestHeaders, body: bodyData)
        )
        let responseData = response.map { response in
            HTTPResponseData(
                statusCode: response.statusCode,
                statusMessage: HTTPReasonPhrase.standard(for: response.statusCode),
                headers: response.allHeaderFields.compactMap { key, value in
                    (key as? String).map { HTTPHeader(name: $0, value: "\(value)") }
                },
                body: body,
                contentType: ContentType.detect(from: response.value(forHTTPHeaderField: "Content-Type"))
            )
        }
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let transaction = HTTPTransaction(
            timestamp: startedAt,
            request: requestData,
            response: responseData,
            state: responseData == nil ? .failed : .completed,
            timingInfo: TimingInfo(
                dnsLookup: 0,
                tcpConnection: 0,
                tlsHandshake: 0,
                timeToFirstByte: elapsed,
                contentTransfer: 0
            )
        )
        transaction.measuredDuration = elapsed
        transaction.clientApp = RockxyIdentity.current.displayName
        transaction.sslCapture = url.scheme?.lowercased() == "https" ? .intercepted : nil
        return transaction
    }
}
