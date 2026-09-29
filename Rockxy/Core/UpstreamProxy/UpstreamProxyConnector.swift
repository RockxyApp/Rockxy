import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSL

// MARK: - UpstreamProxyConnector

nonisolated enum UpstreamProxyConnector {
    // MARK: Internal

    static func connect(
        eventLoop: EventLoop,
        targetScheme: String = "https",
        targetHost: String,
        targetPort: Int,
        configuration: UpstreamProxyResolvedConfiguration?,
        timeout: TimeAmount = ProxyTimeouts.upstreamConnect,
        pacResolver: @escaping UpstreamPACResolverFunction = UpstreamPACResolver.resolve,
        channelInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
    )
        -> EventLoopFuture<Channel>
    {
        guard let configuration,
              configuration.isEnabled,
              !configuration.shouldBypass(targetHost: targetHost) else
        {
            return directConnect(
                eventLoop: eventLoop,
                targetHost: targetHost,
                targetPort: targetPort,
                timeout: ProxyTimeouts.outboundConnect,
                channelInitializer: channelInitializer
            )
        }

        switch configuration.configuration.type {
        case .automatic:
            guard let pacURL = configuration.configuration.resolvedPACURL else {
                return eventLoop.makeFailedFuture(UpstreamProxyError.pacURLInvalid)
            }
            return pacResolver(eventLoop, pacURL, targetScheme, targetHost, targetPort).flatMap { route in
                switch route {
                case .direct:
                    return directConnect(
                        eventLoop: eventLoop,
                        targetHost: targetHost,
                        targetPort: targetPort,
                        timeout: ProxyTimeouts.outboundConnect,
                        channelInitializer: channelInitializer
                    )
                case let .proxy(type, proxyHost, proxyPort):
                    if type == .socks5, !configuration.allowsSOCKS5 {
                        return eventLoop.makeFailedFuture(UpstreamProxyError.pacSOCKS5Unavailable)
                    }
                    return proxyConnect(
                        eventLoop: eventLoop,
                        proxyHost: proxyHost,
                        proxyPort: proxyPort,
                        proxyType: type,
                        targetScheme: targetScheme,
                        targetHost: targetHost,
                        targetPort: targetPort,
                        credentials: configuration.credentials,
                        timeout: timeout,
                        channelInitializer: channelInitializer
                    )
                }
            }
        case .http:
            return proxyConnect(
                eventLoop: eventLoop,
                proxyHost: configuration.configuration.host,
                proxyPort: configuration.configuration.port,
                proxyType: .http,
                targetScheme: targetScheme,
                targetHost: targetHost,
                targetPort: targetPort,
                credentials: configuration.credentials,
                timeout: timeout,
                channelInitializer: channelInitializer
            )
        case .https:
            return proxyConnect(
                eventLoop: eventLoop,
                proxyHost: configuration.configuration.host,
                proxyPort: configuration.configuration.port,
                proxyType: .https,
                targetScheme: targetScheme,
                targetHost: targetHost,
                targetPort: targetPort,
                credentials: configuration.credentials,
                timeout: timeout,
                channelInitializer: channelInitializer
            )
        case .socks5:
            return proxyConnect(
                eventLoop: eventLoop,
                proxyHost: configuration.configuration.host,
                proxyPort: configuration.configuration.port,
                proxyType: .socks5,
                targetScheme: targetScheme,
                targetHost: targetHost,
                targetPort: targetPort,
                credentials: configuration.credentials,
                timeout: timeout,
                channelInitializer: channelInitializer
            )
        }
    }

    static func directConnect(
        eventLoop: EventLoop,
        targetHost: String,
        targetPort: Int,
        timeout: TimeAmount = ProxyTimeouts.outboundConnect,
        channelInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
    )
        -> EventLoopFuture<Channel>
    {
        ClientBootstrap(group: eventLoop)
            .connectTimeout(timeout)
            .channelInitializer(channelInitializer)
            .connect(host: targetHost, port: targetPort)
    }

    // MARK: Private

    /// Plain-HTTP targets are sent to an HTTP(S) proxy in absolute form on the proxy
    /// connection; only TLS targets and SOCKS routes need a tunnel handshake first.
    nonisolated static func usesAbsoluteFormRelay(proxyType: UpstreamProxyType, targetScheme: String) -> Bool {
        (proxyType == .http || proxyType == .https) && targetScheme.lowercased() == "http"
    }

    private static func proxyConnect(
        eventLoop: EventLoop,
        proxyHost: String,
        proxyPort: Int,
        proxyType: UpstreamProxyType,
        targetScheme: String,
        targetHost: String,
        targetPort: Int,
        credentials: UpstreamProxyCredentials?,
        timeout: TimeAmount,
        channelInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
    )
        -> EventLoopFuture<Channel>
    {
        if usesAbsoluteFormRelay(proxyType: proxyType, targetScheme: targetScheme) {
            return ClientBootstrap(group: eventLoop)
                .connectTimeout(timeout)
                .connect(host: proxyHost, port: proxyPort)
                .flatMap { channel in
                    let transport: EventLoopFuture<Void> = proxyType == .https
                        ? addTLSHandler(channel: channel, proxyHost: proxyHost)
                        : channel.eventLoop.makeSucceededVoidFuture()
                    return transport.flatMap {
                        channelInitializer(channel)
                    }.flatMap {
                        // Appended after the relay's HTTP client handlers so the head is rewritten
                        // before the encoder serialises it.
                        channel.pipeline.addHandler(AbsoluteFormRequestHandler(
                            targetScheme: targetScheme,
                            targetHost: targetHost,
                            targetPort: targetPort,
                            credentials: credentials
                        ))
                    }.map {
                        channel
                    }.flatMapError { error in
                        channel.close(promise: nil)
                        return eventLoop.makeFailedFuture(error)
                    }
                }
        }

        return ClientBootstrap(group: eventLoop)
            .connectTimeout(timeout)
            .connect(host: proxyHost, port: proxyPort)
            .flatMap { channel in
                let handshake = installHandshake(
                    channel: channel,
                    proxyType: proxyType,
                    proxyHost: proxyHost,
                    targetHost: targetHost,
                    targetPort: targetPort,
                    credentials: credentials,
                    timeout: ProxyTimeouts.upstreamHandshake
                )
                return handshake.flatMap {
                    channelInitializer(channel)
                }.map {
                    channel
                }.flatMapError { error in
                    channel.close(promise: nil)
                    return eventLoop.makeFailedFuture(error)
                }
            }
    }

    private static func installHandshake(
        channel: Channel,
        proxyType: UpstreamProxyType,
        proxyHost: String,
        targetHost: String,
        targetPort: Int,
        credentials: UpstreamProxyCredentials?,
        timeout: TimeAmount
    )
        -> EventLoopFuture<Void>
    {
        let promise = channel.eventLoop.makePromise(of: Void.self)
        let timeoutTask = channel.eventLoop.scheduleTask(in: timeout) {
            promise.fail(UpstreamProxyError.timeout)
            channel.close(promise: nil)
        }
        promise.futureResult.whenComplete { _ in
            timeoutTask.cancel()
        }

        let addHandshake: EventLoopFuture<Void> = switch proxyType {
        case .http:
            channel.pipeline.addHandler(HTTPConnectTunnelHandler(
                targetHost: targetHost,
                targetPort: targetPort,
                credentials: credentials,
                completionPromise: promise
            ))
        case .https:
            addTLSHandler(channel: channel, proxyHost: proxyHost).flatMap {
                channel.pipeline.addHandler(HTTPConnectTunnelHandler(
                    targetHost: targetHost,
                    targetPort: targetPort,
                    credentials: credentials,
                    completionPromise: promise
                ))
            }
        case .socks5:
            channel.pipeline.addHandler(SOCKS5ClientHandler(
                targetHost: targetHost,
                targetPort: targetPort,
                credentials: credentials,
                completionPromise: promise
            ))
        case .automatic:
            channel.eventLoop.makeFailedFuture(UpstreamProxyError.pacNoSupportedRoute)
        }

        addHandshake.whenFailure { error in
            promise.fail(error)
        }
        return promise.futureResult
    }

    private static func addTLSHandler(channel: Channel, proxyHost: String) -> EventLoopFuture<Void> {
        do {
            let tlsConfig = TLSConfiguration.makeClientConfiguration()
            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: TLSServerName.sni(for: proxyHost))
            return channel.pipeline.addHandler(sslHandler)
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }
    }
}
