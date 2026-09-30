import Foundation

// MARK: - ConnectionLogFormatter

/// Turns a recorded exchange into `curl -v`-style lines: `*` for connection events, `>` for
/// what was sent to the server and `<` for what came back. The log is a technical transcript
/// like the Raw tab, so its lines are not localized.
enum ConnectionLogFormatter {
    // MARK: Internal

    struct Input: Sendable {
        // MARK: Lifecycle

        @MainActor
        init(transaction: HTTPTransaction) {
            log = transaction.connectionLog
            request = transaction.request
            response = transaction.response
            serverHTTPVersion = transaction.serverHTTPVersion
            localResponder = transaction.connectionLog == nil ? transaction.matchedRuleActionSummary : nil
            isTunnel = transaction.request.method.uppercased() == "CONNECT"
        }

        init(
            log: ConnectionLog?,
            request: HTTPRequestData,
            response: HTTPResponseData?,
            serverHTTPVersion: String? = nil,
            localResponder: String? = nil,
            isTunnel: Bool = false
        ) {
            self.log = log
            self.request = request
            self.response = response
            self.serverHTTPVersion = serverHTTPVersion
            self.localResponder = localResponder
            self.isTunnel = isTunnel
        }

        // MARK: Internal

        let log: ConnectionLog?
        let request: HTTPRequestData
        let response: HTTPResponseData?
        let serverHTTPVersion: String?
        /// Set when a rule answered the request without contacting the server.
        let localResponder: String?
        let isTunnel: Bool
    }

    static func lines(for input: Input) -> [ConnectionLogLine] {
        var lines: [ConnectionLogLine] = []
        if let log = input.log {
            appendConnection(log, to: &lines)
            if let tls = log.tls {
                appendTLS(tls, failed: log.failure?.stage == .tls, to: &lines)
            }
            if log.failure?.stage != .connect, log.failure?.stage != .proxy, !input.isTunnel {
                lines.append(event("Using \(protocolName(input.serverHTTPVersion))"))
            }
        } else if let responder = input.localResponder, input.response != nil {
            lines.append(event("No connection to the server: the response came from \(responder)", role: .note))
        } else {
            lines.append(event("Connection details were not recorded for this request", role: .note))
        }

        if !input.isTunnel {
            appendRequest(input.request, version: requestVersion(input), to: &lines)
            if let response = input.response, input.log?.failure == nil || response.statusCode < 500 {
                appendResponse(response, version: requestVersion(input), to: &lines)
            }
        }

        if let failure = input.log?.failure {
            lines.append(event(failure.message, role: .failure))
            lines.append(contentsOf: failure.attempts.map { event("  \($0)", role: .failure) })
        }
        return lines
    }

    static func plainText(for input: Input) -> String {
        lines(for: input).map(\.rendered).joined(separator: "\n")
    }

    // MARK: Private

    private static let certificateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy 'GMT'"
        return formatter
    }()

    private static func appendConnection(_ log: ConnectionLog, to lines: inout [ConnectionLogLine]) {
        lines.append(event("Host \(log.host) port \(log.port)", role: .host))
        if let connectHost = log.connectHost {
            lines.append(event("Connecting to \(connectHost) instead of \(log.host)", role: .warning))
        }
        switch log.route {
        case .direct:
            if log.routeChosenByPAC {
                lines.append(event("Proxy auto-configuration chose a direct connection"))
            }
        case let .externalProxy(kind, host, port):
            let origin = log.routeChosenByPAC ? " (chosen by proxy auto-configuration)" : ""
            lines.append(event("Using external \(kind) proxy \(host) port \(port)\(origin)", role: .host))
        }
        if let address = log.remoteAddress {
            let port = log.remotePort.map { " port \($0)" } ?? ""
            let elapsed = log.connectDuration.map { " in \(milliseconds($0))" } ?? ""
            lines.append(event("Connected to \(address)\(port)\(elapsed)", role: .success))
        }
        if let local = log.localAddress {
            let port = log.localPort.map { " port \($0)" } ?? ""
            lines.append(event("Local address \(local)\(port)"))
        }
    }

    private static func appendTLS(_ tls: ConnectionLog.TLS, failed: Bool, to lines: inout [ConnectionLogLine]) {
        if let serverName = tls.serverName {
            lines.append(event("TLS server name (SNI): \(serverName)", role: .tls))
        } else {
            lines.append(event("TLS server name (SNI): not sent for an IP address", role: .tls))
        }
        if tls.offeredProtocols.isEmpty {
            lines.append(event("ALPN: not offered (HTTP/1.1)", role: .tls))
        } else {
            lines.append(event("ALPN: offering \(tls.offeredProtocols.joined(separator: ", "))", role: .tls))
        }
        if !failed, tls.version != nil {
            let elapsed = tls.handshakeDuration.map { " in \(milliseconds($0))" } ?? ""
            lines.append(event("TLS handshake completed\(elapsed)", role: .success))
        }
        if let version = tls.version {
            lines.append(event("SSL connection using \(version)", role: .tls))
        }
        if let negotiated = tls.negotiatedProtocol {
            lines.append(event("ALPN: server accepted \(negotiated)", role: .tls))
        }
        if let certificate = tls.certificate {
            lines.append(event("Server certificate:"))
            lines.append(event(" subject: \(certificate.subject)"))
            lines.append(event(" issuer: \(certificate.issuer)"))
            if let start = certificate.notValidBefore {
                lines.append(event(" start date: \(certificateDateFormatter.string(from: start))"))
            }
            if let end = certificate.notValidAfter {
                let expired = end < Date()
                lines.append(event(
                    " expire date: \(certificateDateFormatter.string(from: end))\(expired ? " (expired)" : "")",
                    role: expired ? .warning : .event
                ))
            }
            if !certificate.alternativeNames.isEmpty {
                lines.append(event(" subjectAltName: \(certificate.alternativeNames.joined(separator: ", "))"))
            }
        }
        switch tls.verification {
        case .verified:
            lines.append(event("Certificate verification: OK", role: .success))
        case .hostnameSkipped:
            lines.append(event("Certificate verification: chain OK", role: .success))
            lines.append(event("Hostname verification: not performed (IP address)", role: .warning))
        case .disabled:
            lines.append(event(
                "Certificate verification disabled (untrusted server certificates are accepted)",
                role: .warning
            ))
        case nil:
            break
        }
    }

    private static func appendRequest(
        _ request: HTTPRequestData,
        version: String,
        to lines: inout [ConnectionLogLine]
    ) {
        var target = request.url.path(percentEncoded: true)
        if target.isEmpty {
            target = "/"
        }
        if let query = request.url.query(percentEncoded: true) {
            target += "?\(query)"
        }
        lines.append(ConnectionLogLine(
            marker: ">",
            text: "\(request.method) \(target) \(version)",
            role: .requestHeader
        ))
        for header in request.headers {
            lines.append(ConnectionLogLine(marker: ">", text: "\(header.name): \(header.value)", role: .requestHeader))
        }
        lines.append(ConnectionLogLine(marker: ">", text: "", role: .requestHeader))
        if let body = request.body, !body.isEmpty {
            lines.append(event("Request body: \(SizeFormatter.format(bytes: body.count))"))
        }
    }

    private static func appendResponse(
        _ response: HTTPResponseData,
        version: String,
        to lines: inout [ConnectionLogLine]
    ) {
        let reason = response.statusMessage.isEmpty ? "" : " \(response.statusMessage)"
        lines.append(ConnectionLogLine(
            marker: "<",
            text: "\(version) \(response.statusCode)\(reason)",
            role: .responseHeader
        ))
        for header in response.headers {
            lines.append(ConnectionLogLine(marker: "<", text: "\(header.name): \(header.value)", role: .responseHeader))
        }
        lines.append(ConnectionLogLine(marker: "<", text: "", role: .responseHeader))
        if let body = response.body, !body.isEmpty {
            let note = response.bodyTruncated ? " (only the first part was kept)" : ""
            lines.append(event("Response body: \(SizeFormatter.format(bytes: body.count))\(note)"))
        }
        for trailer in response.trailers ?? [] {
            lines.append(ConnectionLogLine(
                marker: "<",
                text: "\(trailer.name): \(trailer.value)",
                role: .responseHeader
            ))
        }
    }

    private static func requestVersion(_ input: Input) -> String {
        if let server = input.serverHTTPVersion {
            return server == "2" ? "HTTP/2" : "HTTP/\(server)"
        }
        return input.request.httpVersion
    }

    private static func protocolName(_ serverVersion: String?) -> String {
        switch serverVersion {
        case "2": "HTTP/2"
        case let version?: "HTTP/\(version)"
        case nil: "HTTP/1.1"
        }
    }

    private static func milliseconds(_ seconds: TimeInterval) -> String {
        "\(Int((seconds * 1_000).rounded())) ms"
    }

    private static func event(_ text: String, role: ConnectionLogLine.Role = .event) -> ConnectionLogLine {
        ConnectionLogLine(marker: "*", text: text, role: role)
    }
}
