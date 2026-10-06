import Foundation
import NIOCore
import NIOHTTP1

// Reverse proxy listeners: a local port that forwards every request to one remote server,
// for clients that cannot be pointed at an HTTP proxy.

// MARK: - ReverseProxyTarget

/// Runtime description of one reverse proxy listener. The listener accepts plain
/// HTTP on `127.0.0.1:localPort` and relays each request to `scheme://host:port`,
/// so a client only changes its base URL to reach the server through Rockxy.
struct ReverseProxyTarget: Equatable, Hashable, Sendable {
    enum Scheme: String, Codable, CaseIterable, Sendable {
        case http
        case https

        // MARK: Internal

        var defaultPort: Int {
            self == .https ? 443 : 80
        }
    }

    let id: UUID
    let localPort: Int
    let scheme: Scheme
    let host: String
    let port: Int
    /// Keep the client's `Host` header instead of sending the remote authority.
    let preserveHostHeader: Bool

    /// Remote authority as it appears in a URL and `Host` header: IPv6 literals are
    /// bracketed and the default port for the scheme is omitted.
    var authority: String {
        let hostPart = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return port == scheme.defaultPort ? hostPart : "\(hostPart):\(port)"
    }

    static func originForm(of uri: String) -> String {
        if uri.hasPrefix("/") {
            return uri
        }
        guard let schemeRange = uri.range(of: "://") else {
            return "/" + uri
        }
        let afterScheme = uri[schemeRange.upperBound...]
        guard let pathStart = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" }) else {
            return "/"
        }
        let rest = String(afterScheme[pathStart...])
        return rest.hasPrefix("?") ? "/" + rest : rest
    }

    /// Absolute-form request target for a request line the client sent to the
    /// local listener. Absolute-form input is reduced to its path and query first,
    /// so a client can never steer the listener to a different server.
    func absoluteURI(for requestURI: String) -> String {
        "\(scheme.rawValue)://\(authority)\(Self.originForm(of: requestURI))"
    }
}

// MARK: - ReverseProxyRequestRewriter

/// Sits in front of `HTTPProxyHandler` on a reverse proxy listener and turns each
/// request line into an absolute-form request for the configured remote server,
/// which the proxy handler then captures and relays like any proxied request.
/// CONNECT is refused: a reverse listener only serves its one remote server.
final class ReverseProxyRequestRewriter: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(target: ReverseProxyTarget) {
        self.target = target
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPServerRequestPart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        guard case var .head(head) = part else {
            if !isRejecting {
                context.fireChannelRead(data)
            }
            return
        }
        guard head.method != .CONNECT else {
            isRejecting = true
            context.close(promise: nil)
            return
        }
        head.uri = target.absoluteURI(for: head.uri)
        if !target.preserveHostHeader {
            head.headers.replaceOrAdd(name: "Host", value: target.authority)
        }
        context.fireChannelRead(wrapInboundOut(.head(head)))
    }

    // MARK: Private

    private let target: ReverseProxyTarget
    private var isRejecting = false
}

// MARK: - ReverseProxyBindFailure

enum ReverseProxyBindFailure: Error, Equatable, Sendable {
    case proxyNotRunning
    case portInUse
    case bindFailed(String)
}
