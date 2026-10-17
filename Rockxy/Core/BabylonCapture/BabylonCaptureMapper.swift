import Foundation

enum BabylonCaptureMapper {
    // MARK: Internal

    /// The SDK replaces a body it would not capture with this marker.
    static let omittedBodyMarker = Data("<Skip Large Body>".utf8)

    static func makeTransaction(
        from package: BabylonTrafficPackageDTO,
        identity: BabylonCaptureIdentity
    )
        throws -> HTTPTransaction
    {
        guard package.packageType != .unknown else {
            throw BabylonCaptureMappingError.unsupportedPackage
        }
        guard !package.request.method.isEmpty, package.request.method.count <= 32 else {
            throw BabylonCaptureMappingError.invalidMethod
        }
        if isGRPC(package) {
            return try makeGRPCTransaction(from: package, identity: identity)
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
        let capturedRequestBody = capturedBody(package.request.body)
        let request = HTTPRequestData(
            method: package.request.method,
            url: url,
            httpVersion: "HTTP/1.1",
            headers: requestHeaders,
            body: capturedRequestBody.data,
            bodyTruncated: capturedRequestBody.wasOmitted || package.requestBodyOmission != nil,
            bodyOmission: omissionMetadata(package.requestBodyOmission),
            contentType: ContentTypeDetector.detect(headers: requestHeaders, body: capturedRequestBody.data)
        )
        let response = try package.response.map { response in
            try makeResponse(
                statusCode: response.statusCode,
                headers: headers(response.headers),
                body: package.responseBodyData,
                omission: package.responseBodyOmission
            )
        }

        let isLiveWebSocket = package.packageType == .websocket && package.endAt == nil && package.error == nil
        let transaction = HTTPTransaction(
            timestamp: Date(timeIntervalSince1970: package.startAt),
            request: request,
            response: response,
            state: isLiveWebSocket ? .active : (package.error == nil ? .completed : .failed),
            timingInfo: isLiveWebSocket ? nil : timing(for: package),
            webSocketConnection: package.packageType == .websocket ? WebSocketConnection(upgradeRequest: request) : nil,
            // Rows from the SDK never pass through the proxy's detection, so label them here.
            graphQLInfo: GraphQLDetector.detect(request: request)
        )
        if !isLiveWebSocket {
            transaction.measuredDuration = duration(for: package)
        }
        transaction.clientApp = identity.displayName
        transaction.connectionLog = appReportedFailure(package.error, url: url)
        return transaction
    }

    /// Applies a later package for an already-captured row: a WebSocket that closed or failed, or
    /// a response that arrived after the request was first reported.
    @MainActor
    static func applyUpdate(_ package: BabylonTrafficPackageDTO, to transaction: HTTPTransaction) throws {
        if transaction.response == nil, let response = package.response {
            transaction.response = try makeResponse(
                statusCode: response.statusCode,
                headers: headers(response.headers),
                body: package.responseBodyData,
                omission: package.responseBodyOmission
            )
        }
        guard package.endAt != nil || package.error != nil, transaction.state == .active else {
            return
        }
        transaction.state = package.error == nil ? .completed : .failed
        transaction.timingInfo = timing(for: package)
        transaction.measuredDuration = duration(for: package)
        if let log = appReportedFailure(package.error, url: transaction.request.url) {
            transaction.connectionLog = log
        }
    }

    // MARK: gRPC

    /// The SDK's manual gRPC capture sends method `GRPC`, a bare `/package.Service/Method` path,
    /// raw message bytes, and the call status as diagnostic headers. Rebuild it as the gRPC call it
    /// was, so the gRPC tab can read it.
    static func isGRPC(_ package: BabylonTrafficPackageDTO) -> Bool {
        package.packageType == .grpc || package.request.method.caseInsensitiveCompare("GRPC") == .orderedSame
    }

    /// `notFound (code=5)` → 5. The SDK reports the status as a description, not a number.
    static func grpcStatusCode(from description: String) -> Int? {
        if let value = Int(description.trimmingCharacters(in: .whitespaces)) {
            return value
        }
        guard let range = description.range(of: "code=") else {
            return nil
        }
        return Int(description[range.upperBound...].prefix { $0.isNumber })
    }

    static func makeWebSocketFrame(from package: BabylonTrafficPackageDTO) throws -> WebSocketFrameData {
        guard let message = package.websocketMessagePackage else {
            throw BabylonCaptureMappingError.missingWebSocketMessage
        }
        let direction: FrameDirection = switch message.messageType {
        case .receive,
             .receiveCloseMessage,
             .pong:
            .received
        case .send,
             .sendCloseMessage,
             .pingPong,
             .ping,
             .unknown:
            .sent
        }
        let opcode: FrameOpcode
        let payload: Data
        switch message.messageType {
        case .sendCloseMessage,
             .receiveCloseMessage:
            opcode = .connectionClose
            payload = closePayload(message)
        case .pingPong,
             .ping:
            opcode = .ping
            payload = message.dataValue ?? Data((message.stringValue ?? "").utf8)
        case .pong:
            opcode = .pong
            payload = message.dataValue ?? Data((message.stringValue ?? "").utf8)
        case .send,
             .receive,
             .unknown:
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

    private static let grpcTrailerHeaderNames: Set<String> = [
        "grpc-status",
        "grpc-message",
        "grpc-status-details-bin",
    ]

    private static func makeGRPCTransaction(
        from package: BabylonTrafficPackageDTO,
        identity: BabylonCaptureIdentity
    )
        throws -> HTTPTransaction
    {
        if let capture = package.grpcCapture, capture.schemaVersion == 1 {
            return try makeTypedGRPCTransaction(capture, package: package, identity: identity)
        }
        try validateBody(package.request.body)
        try validateBody(package.responseBodyData)
        let path = package.request.url.hasPrefix("/") ? package.request.url : "/" + package.request.url
        let metadata = headers(package.request.headers)
        let authority = package.request.headers.first {
            [":authority", "host"].contains($0.name.lowercased())
        }?.value ?? "grpc.babylon"
        guard let url = grpcURL(authority: authority, endpoint: path) else {
            throw BabylonCaptureMappingError.invalidURL
        }

        var requestHeaders = metadata.filter { !$0.name.hasPrefix(":") }
        if !requestHeaders.contains(where: { $0.name.caseInsensitiveCompare("content-type") == .orderedSame }) {
            requestHeaders.insert(HTTPHeader(name: "content-type", value: "application/grpc"), at: 0)
        }
        let capturedRequestBody = capturedBody(package.request.body)
        let request = HTTPRequestData(
            method: "POST",
            url: url,
            httpVersion: "HTTP/2",
            headers: requestHeaders,
            body: capturedRequestBody.data.map { grpcFramed($0) },
            bodyTruncated: capturedRequestBody.wasOmitted || package.requestBodyOmission != nil,
            bodyOmission: omissionMetadata(package.requestBodyOmission),
            contentType: .protobuf
        )

        let response = package.response.map { response -> HTTPResponseData in
            let diagnostic = Set(["success", "statuscode", "statusmessage"])
            let all = headers(response.headers)
            let status = all.first { $0.name.lowercased() == "statuscode" }.flatMap { grpcStatusCode(from: $0.value) }
            let message = all.first { $0.name.lowercased() == "statusmessage" }?.value
            var trailers = [HTTPHeader(
                name: "grpc-status",
                value: String(status ?? (response.statusCode == 200 ? 0 : 2))
            )]
            if let message, message != "nil", !message.isEmpty {
                trailers.append(HTTPHeader(name: "grpc-message", value: message))
            }
            let responseBody = capturedBody(package.responseBodyData.isEmpty ? nil : package.responseBodyData)
            var data = HTTPResponseData(
                statusCode: 200,
                statusMessage: "OK",
                headers: [HTTPHeader(name: "content-type", value: "application/grpc")]
                    + all.filter { !diagnostic.contains($0.name.lowercased()) },
                body: responseBody.data.map { grpcFramed($0) },
                contentType: .protobuf
            )
            data.trailers = trailers
            data.bodyTruncated = responseBody.wasOmitted || package.responseBodyOmission != nil
            data.bodyOmission = omissionMetadata(package.responseBodyOmission)
            return data
        }

        let transaction = HTTPTransaction(
            timestamp: Date(timeIntervalSince1970: package.startAt),
            request: request,
            response: response,
            state: package.error == nil ? .completed : .failed,
            timingInfo: timing(for: package)
        )
        transaction.measuredDuration = duration(for: package)
        transaction.clientApp = identity.displayName
        transaction.serverHTTPVersion = "2"
        transaction.connectionLog = appReportedFailure(package.error, url: url)
        return transaction
    }

    private static func makeTypedGRPCTransaction(
        _ capture: BabylonTrafficPackageDTO.GRPCCapture,
        package: BabylonTrafficPackageDTO,
        identity: BabylonCaptureIdentity
    )
        throws -> HTTPTransaction
    {
        let authority = capture.authority ?? package.request.headers.first {
            [":authority", "host"].contains($0.key.lowercased())
        }?.value ?? "grpc.babylon"
        guard capture.endpoint.utf8.count <= ProxyLimits.maxURILength,
              capture.service.utf8.count <= 512,
              !capture.service.isEmpty,
              capture.method.utf8.count <= 256,
              !capture.method.isEmpty,
              let url = grpcURL(authority: authority, endpoint: capture.endpoint) else
        {
            throw BabylonCaptureMappingError.invalidURL
        }
        let requestMessages = capture.messages.filter { $0.direction == .request }.sorted {
            $0.sequence == $1.sequence ? $0.timestamp < $1.timestamp : $0.sequence < $1.sequence
        }
        let responseMessages = capture.messages.filter { $0.direction == .response }.sorted {
            $0.sequence == $1.sequence ? $0.timestamp < $1.timestamp : $0.sequence < $1.sequence
        }
        let (requestBody, requestMessageOmission) = try grpcMessageBody(requestMessages)
        let (responseBody, responseMessageOmission) = try grpcMessageBody(responseMessages)
        let requestOmission = omissionMetadata(package.requestBodyOmission) ?? requestMessageOmission
        let responseOmission = omissionMetadata(package.responseBodyOmission) ?? responseMessageOmission
        var requestHeaders = headers(capture.requestMetadata).filter {
            !$0.name.hasPrefix(":") && !Self.grpcTrailerHeaderNames.contains($0.name.lowercased())
        }
        if !requestHeaders.contains(where: { $0.name.caseInsensitiveCompare("content-type") == .orderedSame }) {
            requestHeaders.append(HTTPHeader(name: "content-type", value: "application/grpc"))
        }
        appendGRPCEncodingHeader(capture.requestCompression, to: &requestHeaders)
        let request = HTTPRequestData(
            method: "POST",
            url: url,
            httpVersion: "HTTP/2",
            headers: requestHeaders,
            body: requestBody,
            bodyTruncated: requestOmission != nil,
            bodyOmission: requestOmission,
            contentType: .protobuf
        )
        var response: HTTPResponseData?
        if package.response != nil || capture.statusCode != nil {
            var trailers = headers(capture.trailers)
            if !trailers.contains(where: { $0.name.caseInsensitiveCompare("grpc-status") == .orderedSame }),
               let statusCode = capture.statusCode
            {
                trailers.append(HTTPHeader(name: "grpc-status", value: String(statusCode)))
            }
            if !trailers.contains(where: { $0.name.caseInsensitiveCompare("grpc-message") == .orderedSame }),
               let statusMessage = capture.statusMessage,
               !statusMessage.isEmpty
            {
                trailers.append(HTTPHeader(name: "grpc-message", value: statusMessage))
            }
            var responseHeaders = headers(capture.responseMetadata).filter {
                !$0.name.hasPrefix(":") && !Self.grpcTrailerHeaderNames.contains($0.name.lowercased())
            }
            if !responseHeaders.contains(where: { $0.name.caseInsensitiveCompare("content-type") == .orderedSame }) {
                responseHeaders.append(HTTPHeader(name: "content-type", value: "application/grpc"))
            }
            appendGRPCEncodingHeader(capture.responseCompression, to: &responseHeaders)
            var value = HTTPResponseData(
                statusCode: 200,
                statusMessage: "OK",
                headers: responseHeaders,
                body: responseBody,
                contentType: .protobuf
            )
            value.trailers = trailers
            value.bodyTruncated = responseOmission != nil
            value.bodyOmission = responseOmission
            response = value
        }
        let transaction = HTTPTransaction(
            timestamp: Date(timeIntervalSince1970: package.startAt),
            request: request,
            response: response,
            state: package.error == nil ? .completed : .failed,
            timingInfo: timing(for: package)
        )
        transaction.measuredDuration = duration(for: package)
        transaction.clientApp = identity.displayName
        transaction.serverHTTPVersion = "2"
        transaction.connectionLog = appReportedFailure(package.error, url: url)
        transaction.babylonGRPCCallType = capture.callType.rawValue
        return transaction
    }

    private static func grpcMessageBody(
        _ messages: [BabylonTrafficPackageDTO.GRPCCapture.Message]
    )
        throws -> (Data?, BodyOmissionMetadata?)
    {
        var result = Data()
        var omitted = false
        var omittedObservedBytes = 0
        for message in messages {
            guard !message.omitted, let body = message.data else {
                omitted = true
                let reportedBytes = min(max(message.observedBytes, 0), 1_000_000_000)
                omittedObservedBytes = min(1_000_000_000, omittedObservedBytes + reportedBytes)
                continue
            }
            try validateBody(body)
            let isAlreadyFramed = body.count >= 5 && (body.first == 0 || body.first == 1)
                && body.dropFirst().prefix(4).reduce(0) { ($0 << 8) | Int($1) } == body.count - 5
            let framedSize = body.count + (isAlreadyFramed ? 0 : 5)
            guard framedSize <= BabylonCaptureProtocol.maximumCapturedBodySize - result.count else {
                throw BabylonCaptureMappingError.oversizedBody
            }
            result.append(isAlreadyFramed ? body : grpcFramed(body, compressed: message.compressed))
        }
        let omission = omitted
            ? BodyOmissionMetadata(
                reason: "grpcMessageOmitted",
                observedBytes: omittedObservedBytes,
                originalBytes: nil
            )
            : nil
        return (result.isEmpty ? nil : result, omission)
    }

    private static func grpcURL(authority: String, endpoint: String) -> URL? {
        guard endpoint.utf8.count <= ProxyLimits.maxURILength,
              endpoint.hasPrefix("/"),
              !endpoint.hasPrefix("//"),
              !endpoint.contains("?"),
              !endpoint.contains("#"),
              endpoint.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F }),
              let authorityURL = URL(string: "https://\(authority)"),
              var components = URLComponents(url: authorityURL, resolvingAgainstBaseURL: false),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil else
        {
            return nil
        }
        components.path = endpoint
        return components.url
    }

    private static func appendGRPCEncodingHeader(_ value: String?, to destination: inout [HTTPHeader]) {
        guard let value, !value.isEmpty,
              !destination.contains(where: { $0.name.caseInsensitiveCompare("grpc-encoding") == .orderedSame }),
              let header = headers([.init(key: "grpc-encoding", value: value)]).first else
        {
            return
        }
        destination.append(header)
    }

    /// Wraps a raw message in the 5-byte gRPC length prefix unless it already has one.
    private static func grpcFramed(_ message: Data, compressed: Bool = false) -> Data {
        if message.count >= 5, message.first == 0 || message.first == 1 {
            let length = message.dropFirst().prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            if length == message.count - 5 {
                return message
            }
        }
        var framed = Data([compressed ? 1 : 0])
        withUnsafeBytes(of: UInt32(message.count).bigEndian) { framed.append(contentsOf: $0) }
        framed.append(message)
        return framed
    }

    // MARK: Shared

    private static func makeResponse(
        statusCode: Int,
        headers responseHeaders: [HTTPHeader],
        body rawBody: Data,
        omission: BabylonTrafficPackageDTO.BodyOmission? = nil
    )
        throws -> HTTPResponseData
    {
        guard (100 ... 599).contains(statusCode) else {
            throw BabylonCaptureMappingError.invalidStatusCode
        }
        let body = capturedBody(rawBody.isEmpty ? nil : rawBody)
        var response = HTTPResponseData(
            statusCode: statusCode,
            statusMessage: HTTPReasonPhrase.standard(for: statusCode),
            headers: responseHeaders,
            body: body.data,
            contentType: ContentTypeDetector.detect(headers: responseHeaders, body: body.data)
        )
        response.bodyTruncated = body.wasOmitted || omission != nil
        response.bodyOmission = omissionMetadata(omission)
        return response
    }

    private static func omissionMetadata(
        _ omission: BabylonTrafficPackageDTO.BodyOmission?
    )
        -> BodyOmissionMetadata?
    {
        guard let omission,
              omission.observedBytes >= 0,
              omission.observedBytes <= 1_000_000_000,
              omission.originalBytes.map({ $0 >= omission.observedBytes && $0 <= 1_000_000_000 }) ?? true else
        {
            return nil
        }
        let reason = String(omission.reason.filter { $0.isASCII && !$0.isNewline }.prefix(128))
        guard !reason.isEmpty else {
            return nil
        }
        return BodyOmissionMetadata(
            reason: reason,
            observedBytes: omission.observedBytes,
            originalBytes: omission.originalBytes
        )
    }

    /// A body the SDK left out is recorded as missing and truncated, never as the marker text.
    private static func capturedBody(_ body: Data?) -> (data: Data?, wasOmitted: Bool) {
        guard let body else {
            return (nil, false)
        }
        if body == omittedBodyMarker {
            return (nil, true)
        }
        return (body, false)
    }

    private static func duration(for package: BabylonTrafficPackageDTO) -> TimeInterval {
        max(0, (package.endAt ?? package.startAt) - package.startAt)
    }

    private static func timing(for package: BabylonTrafficPackageDTO) -> TimingInfo {
        TimingInfo(
            dnsLookup: 0,
            tcpConnection: 0,
            tlsHandshake: 0,
            timeToFirstByte: 0,
            contentTransfer: duration(for: package)
        )
    }

    /// The error the app's networking stack reported (a timeout, a cancelled task), kept instead
    /// of only flipping the row to failed.
    private static func appReportedFailure(
        _ error: BabylonTrafficPackageDTO.CapturedError?,
        url: URL
    )
        -> ConnectionLog?
    {
        guard let error else {
            return nil
        }
        let defaultPort = ["https", "wss"].contains(url.scheme?.lowercased() ?? "") ? 443 : 80
        let message = String(error.message.prefix(1_024))
        let context = [error.domain, error.phase].compactMap { $0 }.joined(separator: "; ")
        let description = context.isEmpty
            ? "The app reported error \(error.code): \(message)"
            : "The app reported error \(error.code) (\(context)): \(message)"
        return ConnectionLog(
            host: url.host ?? "",
            port: url.port ?? defaultPort,
            failure: ConnectionLog.Failure(
                stage: .response,
                message: description
            )
        )
    }

    /// A close frame's payload is the 2-byte status code followed by the reason, as on the wire.
    private static func closePayload(_ message: BabylonTrafficPackageDTO.WebSocketMessage) -> Data {
        guard let code = message.closeCode, (0 ... Int(UInt16.max)).contains(code) else {
            return message.dataValue ?? Data((message.stringValue ?? "").utf8)
        }
        var payload = Data()
        withUnsafeBytes(of: UInt16(code).bigEndian) { payload.append(contentsOf: $0) }
        payload.append(Data((message.closeReason ?? message.stringValue ?? "").utf8.prefix(123)))
        return payload
    }

    private static func headers(_ values: [BabylonTrafficPackageDTO.Header]) -> [HTTPHeader] {
        values.prefix(1_024).compactMap { value in
            let name = boundedBabylonString(value.key.trimmingCharacters(in: .whitespaces), bytes: 1_024)
            let headerValue = boundedBabylonString(value.value, bytes: 32_768)
            guard !name.isEmpty,
                  name.unicodeScalars.allSatisfy(isValidHeaderNameScalar),
                  headerValue.unicodeScalars.allSatisfy(isValidHeaderValueScalar) else
            {
                return nil
            }
            return HTTPHeader(name: name, value: headerValue)
        }
    }

    private static func isValidHeaderNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value > 0x20, scalar.value != 0x7F else {
            return false
        }
        guard scalar.value <= 0x7E else {
            return false
        }
        return !"()<>@,;:\\\"/[]?={} \t".unicodeScalars.contains(scalar)
    }

    private static func isValidHeaderValueScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x09 || (scalar.value >= 0x20 && scalar.value != 0x7F)
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
