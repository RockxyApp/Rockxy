import Foundation

final class StdioBridge {
    // MARK: Lifecycle

    // MARK: - Initialization

    init(token: String, port: Int) {
        self.token = token
        self.port = port

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config)
        baseURL = Self.makeBaseURL(for: port)
    }

    // MARK: Internal

    func run() {
        let stdin = FileHandle.standardInput

        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                break
            }
            inputBuffer.append(chunk)

            if inputBuffer.count > Self.maxLineSize {
                writeResponse(makeJSONErrorResponse(
                    code: -32_700,
                    message: "input line too large"
                ))
                inputBuffer.removeAll(keepingCapacity: false)
                continue
            }

            while let newlineRange = inputBuffer.range(of: Data("\n".utf8)) {
                let lineData = inputBuffer.subdata(in: inputBuffer.startIndex ..< newlineRange.lowerBound)
                inputBuffer.removeSubrange(inputBuffer.startIndex ... newlineRange.lowerBound)

                guard let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !line.isEmpty else
                {
                    continue
                }

                if let responseData = sendRequest(body: Data(line.utf8)) {
                    writeResponse(responseData)
                }
            }
        }

        // Process any remaining data without trailing newline
        if !inputBuffer.isEmpty,
           let line = String(data: inputBuffer, encoding: .utf8)?
           .trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty
        {
            if let responseData = sendRequest(body: Data(line.utf8)) {
                writeResponse(responseData)
            }
        }

        exit(0)
    }

    // MARK: Private

    private struct HTTPCallResult {
        let data: Data?
        let response: HTTPURLResponse?
        let error: Error?
    }

    private struct ParsedRequest {
        let methodName: String?
        let toolName: String?
    }

    private static let fallbackProtocolVersion = "2025-11-25"
    private static let maxLineSize = 4 * 1_024 * 1_024

    private var token: String
    private var port: Int
    private let session: URLSession
    private var baseURL: URL
    private var inputBuffer = Data()
    private var sessionId: String?
    private var negotiatedProtocolVersion: String?
    private var lastInitializeRequestBody: Data?

    private static func makeBaseURL(for port: Int) -> URL {
        guard let url = URL(string: "http://127.0.0.1:\(port)/mcp") else {
            FileHandle.standardError.write(Data("Error: invalid MCP server URL\n".utf8))
            exit(1)
        }
        return url
    }

    private func sendRequest(body: Data) -> Data? {
        let parsedRequest = parseRequest(from: body)
        let methodName = jsonRpcMethod(from: parsedRequest)
        if methodName == "initialize" {
            lastInitializeRequestBody = body
        }
        let isIdempotentRequest = isIdempotentMethod(methodName, parsedBody: parsedRequest)

        var call = performHTTP(body: body, methodName: methodName)
        updateSessionState(from: call, requestMethod: methodName)

        if shouldRefreshHandshake(from: call),
           refreshHandshake()
        {
            call = performHTTP(body: body, methodName: methodName)
            updateSessionState(from: call, requestMethod: methodName)
        }

        if isIdempotentRequest,
           shouldRecoverSession(from: call, requestMethod: methodName),
           recoverSession()
        {
            call = performHTTP(body: body, methodName: methodName)
            updateSessionState(from: call, requestMethod: methodName)
        }

        if let error = call.error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCannotConnectToHost {
                FileHandle.standardError.write(
                    Data("Error: cannot connect to Rockxy on port \(port). Is the app running with MCP enabled?\n".utf8)
                )
            }
            return makeErrorResponse(message: error.localizedDescription)
        }

        let statusCode = call.response?.statusCode ?? 0
        if methodName == "notifications/initialized",
           (200 ..< 300).contains(statusCode),
           call.data?.isEmpty ?? true
        {
            return nil
        }

        guard let data = call.data, !data.isEmpty else {
            return makeErrorResponse(message: "empty response from Rockxy MCP server")
        }

        return data
    }

    private func performHTTP(body: Data, methodName: String?) -> HTTPCallResult {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if methodName != "initialize" {
            request.setValue(
                negotiatedProtocolVersion ?? Self.fallbackProtocolVersion,
                forHTTPHeaderField: "MCP-Protocol-Version"
            )
        }
        if let sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = body

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var httpResponse: HTTPURLResponse?

        let task = session.dataTask(with: request) { data, response, error in
            responseData = data
            responseError = error
            httpResponse = response as? HTTPURLResponse
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return HTTPCallResult(
            data: responseData,
            response: httpResponse,
            error: responseError
        )
    }

    private func writeResponse(_ data: Data) {
        let stdout = FileHandle.standardOutput
        stdout.write(data)
        stdout.write(Data("\n".utf8))

        // Force flush stdout for non-TTY consumers (MCP client subprocesses)
        fflush(Foundation.stdout)
    }

    private func makeErrorResponse(message: String) -> Data {
        makeJSONErrorResponse(code: -32_000, message: message)
    }

    private func updateSessionState(from call: HTTPCallResult, requestMethod: String?) {
        if let sid = call.response?.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionId = sid
        }

        if requestMethod == "initialize" {
            negotiatedProtocolVersion = protocolVersion(from: call.data) ?? Self.fallbackProtocolVersion
        }
    }

    private func shouldRecoverSession(from call: HTTPCallResult, requestMethod: String?) -> Bool {
        guard requestMethod != nil, requestMethod != "initialize" else {
            return false
        }
        guard call.error == nil else {
            return false
        }
        guard let statusCode = call.response?.statusCode,
              statusCode == 400 || statusCode == 404 else
        {
            return false
        }
        guard let text = call.data.flatMap({ String(data: $0, encoding: .utf8) }) else {
            return false
        }

        return text.contains("Invalid or expired session") || text.contains("Missing Mcp-Session-Id")
    }

    private func shouldRefreshHandshake(from call: HTTPCallResult) -> Bool {
        if let error = call.error as NSError? {
            let transientCodes = [
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorNetworkConnectionLost,
            ]
            return error.domain == NSURLErrorDomain && transientCodes.contains(error.code)
        }

        return call.response?.statusCode == 401
    }

    private func recoverSession() -> Bool {
        guard let initializeBody = lastInitializeRequestBody else {
            return false
        }

        sessionId = nil
        negotiatedProtocolVersion = nil

        let call = performHTTP(body: initializeBody, methodName: "initialize")
        updateSessionState(from: call, requestMethod: "initialize")

        guard call.error == nil,
              let statusCode = call.response?.statusCode,
              (200 ..< 300).contains(statusCode),
              sessionId != nil else
        {
            return false
        }

        return true
    }

    private func refreshHandshake() -> Bool {
        guard let handshake = try? HandshakeReader.readHandshake() else {
            return false
        }

        let url = Self.makeBaseURL(for: handshake.port)
        let changed = handshake.token != token || handshake.port != port
        guard changed else {
            return false
        }

        token = handshake.token
        port = handshake.port
        baseURL = url
        sessionId = nil
        negotiatedProtocolVersion = nil

        return changed
    }

    private func parseRequest(from body: Data) -> ParsedRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        return ParsedRequest(
            methodName: object["method"] as? String,
            toolName: (object["params"] as? [String: Any])?["name"] as? String
        )
    }

    private func jsonRpcMethod(from parsedRequest: ParsedRequest?) -> String? {
        parsedRequest?.methodName
    }

    private func isIdempotentMethod(_ methodName: String?, parsedBody: ParsedRequest?) -> Bool {
        switch methodName {
        case "notifications/initialized",
             "tools/list",
             "ping":
            return true
        case "tools/call":
            guard let toolName = parsedBody?.toolName else {
                return false
            }

            let idempotentTools: Set = [
                "get_version",
                "get_proxy_status",
                "get_certificate_status",
                "get_recent_flows",
                "get_flow_detail",
                "search_flows",
                "filter_flows",
                "export_flow_curl",
                "list_rules",
                "get_ssl_proxying_list",
            ]
            return idempotentTools.contains(toolName)
        default:
            return false
        }
    }

    private func makeJSONErrorResponse(code: Int, message: String) -> Data {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message,
            ],
            "id": NSNull(),
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            return data
        }

        return Data(#"{"jsonrpc":"2.0","error":{"code":-32000,"message":"Internal bridge error"},"id":null}"#.utf8)
    }

    private func protocolVersion(from data: Data?) -> String? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let protocolVersion = result["protocolVersion"] as? String,
              !protocolVersion.isEmpty else
        {
            return nil
        }
        return protocolVersion
    }
}
