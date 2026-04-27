import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import os

private let rootCADownloadLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "RootCADownloadServer"
)

// MARK: - RootCADownloadResponse

struct RootCADownloadResponse {
    let status: HTTPResponseStatus
    let headers: [(String, String)]
    let body: Data
}

// MARK: - RootCADownloadResponder

enum RootCADownloadResponder {
    static func response(
        method: HTTPMethod,
        uri: String,
        session: RootCADownloadSession,
        certificatePEM: String,
        now: Date = Date()
    ) -> RootCADownloadResponse {
        guard method == .GET else {
            return plainResponse(status: .methodNotAllowed, message: "Method not allowed")
        }

        guard let components = URLComponents(string: uri),
              components.path == "/root-ca.pem"
        else {
            return plainResponse(status: .notFound, message: "Not found")
        }

        guard !session.isExpired(at: now) else {
            return plainResponse(status: .gone, message: "Certificate sharing link expired")
        }

        let token = components.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
        guard session.validates(token: token, at: now) else {
            return plainResponse(status: .notFound, message: "Not found")
        }

        return RootCADownloadResponse(
            status: .ok,
            headers: [
                ("Content-Type", "application/x-pem-file; charset=utf-8"),
                ("Content-Disposition", "attachment; filename=\"RockxyRootCA.pem\""),
                ("Cache-Control", "no-store"),
                ("X-Content-Type-Options", "nosniff"),
            ],
            body: Data(certificatePEM.utf8)
        )
    }

    private static func plainResponse(status: HTTPResponseStatus, message: String) -> RootCADownloadResponse {
        RootCADownloadResponse(
            status: status,
            headers: [
                ("Content-Type", "text/plain; charset=utf-8"),
                ("Cache-Control", "no-store"),
                ("X-Content-Type-Options", "nosniff"),
            ],
            body: Data(message.utf8)
        )
    }
}

// MARK: - RootCADownloadServer

actor RootCADownloadServer {
    // MARK: Internal

    private(set) var activeSession: RootCADownloadSession?

    var isRunning: Bool {
        serverChannel != nil
    }

    func start(certificatePEM: String, ttl: TimeInterval = 600) async throws -> RootCADownloadSession {
        guard !certificatePEM.isEmpty else {
            throw RootCADownloadError.noRootCA
        }

        await stop()

        guard let host = Self.rankedLANIPv4AddressCandidates().first?.address else {
            throw RootCADownloadError.noReachableLANAddress
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group

        let placeholderSession = try RootCADownloadSession.make(host: host, port: 0, ttl: ttl)
        let pem = certificatePEM

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 16)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(RootCADownloadHandler(session: placeholderSession, certificatePEM: pem))
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 8)

        do {
            let channel = try await bootstrap.bind(host: host, port: 0).get()
            guard let localAddress = channel.localAddress, let port = localAddress.port else {
                try await channel.close().get()
                throw RootCADownloadError.portUnavailable
            }

            let session = try placeholderSession.withPort(port)

            serverChannel = channel
            activeSession = session
            rootCADownloadLogger.info("Root CA download server started on \(host):\(port)")
            return session
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            activeSession = nil
            throw error
        }
    }

    func stop() async {
        activeSession = nil
        let channel = serverChannel
        serverChannel = nil

        if let channel {
            do {
                try await channel.close().get()
            } catch {
                rootCADownloadLogger.error("Failed to close Root CA download channel: \(error.localizedDescription)")
            }
        }

        if let group = eventLoopGroup {
            do {
                try await group.shutdownGracefully()
            } catch {
                rootCADownloadLogger.error("Failed to shut down Root CA download event loop: \(error.localizedDescription)")
            }
            eventLoopGroup = nil
        }
    }

    nonisolated static func lanIPv4Addresses() -> [String] {
        rankedLANIPv4AddressCandidates().map(\.address)
    }

    nonisolated static func rankedLANIPv4AddressCandidates() -> [LANIPv4AddressCandidate] {
        var candidates: [(interfaceName: String, address: String)] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0
            else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            let candidate = String(cString: hostname)
            let interfaceName = String(cString: interface.ifa_name)
            if !candidate.isEmpty, candidate != "0.0.0.0" {
                candidates.append((interfaceName: interfaceName, address: candidate))
            }
        }

        return rankedLANIPv4AddressCandidates(from: candidates)
    }

    nonisolated static func rankedLANIPv4AddressCandidates(
        from candidates: [(interfaceName: String, address: String)]
    ) -> [LANIPv4AddressCandidate] {
        var seenAddresses = Set<String>()
        return candidates
            .compactMap { candidate -> LANIPv4AddressCandidate? in
                guard let rank = interfaceRank(candidate.interfaceName) else {
                    return nil
                }
                return LANIPv4AddressCandidate(
                    interfaceName: candidate.interfaceName,
                    address: candidate.address,
                    rank: rank
                )
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                if lhs.interfaceName != rhs.interfaceName {
                    return lhs.interfaceName.localizedStandardCompare(rhs.interfaceName) == .orderedAscending
                }
                return lhs.address.localizedStandardCompare(rhs.address) == .orderedAscending
            }
            .filter { candidate in
                seenAddresses.insert(candidate.address).inserted
            }
    }

    // MARK: Private

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    nonisolated private static func interfaceRank(_ name: String) -> Int? {
        let lowercasedName = name.lowercased()
        guard !lowercasedName.hasPrefix("lo") else {
            return nil
        }

        switch lowercasedName {
        case "en0":
            return 0
        case "en1":
            return 1
        case "pdp_ip0":
            return 5
        default:
            if lowercasedName.hasPrefix("en") {
                return 10
            }
            if Self.virtualInterfacePrefixes.contains(where: { lowercasedName.hasPrefix($0) }) {
                return 90
            }
            return 50
        }
    }

    nonisolated private static let virtualInterfacePrefixes = [
        "utun",
        "bridge",
        "vmnet",
        "vboxnet",
        "awdl",
        "gif",
        "ppp",
        "p2p",
        "llw",
        "stf",
    ]
}

// MARK: - LANIPv4AddressCandidate

struct LANIPv4AddressCandidate: Equatable, Sendable {
    let interfaceName: String
    let address: String
    let rank: Int
}

// MARK: - RootCADownloadHandler

final class RootCADownloadHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    init(session: RootCADownloadSession, certificatePEM: String) {
        self.session = session
        self.certificatePEM = certificatePEM
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            requestMethod = head.method
            requestURI = head.uri
        case .body:
            break
        case .end:
            let response = RootCADownloadResponder.response(
                method: requestMethod ?? .GET,
                uri: requestURI ?? "",
                session: session,
                certificatePEM: certificatePEM
            )
            send(response: response, context: context)
            reset()
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    private let session: RootCADownloadSession
    private let certificatePEM: String
    private var requestMethod: HTTPMethod?
    private var requestURI: String?

    private func send(response: RootCADownloadResponse, context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        for (name, value) in response.headers {
            headers.add(name: name, value: value)
        }
        headers.add(name: "Content-Length", value: "\(response.body.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: response.status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: response.body.count)
        buffer.writeBytes(response.body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func reset() {
        requestMethod = nil
        requestURI = nil
    }
}
