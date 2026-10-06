import Darwin
import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSL
import SwiftASN1
import X509

// MARK: - UpstreamConnectionProbe

/// Marks an upstream socket with how and when it was opened, for the response handler to read
/// when it assembles the Connection Log. NIO only accepts inbound or outbound handlers, so it
/// is a pass-through outbound handler next to the head: reads never visit it, and writes take
/// one forwarding hop.
nonisolated final class UpstreamConnectionProbe: ChannelOutboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    private init(
        targetHost: String,
        route: ConnectionLog.Route,
        routeChosenByPAC: Bool,
        startedAt: DispatchTime,
        connectedAt: DispatchTime
    ) {
        self.targetHost = targetHost
        self.route = route
        self.routeChosenByPAC = routeChosenByPAC
        self.startedAt = startedAt
        self.connectedAt = connectedAt
    }

    // MARK: Internal

    typealias OutboundIn = NIOAny

    /// The host Rockxy dialled (or asked the external proxy to reach).
    let targetHost: String
    let route: ConnectionLog.Route
    let routeChosenByPAC: Bool
    let startedAt: DispatchTime
    let connectedAt: DispatchTime
    /// Set by the ALPN step when the channel is handed over only after the TLS handshake.
    var tlsHandshakeCompletedAt: DispatchTime?
    var negotiatedProtocol: String?

    static func install(
        on channel: Channel,
        targetHost: String,
        route: ConnectionLog.Route,
        routeChosenByPAC: Bool,
        startedAt: DispatchTime,
        connectedAt: DispatchTime
    ) {
        let probe = UpstreamConnectionProbe(
            targetHost: targetHost,
            route: route,
            routeChosenByPAC: routeChosenByPAC,
            startedAt: startedAt,
            connectedAt: connectedAt
        )
        if channel.eventLoop.inEventLoop {
            try? channel.pipeline.syncOperations.addHandler(probe, position: .first)
        } else {
            channel.pipeline.addHandler(probe, position: .first).whenFailure { _ in }
        }
    }

    /// The probe of `channel`, or of its parent connection for an HTTP/2 stream.
    static func find(on channel: Channel) -> UpstreamConnectionProbe? {
        guard channel.eventLoop.inEventLoop else {
            return nil
        }
        if let probe = try? channel.pipeline.syncOperations.handler(type: UpstreamConnectionProbe.self) {
            return probe
        }
        guard let parent = channel.parent else {
            return nil
        }
        return try? parent.pipeline.syncOperations.handler(type: UpstreamConnectionProbe.self)
    }
}

// MARK: - UpstreamTLSIntent

/// What Rockxy asked for when it opened a TLS connection to the server.
struct UpstreamTLSIntent: Sendable {
    let offeredProtocols: [String]
    let acceptsUntrustedCertificates: Bool
}

// MARK: - ConnectionLogCapture

nonisolated enum ConnectionLogCapture {
    // MARK: Internal

    /// Builds the log for an upstream channel that carried the exchange. Must run on the
    /// channel's event loop: NIOSSL's session accessors are not thread safe.
    static func log(
        for channel: Channel,
        host: String,
        port: Int,
        tlsIntent: UpstreamTLSIntent?,
        handshakeDuration: TimeInterval?,
        negotiatedProtocol: String?,
        failure: ConnectionLog.Failure? = nil
    )
        -> ConnectionLog
    {
        var log = ConnectionLog(host: host, port: port)
        let connection = channel.parent ?? channel
        if let probe = UpstreamConnectionProbe.find(on: channel) {
            log.connectHost = probe.targetHost == host ? nil : probe.targetHost
            log.route = probe.route
            log.routeChosenByPAC = probe.routeChosenByPAC
            log.connectDuration = seconds(from: probe.startedAt, to: probe.connectedAt)
        }
        if let remote = connection.remoteAddress {
            log.remoteAddress = remote.ipAddress
            log.remotePort = remote.port
        }
        if let local = connection.localAddress {
            log.localAddress = local.ipAddress
            log.localPort = local.port
        }
        if let tlsIntent {
            log.tls = tlsDetails(
                on: connection,
                host: host,
                intent: tlsIntent,
                handshakeDuration: handshakeDuration,
                negotiatedProtocol: negotiatedProtocol ?? (channel.parent == nil ? nil : "h2"),
                failed: failure?.stage == .tls
            )
        }
        log.failure = failure
        return log
    }

    /// The log for a connection that never opened, described from the connect error.
    static func failedConnection(host: String, port: Int, connectHost: String, error: Error) -> ConnectionLog {
        var log = ConnectionLog(host: host, port: port)
        log.connectHost = connectHost == host ? nil : connectHost
        log.failure = failure(for: error)
        return log
    }

    /// Wraps a transaction callback so the delivered row carries the failed-connection log.
    static func attachingFailure(
        _ error: Error,
        host: String,
        port: Int,
        connectHost: String,
        to callback: @escaping @Sendable (HTTPTransaction) -> Void
    )
        -> @Sendable (HTTPTransaction) -> Void
    {
        let log = failedConnection(host: host, port: port, connectHost: connectHost, error: error)
        return { transaction in
            transaction.connectionLog = log
            callback(transaction)
        }
    }

    static func failure(for error: Error) -> ConnectionLog.Failure {
        if let connectionError = error as? NIOConnectionError {
            if connectionError.connectionErrors.isEmpty,
               let dnsError = connectionError.dnsAError ?? connectionError.dnsAAAAError
            {
                return ConnectionLog.Failure(
                    stage: .connect,
                    message: "Could not resolve host \(connectionError.host): \(describe(dnsError))"
                )
            }
            let attempts = connectionError.connectionErrors.map {
                "\($0.target.ipAddress ?? "?") port \($0.target.port ?? connectionError.port): \(describe($0.error))"
            }
            return ConnectionLog.Failure(
                stage: .connect,
                message: "Failed to connect to \(connectionError.host) port \(connectionError.port)",
                attempts: attempts
            )
        }
        if let channelError = error as? ChannelError, case let .connectTimeout(amount) = channelError {
            let millis = amount.nanoseconds / 1_000_000
            return ConnectionLog.Failure(stage: .connect, message: "Connection timed out after \(millis) ms")
        }
        if error is UpstreamProxyError {
            return ConnectionLog.Failure(stage: .proxy, message: "External proxy: \(error.localizedDescription)")
        }
        if error is NIOSSLError || error is BoringSSLError || error is NIOSSLExtraError {
            return ConnectionLog.Failure(stage: .tls, message: "TLS handshake failed: \(describe(error))")
        }
        if let ioError = error as? IOError {
            return ConnectionLog.Failure(stage: .connect, message: describe(ioError))
        }
        return ConnectionLog.Failure(stage: .response, message: describe(error))
    }

    static func versionName(_ version: TLSVersion) -> String {
        switch version {
        case .tlsv1: "TLSv1.0"
        case .tlsv11: "TLSv1.1"
        case .tlsv12: "TLSv1.2"
        case .tlsv13: "TLSv1.3"
        }
    }

    static func certificateSummary(_ certificate: NIOSSLCertificate) -> ConnectionLog.Certificate? {
        guard let der = try? certificate.toDERBytes(),
              let parsed = try? X509.Certificate(derEncoded: der) else
        {
            return nil
        }
        let names: [String] = ((try? parsed.extensions.subjectAlternativeNames) ?? nil)?.compactMap { name in
            switch name {
            case let .dnsName(value):
                value
            case let .ipAddress(octets):
                ipAddressString(Array(octets.bytes))
            case let .uniformResourceIdentifier(value):
                value
            default:
                nil
            }
        } ?? []
        return ConnectionLog.Certificate(
            subject: parsed.subject.description,
            issuer: parsed.issuer.description,
            alternativeNames: names,
            notValidBefore: parsed.notValidBefore,
            notValidAfter: parsed.notValidAfter,
            serialNumber: parsed.serialNumber.description
        )
    }

    // MARK: Private

    private static func tlsDetails(
        on connection: Channel,
        host: String,
        intent: UpstreamTLSIntent,
        handshakeDuration: TimeInterval?,
        negotiatedProtocol: String?,
        failed: Bool
    )
        -> ConnectionLog.TLS?
    {
        guard let handler = try? connection.pipeline.syncOperations.handler(type: NIOSSLClientHandler.self) else {
            return nil
        }
        var tls = ConnectionLog.TLS()
        tls.serverName = TLSServerName.sni(for: host)
        tls.offeredProtocols = intent.offeredProtocols
        tls.negotiatedProtocol = negotiatedProtocol
        tls.version = handler.tlsVersion.map(versionName)
        tls.handshakeDuration = handshakeDuration
        tls.certificate = handler.peerCertificate.flatMap(certificateSummary)
        if !failed {
            tls.verification = if intent.acceptsUntrustedCertificates {
                .disabled
            } else if tls.serverName == nil {
                .hostnameSkipped
            } else {
                .verified
            }
        }
        return tls
    }

    private static func describe(_ error: Error) -> String {
        if let ioError = error as? IOError {
            return "\(String(cString: strerror(ioError.errnoCode))) (errno \(ioError.errnoCode))"
        }
        if let sslError = error as? NIOSSLError, case let .handshakeFailed(underlying) = sslError {
            return String(describing: underlying)
        }
        return String(describing: error)
    }

    private static func ipAddressString(_ bytes: [UInt8]) -> String? {
        switch bytes.count {
        case 4:
            return bytes.map(String.init).joined(separator: ".")
        case 16:
            var address = in6_addr()
            withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: bytes) }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else {
                return nil
            }
            return String(cString: buffer)
        default:
            return nil
        }
    }

    private static func seconds(from start: DispatchTime, to end: DispatchTime) -> TimeInterval {
        guard end.uptimeNanoseconds >= start.uptimeNanoseconds else {
            return 0
        }
        return TimeInterval(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }
}
