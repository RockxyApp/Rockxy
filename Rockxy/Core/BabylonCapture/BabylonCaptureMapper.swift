import Foundation

enum BabylonCaptureMapper {
    // MARK: Internal

    static func makeTransaction(
        from package: BabylonTrafficPackageDTO,
        identity: BabylonCaptureIdentity
    )
        throws -> HTTPTransaction
    {
        guard !package.request.method.isEmpty, package.request.method.count <= 32 else {
            throw BabylonCaptureMappingError.invalidMethod
        }
        guard package.request.url.count <= ProxyLimits.maxURILength,
              let url = URL(string: package.request.url),
              let scheme = url.scheme?.lowercased() else
        {
            throw BabylonCaptureMappingError.invalidURL
        }
        guard ["http", "https", "ws", "wss"].contains(scheme) else {
            throw BabylonCaptureMappingError.unsupportedScheme
        }
        try validateBody(package.request.body)
        try validateBody(package.responseBodyData)

        let requestHeaders = headers(package.request.headers)
        let request = HTTPRequestData(
            method: package.request.method,
            url: url,
            httpVersion: "HTTP/1.1",
            headers: requestHeaders,
            body: package.request.body,
            contentType: ContentTypeDetector.detect(headers: requestHeaders, body: package.request.body)
        )
        let response = try package.response.map { response in
            guard (100 ... 599).contains(response.statusCode) else {
                throw BabylonCaptureMappingError.invalidStatusCode
            }
            let responseHeaders = headers(response.headers)
            let body = package.responseBodyData.isEmpty ? nil : package.responseBodyData
            return HTTPResponseData(
                statusCode: response.statusCode,
                statusMessage: HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
                headers: responseHeaders,
                body: body,
                contentType: ContentTypeDetector.detect(headers: responseHeaders, body: body)
            )
        }

        let duration = max(0, (package.endAt ?? package.startAt) - package.startAt)
        let timing = TimingInfo(
            dnsLookup: 0,
            tcpConnection: 0,
            tlsHandshake: 0,
            timeToFirstByte: 0,
            contentTransfer: duration
        )
        let webSocketConnection = package.packageType == .websocket
            ? WebSocketConnection(upgradeRequest: request)
            : nil
        let transaction = HTTPTransaction(
            timestamp: Date(timeIntervalSince1970: package.startAt),
            request: request,
            response: response,
            state: package.error == nil ? .completed : .failed,
            timingInfo: timing,
            webSocketConnection: webSocketConnection
        )
        transaction.measuredDuration = duration
        transaction.clientApp = identity.displayName
        return transaction
    }

    static func makeWebSocketFrame(from package: BabylonTrafficPackageDTO) throws -> WebSocketFrameData {
        guard let message = package.websocketMessagePackage else {
            throw BabylonCaptureMappingError.missingWebSocketMessage
        }
        let direction: FrameDirection = switch message.messageType {
        case .receive:
            .received
        case .send,
             .sendCloseMessage,
             .pingPong:
            .sent
        }
        let opcode: FrameOpcode
        let payload: Data
        switch message.messageType {
        case .sendCloseMessage:
            opcode = .connectionClose
            payload = message.dataValue ?? Data((message.stringValue ?? "").utf8)
        case .pingPong:
            opcode = .ping
            payload = message.dataValue ?? Data((message.stringValue ?? "").utf8)
        case .send,
             .receive:
            if let data = message.dataValue {
                opcode = .binary
                payload = data
            } else {
                opcode = .text
                payload = Data((message.stringValue ?? "").utf8)
            }
        }
        guard payload.count <= ProxyLimits.maxWebSocketFrameSize else {
            throw BabylonCaptureMappingError.oversizedBody
        }
        return WebSocketFrameData(
            timestamp: Date(timeIntervalSince1970: message.createdAt),
            direction: direction,
            opcode: opcode,
            payload: payload
        )
    }

    // MARK: Private

    private static func headers(_ values: [BabylonTrafficPackageDTO.Header]) -> [HTTPHeader] {
        values.prefix(1_024).map {
            HTTPHeader(name: String($0.key.prefix(1_024)), value: String($0.value.prefix(32_768)))
        }
    }

    private static func validateBody(_ body: Data?) throws {
        guard let body else {
            return
        }
        try validateBody(body)
    }

    private static func validateBody(_ body: Data) throws {
        guard body.count <= BabylonCaptureProtocol.maximumCapturedBodySize else {
            throw BabylonCaptureMappingError.oversizedBody
        }
    }
}
