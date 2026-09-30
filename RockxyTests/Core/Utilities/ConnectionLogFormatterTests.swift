import AppKit
import Darwin
import Foundation
import NIOCore
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - ConnectionLogFormatterTests

struct ConnectionLogFormatterTests {
    // MARK: Internal

    @Test("A decrypted exchange lists the address, TLS session, certificate and both header blocks")
    func decryptedExchange() {
        var log = ConnectionLog(host: "api.example.com", port: 443)
        log.remoteAddress = "93.184.216.34"
        log.remotePort = 443
        log.connectDuration = 0.023
        log.tls = ConnectionLog.TLS(
            serverName: "api.example.com",
            offeredProtocols: ["h2", "http/1.1"],
            negotiatedProtocol: "h2",
            version: "TLSv1.3",
            handshakeDuration: 0.041,
            verification: .verified,
            certificate: ConnectionLog.Certificate(
                subject: "CN=api.example.com",
                issuer: "CN=R11,O=Let's Encrypt,C=US",
                alternativeNames: ["api.example.com", "*.example.com"],
                notValidBefore: Date(timeIntervalSince1970: 1_780_000_000),
                notValidAfter: Date(timeIntervalSince1970: 4_000_000_000),
                serialNumber: "01"
            )
        )
        let text = ConnectionLogFormatter.plainText(for: input(log: log, serverHTTPVersion: "2"))

        #expect(text.contains("* Host api.example.com port 443"))
        #expect(text.contains("* Connected to 93.184.216.34 port 443 in 23 ms"))
        #expect(text.contains("* ALPN: offering h2, http/1.1"))
        #expect(text.contains("* TLS handshake completed in 41 ms"))
        #expect(text.contains("* SSL connection using TLSv1.3"))
        #expect(text.contains("* ALPN: server accepted h2"))
        #expect(text.contains("*  subject: CN=api.example.com"))
        #expect(text.contains("*  subjectAltName: api.example.com, *.example.com"))
        #expect(text.contains("* Certificate verification: OK"))
        #expect(text.contains("* Using HTTP/2"))
        #expect(text.contains("> GET /v1/items?page=2 HTTP/2"))
        #expect(text.contains("> Accept: application/json"))
        #expect(text.contains("< HTTP/2 200 OK"))
        #expect(text.contains("< Content-Type: application/json"))
        #expect(text.contains("* Response body: "))
    }

    @Test("Certificate dates render in GMT regardless of the user's locale")
    func certificateDatesAreGMT() {
        var log = ConnectionLog(host: "a.test", port: 443)
        log.tls = ConnectionLog.TLS(
            version: "TLSv1.2",
            certificate: ConnectionLog.Certificate(
                subject: "CN=a.test",
                issuer: "CN=a.test",
                alternativeNames: [],
                notValidBefore: Date(timeIntervalSince1970: 0),
                notValidAfter: Date(timeIntervalSince1970: 86_400),
                serialNumber: nil
            )
        )
        let text = ConnectionLogFormatter.plainText(for: input(log: log))
        #expect(text.contains("*  start date: Jan 1 00:00:00 1970 GMT"))
        #expect(text.contains("*  expire date: Jan 2 00:00:00 1970 GMT (expired)"))
    }

    @Test("External proxy routes, address overrides and relaxed trust are called out")
    func routeAndWarnings() {
        var log = ConnectionLog(host: "api.example.com", port: 443)
        log.connectHost = "127.0.0.1"
        log.route = .externalProxy(kind: "HTTP", host: "proxy.corp", port: 8_080)
        log.routeChosenByPAC = true
        log.tls = ConnectionLog.TLS(serverName: "api.example.com", version: "TLSv1.2", verification: .disabled)
        let lines = ConnectionLogFormatter.lines(for: input(log: log))

        #expect(lines.contains(ConnectionLogLine(
            marker: "*",
            text: "Connecting to 127.0.0.1 instead of api.example.com",
            role: .warning
        )))
        #expect(lines.contains {
            $0.text == "Using external HTTP proxy proxy.corp port 8080 (chosen by proxy auto-configuration)"
        })
        #expect(lines.contains { $0.role == .warning && $0.text.hasPrefix("Certificate verification disabled") })
        #expect(lines.contains { $0.text == "ALPN: not offered (HTTP/1.1)" })
    }

    @Test("A failed connection lists every attempt and does not invent a server response")
    func failureListsAttempts() {
        var log = ConnectionLog(host: "down.test", port: 8_443)
        log.failure = ConnectionLog.Failure(
            stage: .connect,
            message: "Failed to connect to down.test port 8443",
            attempts: [
                "::1 port 8443: Connection refused (errno 61)",
                "127.0.0.1 port 8443: Connection refused (errno 61)"
            ]
        )
        let synthetic = HTTPResponseData(statusCode: 502, statusMessage: "Bad Gateway", headers: [])
        let lines = ConnectionLogFormatter.lines(for: input(log: log, response: synthetic))

        #expect(lines.last == ConnectionLogLine(
            marker: "*",
            text: "  127.0.0.1 port 8443: Connection refused (errno 61)",
            role: .failure
        ))
        #expect(lines.contains { $0.role == .failure && $0.text == "Failed to connect to down.test port 8443" })
        #expect(!lines.contains { $0.marker == "<" })
        #expect(!lines.contains { $0.text.hasPrefix("Using HTTP") })
    }

    @Test("Rows without a recorded connection say why instead of showing an empty log")
    func missingLogExplained() {
        let local = ConnectionLogFormatter.lines(for: input(log: nil, localResponder: "Map Local ▸ users.json"))
        #expect(local.first?.text == "No connection to the server: the response came from Map Local ▸ users.json")

        let older = ConnectionLogFormatter.lines(for: input(log: nil))
        #expect(older.first?.text == "Connection details were not recorded for this request")
        #expect(older.contains { $0.marker == ">" })
    }

    @Test("Header rows color the name; request lines stay plain")
    func headerNamesAreColored() {
        let lines = [
            ConnectionLogLine(marker: ">", text: "GET /a:b HTTP/1.1", role: .requestHeader),
            ConnectionLogLine(marker: ">", text: "Accept: */*", role: .requestHeader),
        ]
        let text = ConnectionLogTextView.attributedText(for: lines, fontSize: 12)
        let requestLine = (text.string as NSString).range(of: "GET")
        let headerName = (text.string as NSString).range(of: "Accept")
        let requestColor = text.attribute(.foregroundColor, at: requestLine.location, effectiveRange: nil) as? NSColor
        let nameColor = text.attribute(.foregroundColor, at: headerName.location, effectiveRange: nil) as? NSColor
        #expect(requestColor == NSColor.labelColor)
        #expect(nameColor == Theme.ConnectionLog.headerNameNS)
        #expect(text.string == "> GET /a:b HTTP/1.1\n> Accept: */*")
    }

    @Test("Sessions keep the connection log and older files without it still open")
    func sessionRoundTrip() throws {
        let transaction = HTTPTransaction(request: Self.request, response: nil, state: .completed)
        var log = ConnectionLog(host: "api.example.com", port: 443)
        log.remoteAddress = "10.0.0.8"
        log.failure = ConnectionLog.Failure(stage: .tls, message: "TLS handshake failed: x", attempts: [])
        transaction.connectionLog = log

        let data = try JSONEncoder().encode(CodableTransaction(from: transaction))
        let decoded = try JSONDecoder().decode(CodableTransaction.self, from: data).toLiveModel()
        #expect(decoded.connectionLog == log)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "connectionLog")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(CodableTransaction.self, from: legacy).toLiveModel().connectionLog == nil)
    }

    @Test("Redaction drops the capturing machine's local address")
    func redactionDropsLocalAddress() {
        let transaction = HTTPTransaction(request: Self.request, response: nil, state: .completed)
        var log = ConnectionLog(host: "api.example.com", port: 443)
        log.remoteAddress = "93.184.216.34"
        log.localAddress = "192.168.1.20"
        log.localPort = 55_123
        transaction.connectionLog = log

        let redacted = SensitiveDataRedactor().redactTransaction(transaction)
        #expect(redacted.connectionLog?.remoteAddress == "93.184.216.34")
        #expect(redacted.connectionLog?.localAddress == nil)
        #expect(redacted.connectionLog?.localPort == nil)
    }

    @Test("A refused connection is described with the address tried and the OS reason")
    func refusedConnectionDescribed() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let port = try Self.closedLoopbackPort()

        do {
            let channel = try await UpstreamProxyConnector.directConnect(
                eventLoop: group.next(),
                targetHost: "127.0.0.1",
                targetPort: port
            ) { $0.eventLoop.makeSucceededVoidFuture() }.get()
            try await channel.close()
            Issue.record("expected the connection to be refused")
        } catch {
            let failure = ConnectionLogCapture.failure(for: error)
            #expect(failure.stage == .connect)
            #expect(failure.message == "Failed to connect to 127.0.0.1 port \(port)")
            #expect(failure.attempts == ["127.0.0.1 port \(port): Connection refused (errno 61)"])
        }
    }

    // MARK: Private

    private static let request = HTTPRequestData(
        method: "GET",
        url: URL(string: "https://api.example.com/v1/items?page=2")!,
        httpVersion: "HTTP/1.1",
        headers: [HTTPHeader(name: "Accept", value: "application/json")]
    )

    private static func closedLoopbackPort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, length) == 0 && getsockname(socket, $0, &length) == 0
            }
        }
        guard bound else {
            throw POSIXError(.EADDRINUSE)
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func input(
        log: ConnectionLog?,
        response: HTTPResponseData? = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data("{}".utf8)
        ),
        serverHTTPVersion: String? = nil,
        localResponder: String? = nil
    )
        -> ConnectionLogFormatter.Input
    {
        ConnectionLogFormatter.Input(
            log: log,
            request: Self.request,
            response: response,
            serverHTTPVersion: serverHTTPVersion,
            localResponder: localResponder
        )
    }
}
