import Foundation
import NIOCore
import NIOHTTP1
import os

// Accepts SOCKS5 clients (for example URLSessionWebSocketTask or NWConnection configured
// with a SOCKS proxy) and hands each connection to the normal capture pipeline.

nonisolated(unsafe) private let socksLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "SOCKS5Server"
)

// MARK: - SOCKS5Request

/// A parsed SOCKS5 CONNECT request.
struct SOCKS5Request: Equatable {
    let host: String
    let port: Int
}

// MARK: - SOCKS5Parser

/// Stateless SOCKS5 (RFC 1928) message parsing, bounded by the protocol's own
/// length fields. Only the no-authentication method and CONNECT are accepted.
enum SOCKS5Parser {
    enum Outcome<Value: Equatable>: Equatable {
        case needMoreData
        case parsed(Value, consumed: Int)
        case rejected(reply: UInt8)
    }

    static let version: UInt8 = 0x05
    static let noAuthentication: UInt8 = 0x00
    static let noAcceptableMethods: UInt8 = 0xFF
    static let replySucceeded: UInt8 = 0x00
    static let replyGeneralFailure: UInt8 = 0x01
    static let replyNotAllowed: UInt8 = 0x02
    static let replyNetworkUnreachable: UInt8 = 0x03
    static let replyCommandNotSupported: UInt8 = 0x07
    static let replyAddressTypeNotSupported: UInt8 = 0x08

    /// Greeting: VER, NMETHODS, METHODS… → whether no-auth was offered.
    static func parseGreeting(_ bytes: [UInt8]) -> Outcome<Bool> {
        guard bytes.count >= 2 else {
            return .needMoreData
        }
        guard bytes[0] == version else {
            return .rejected(reply: noAcceptableMethods)
        }
        let methodCount = Int(bytes[1])
        guard bytes.count >= 2 + methodCount else {
            return .needMoreData
        }
        let offersNoAuth = bytes[2 ..< 2 + methodCount].contains(noAuthentication)
        return .parsed(offersNoAuth, consumed: 2 + methodCount)
    }

    /// Request: VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT.
    static func parseRequest(_ bytes: [UInt8]) -> Outcome<SOCKS5Request> {
        guard bytes.count >= 5 else {
            return .needMoreData
        }
        guard bytes[0] == version else {
            return .rejected(reply: replyGeneralFailure)
        }
        guard bytes[1] == 0x01 else {
            return .rejected(reply: replyCommandNotSupported)
        }
        let addressStart = 4
        let host: String
        let addressEnd: Int
        switch bytes[3] {
        case 0x01:
            addressEnd = addressStart + 4
            guard bytes.count >= addressEnd + 2 else {
                return .needMoreData
            }
            host = bytes[addressStart ..< addressEnd].map(String.init).joined(separator: ".")
        case 0x03:
            let length = Int(bytes[addressStart])
            addressEnd = addressStart + 1 + length
            guard length > 0 else {
                return .rejected(reply: replyGeneralFailure)
            }
            guard bytes.count >= addressEnd + 2 else {
                return .needMoreData
            }
            guard let name = String(bytes: bytes[(addressStart + 1) ..< addressEnd], encoding: .utf8),
                  !name.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" }) else
            {
                return .rejected(reply: replyGeneralFailure)
            }
            host = name
        case 0x04:
            addressEnd = addressStart + 16
            guard bytes.count >= addressEnd + 2 else {
                return .needMoreData
            }
            let groups = stride(from: addressStart, to: addressEnd, by: 2).map {
                String(UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]), radix: 16)
            }
            host = groups.joined(separator: ":")
        default:
            return .rejected(reply: replyAddressTypeNotSupported)
        }
        let port = Int(bytes[addressEnd]) << 8 | Int(bytes[addressEnd + 1])
        guard port > 0 else {
            return .rejected(reply: replyGeneralFailure)
        }
        return .parsed(SOCKS5Request(host: host, port: port), consumed: addressEnd + 2)
    }

    static func reply(_ code: UInt8) -> [UInt8] {
        [version, code, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
    }
}

// MARK: - SOCKS5ServerHandler

/// First handler on a SOCKS listener channel. It completes the SOCKS5 handshake,
/// then looks at the client's first bytes: TLS goes through the same tunnel path
/// as an HTTP CONNECT (so HTTPS decryption rules apply), and plain HTTP (including
/// `ws://` upgrades) is parsed by the proxy handler with requests pinned to the
/// SOCKS destination. The handler removes itself once the connection is routed.
final class SOCKS5ServerHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    /// Upper bound for the greeting plus request (a domain name is at most 255 bytes).
    static let maxHandshakeBytes = 600
    /// Upper bound for client bytes held while the connection is admitted and routed.
    static let maxBufferedPayloadBytes = 256 * 1_024

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        guard stage != .routed else {
            context.fireChannelRead(data)
            return
        }
        guard stage != .closing else {
            return
        }
        pending.writeBuffer(&incoming)
        let limit = stage == .greeting || stage == .request ? Self.maxHandshakeBytes : Self.maxBufferedPayloadBytes
        guard pending.readableBytes <= limit else {
            socksLogger.warning("SECURITY: SOCKS client exceeded the buffered byte limit")
            context.close(promise: nil)
            return
        }
        advance(context: context)
    }

    // MARK: Private

    private enum Stage {
        case greeting
        case request
        /// Destination parsed; waiting for CONNECT policy. Client bytes are held.
        case admitting
        case awaitingFirstPayload
        /// Tunnel or HTTP relay being installed. Client bytes are held.
        case routing
        case routed
        /// A refusal reply is being flushed; further client bytes are dropped.
        case closing
    }

    private var stage = Stage.greeting
    private var pending = ByteBuffer()
    private var destination: SOCKS5Request?

    private func advance(context: ChannelHandlerContext) {
        let bytes = pending.readableBytesView.map(\.self)
        switch stage {
        case .greeting:
            switch SOCKS5Parser.parseGreeting(bytes) {
            case .needMoreData:
                return
            case let .rejected(reply):
                write([SOCKS5Parser.version, reply], context: context, thenClose: true)
            case let .parsed(offersNoAuth, consumed):
                guard offersNoAuth else {
                    write([SOCKS5Parser.version, SOCKS5Parser.noAcceptableMethods], context: context, thenClose: true)
                    return
                }
                pending.moveReaderIndex(forwardBy: consumed)
                stage = .request
                write([SOCKS5Parser.version, SOCKS5Parser.noAuthentication], context: context, thenClose: false)
                advance(context: context)
            }
        case .request:
            switch SOCKS5Parser.parseRequest(bytes) {
            case .needMoreData:
                return
            case let .rejected(reply):
                write(SOCKS5Parser.reply(reply), context: context, thenClose: true)
            case let .parsed(request, consumed):
                pending.moveReaderIndex(forwardBy: consumed)
                pending.discardReadBytes()
                destination = request
                stage = .admitting
                admit(request, context: context)
            }
        case .awaitingFirstPayload:
            route(context: context)
        case .admitting,
             .routing,
             .routed,
             .closing:
            return
        }
    }

    /// Applies CONNECT policy before telling the client the tunnel is open.
    private func admit(_ request: SOCKS5Request, context: ChannelHandlerContext) {
        context.pipeline.handler(type: HTTPProxyHandler.self).flatMap { proxyHandler in
            proxyHandler.admitTunnel(context: context, host: request.host, port: request.port)
        }.whenComplete { result in
            switch result {
            case .success(.allowed):
                self.stage = .awaitingFirstPayload
                self.write(SOCKS5Parser.reply(SOCKS5Parser.replySucceeded), context: context, thenClose: false)
                if self.pending.readableBytes > 0 {
                    self.route(context: context)
                }
            case .success(.blocked):
                self.write(SOCKS5Parser.reply(SOCKS5Parser.replyNotAllowed), context: context, thenClose: true)
            case .success(.unreachable):
                self.write(SOCKS5Parser.reply(SOCKS5Parser.replyNetworkUnreachable), context: context, thenClose: true)
            case .failure:
                self.write(SOCKS5Parser.reply(SOCKS5Parser.replyGeneralFailure), context: context, thenClose: true)
            }
        }
    }

    /// Routes the connection once the client's first payload bytes are known. Bytes
    /// that arrive while the route is being installed stay in `pending` and are
    /// delivered together once the next handler is in place.
    private func route(context: ChannelHandlerContext) {
        guard let destination, pending.readableBytes > 0 else {
            return
        }
        stage = .routing
        let pipeline = context.pipeline
        let looksLikeTLS = pending.getInteger(at: pending.readerIndex, as: UInt8.self) == 0x16

        let installed: EventLoopFuture<Void>
        if looksLikeTLS {
            installed = pipeline.context(handlerType: HTTPProxyHandler.self).flatMap { proxyContext in
                guard let proxyHandler = proxyContext.handler as? HTTPProxyHandler else {
                    return context.eventLoop.makeFailedFuture(ChannelPipelineError.notFound)
                }
                return proxyHandler.beginTunnel(
                    context: proxyContext,
                    host: destination.host,
                    port: destination.port,
                    captureContext: nil
                )
            }
        } else {
            let target = ReverseProxyTarget(
                id: UUID(),
                localPort: 0,
                scheme: .http,
                host: destination.host,
                port: destination.port,
                preserveHostHeader: true
            )
            installed = pipeline.context(handlerType: HTTPProxyHandler.self).flatMap { proxyContext in
                pipeline.addHandler(ReverseProxyRequestRewriter(target: target), position: .before(proxyContext.handler))
            }
        }

        installed.whenComplete { result in
            guard case .success = result else {
                context.close(promise: nil)
                return
            }
            self.stage = .routed
            let buffered = self.pending
            self.pending = ByteBuffer()
            context.fireChannelRead(self.wrapInboundOut(buffered))
            pipeline.removeHandler(self, promise: nil)
        }
    }

    private func write(_ bytes: [UInt8], context: ChannelHandlerContext, thenClose: Bool) {
        var buffer = context.channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        let written = context.writeAndFlush(NIOAny(buffer))
        if thenClose {
            stage = .closing
            written.whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
}
