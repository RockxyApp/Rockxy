import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
@testable import Rockxy
import Testing

enum BreakpointHarnessError: Error, CustomStringConvertible {
    case noNetwork(URL, underlying: Error)
    case timeout(String)
    case socket(String)

    var description: String {
        switch self {
        case let .noNetwork(url, underlying):
            "No network response from \(url.absoluteString): \(underlying.localizedDescription)"
        case let .timeout(message):
            message
        case let .socket(message):
            message
        }
    }
}

actor BreakpointTestHarness {
    let manager: BreakpointManager
    let ruleEngine: RuleEngine
    private let captureSink = CaptureSink()
    private var proxyServer: ProxyServer?
    private var proxyPort: Int?

    init(
        manager: BreakpointManager,
        ruleEngine: RuleEngine
    ) {
        self.manager = manager
        self.ruleEngine = ruleEngine
    }

    static func start() async throws -> BreakpointTestHarness {
        let manager = await MainActor.run { BreakpointManager() }
        let engine = RuleEngine()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: engine)
        _ = try await harness.startProxy()
        return harness
    }

    func startProxy() async throws -> Int {
        if let proxyPort {
            return proxyPort
        }
        let port = try Self.findFreePort()
        let manager = manager
        let sink = captureSink
        let server = ProxyServer(
            configuration: ProxyConfiguration(port: port, listenAddress: "127.0.0.1", listenIPv6: false),
            ruleEngine: ruleEngine,
            onTransactionComplete: { transaction in
                Task { await sink.append(transaction) }
            },
            onBreakpointHit: { data in
                await manager.enqueueAndWait(data)
            }
        )
        try await server.start()
        proxyServer = server
        proxyPort = port
        return port
    }

    func stop() async {
        await proxyServer?.stop()
        proxyServer = nil
        proxyPort = nil
        await MainActor.run {
            manager.resolveAll(decision: .cancel)
        }
    }

    func client() async throws -> URLSession {
        let port = try await startProxy()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": port,
        ]
        return URLSession(configuration: configuration)
    }

    func addRule(_ rule: ProxyRule) async {
        await ruleEngine.addRule(rule)
    }

    func clearRules() async {
        await ruleEngine.replaceAll([])
    }

    func setGlobalEnable(_ enabled: Bool) async {
        await ruleEngine.setBreakpointToolEnabled(enabled)
    }

    func awaitNextPause(timeout seconds: TimeInterval = 5) async throws -> PausedBreakpointItem {
        if let item = await MainActor.run(body: { manager.pausedItems.first }) {
            return item
        }
        return try await withThrowingTaskGroup(of: PausedBreakpointItem.self) { group in
            group.addTask { [manager] in
                for await _ in NotificationCenter.default.notifications(named: .breakpointHit) {
                    if let item = await MainActor.run(body: { manager.pausedItems.first }) {
                        return item
                    }
                }
                throw BreakpointHarnessError.timeout("Breakpoint queue notification ended before a pause arrived.")
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw BreakpointHarnessError.timeout(
                    "Timed out waiting \(seconds)s for the next breakpoint pause."
                )
            }
            let item = try await group.next()!
            group.cancelAll()
            return item
        }
    }

    func editDraft(
        _ itemID: UUID,
        mutate: @MainActor @escaping (inout BreakpointRequestData) -> Void
    ) async {
        await MainActor.run {
            manager.updateDraft(id: itemID, mutate)
        }
    }

    func resolve(_ itemID: UUID, decision: BreakpointDecision) async {
        await MainActor.run {
            manager.resolve(id: itemID, decision: decision)
        }
    }

    @MainActor
    func addTemplate(_ template: BreakpointTemplate, to store: BreakpointTemplateStore) {
        let created = store.addTemplate(kind: template.kind)
        store.updateTemplate(id: created.id, name: template.name, rawMessage: template.rawMessage)
    }

    @MainActor
    func clearTemplates(_ store: BreakpointTemplateStore) {
        for template in store.templates {
            store.deleteTemplate(id: template.id)
        }
    }

    func lastCapturedRow() async -> HTTPTransaction? {
        await captureSink.last()
    }

    func capturedRows() async -> [HTTPTransaction] {
        await captureSink.all()
    }

    static func dataWithRetry(
        from url: URL,
        session: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            if (error as NSError).domain == NSURLErrorDomain,
               (error as NSError).code == NSURLErrorCannotFindHost
                    || (error as NSError).code == NSURLErrorDNSLookupFailed
            {
                try await Task.sleep(nanoseconds: 300_000_000)
                return try await session.data(from: url)
            }
            throw BreakpointHarnessError.noNetwork(url, underlying: error)
        }
    }

    private static func findFreePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw BreakpointHarnessError.socket("Unable to create socket.")
        }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw BreakpointHarnessError.socket("Unable to bind test socket.")
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw BreakpointHarnessError.socket("Unable to inspect test socket port.")
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

// MARK: - BreakpointLocalHTTPServer

actor BreakpointLocalHTTPServer {
    static func start() async throws -> BreakpointLocalHTTPServer {
        let server = BreakpointLocalHTTPServer()
        try await server.start()
        return server
    }

    func url(_ path: String) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        guard let url = components.url else {
            preconditionFailure("Breakpoint local test server produced an invalid URL.")
        }
        return url
    }

    func matchingRule(_ path: String) -> String {
        "\(host):\(port)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    func stop() async {
        let channel = serverChannel
        serverChannel = nil
        if let channel {
            try? await channel.close().get()
        }
        if let eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
        }
        eventLoopGroup = nil
        port = 0
    }

    private let host = "127.0.0.1"
    private var port = 0
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    private func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group

        do {
            let channel = try await ServerBootstrap(group: group)
                .serverChannelOption(.backlog, value: 16)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(BreakpointLocalHTTPHandler())
                    }
                }
                .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .bind(host: host, port: 0)
                .get()

            guard let boundPort = channel.localAddress?.port else {
                try await channel.close().get()
                throw BreakpointHarnessError.socket("Unable to inspect local test server port.")
            }
            serverChannel = channel
            port = boundPort
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            throw error
        }
    }
}

private final class BreakpointLocalHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            requestHead = head
        case .body:
            break
        case .end:
            respond(context: context)
            requestHead = nil
        }
    }

    private var requestHead: HTTPRequestHead?

    private func respond(context: ChannelHandlerContext) {
        let head = requestHead
        let path = URLComponents(string: head?.uri ?? "/")?.path ?? "/"
        let response = response(for: path, requestHeaders: head?.headers ?? HTTPHeaders())
        var headers = response.headers
        headers.add(name: "Content-Length", value: "\(response.body.readableBytes)")
        headers.add(name: "Connection", value: "close")

        let responseHead = HTTPResponseHead(version: .http1_1, status: response.status, headers: headers)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(response.body))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func response(for path: String, requestHeaders: HTTPHeaders) -> (
        status: HTTPResponseStatus,
        headers: HTTPHeaders,
        body: ByteBuffer
    ) {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        var headers = HTTPHeaders()

        switch path {
        case "/headers":
            headers.add(name: "Content-Type", value: "application/json")
            let echoedHeaders = Dictionary(requestHeaders.map { ($0.name, $0.value) }, uniquingKeysWith: { _, latest in latest })
            let payload = (try? JSONSerialization.data(withJSONObject: ["headers": echoedHeaders])) ?? Data("{}".utf8)
            buffer.writeBytes(payload)
            return (.ok, headers, buffer)
        case "/status/401":
            headers.add(name: "Content-Type", value: "text/plain")
            buffer.writeString("unauthorized")
            return (.unauthorized, headers, buffer)
        case "/delay/1", "/get":
            headers.add(name: "Content-Type", value: "application/json")
            buffer.writeString(#"{"ok":true}"#)
            return (.ok, headers, buffer)
        default:
            headers.add(name: "Content-Type", value: "text/plain")
            buffer.writeString("not found")
            return (.notFound, headers, buffer)
        }
    }
}

private actor CaptureSink {
    private var transactions: [HTTPTransaction] = []

    func append(_ transaction: HTTPTransaction) {
        transactions.append(transaction)
    }

    func last() -> HTTPTransaction? {
        transactions.last
    }

    func all() -> [HTTPTransaction] {
        transactions
    }
}

extension ProxyRule {
    static func breakpointTest(
        name: String = "Breakpoint Test Rule",
        matchingRule: String,
        method: HTTPMethodFilter = .any,
        matchType: RuleMatchType = .wildcard,
        phases: BreakpointRulePhase = .both,
        includeSubpaths: Bool = false,
        isEnabled: Bool = true
    ) -> ProxyRule {
        ProxyRule(
            name: name,
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(
                urlPattern: RulePatternBuilder.regexSource(
                    rawPattern: matchingRule,
                    matchType: matchType,
                    includeSubpaths: includeSubpaths
                ),
                method: method.methodValue
            ),
            action: .breakpoint(phase: phases)
        )
    }
}

extension BreakpointRequestData {
    static func test(
        method: String = "GET",
        url: String = "https://httpbin.org/get",
        headers: [EditableHeader] = [],
        body: String = "",
        statusCode: Int = 200,
        phase: BreakpointPhase = .request
    ) -> BreakpointRequestData {
        BreakpointRequestData(
            method: method,
            url: url,
            headers: headers,
            body: body,
            statusCode: statusCode,
            phase: phase
        )
    }
}

struct BreakpointRuleStateBackup {
    let diskData: Data?
    let engineRules: [ProxyRule]
    let breakpointToolEnabled: Bool?
}

enum BreakpointRuleTestIsolation {
    private static let breakpointToolEnabledKey = "breakpointToolEnabled"

    private static let rulesPath = RockxyIdentity.current.appSupportPath(TestIdentity.rulesPathComponent)

    static func withSharedRuleState(_ body: () async throws -> Void) async rethrows {
        await RuleTestLock.shared.acquire()
        let backup = await backup()
        do {
            try await body()
            await restore(backup)
            await RuleTestLock.shared.release()
        } catch {
            await restore(backup)
            await RuleTestLock.shared.release()
            throw error
        }
    }

    private static func backup() async -> BreakpointRuleStateBackup {
        BreakpointRuleStateBackup(
            diskData: try? Data(contentsOf: rulesPath),
            engineRules: await RuleEngine.shared.allRules,
            breakpointToolEnabled: UserDefaults.standard.object(forKey: breakpointToolEnabledKey) as? Bool
        )
    }

    private static func restore(_ backup: BreakpointRuleStateBackup) async {
        if let diskData = backup.diskData {
            try? FileManager.default.createDirectory(
                at: rulesPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? diskData.write(to: rulesPath)
        } else {
            try? FileManager.default.removeItem(at: rulesPath)
        }
        if let breakpointToolEnabled = backup.breakpointToolEnabled {
            UserDefaults.standard.set(breakpointToolEnabled, forKey: breakpointToolEnabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: breakpointToolEnabledKey)
        }
        await RuleEngine.shared.replaceAll(backup.engineRules)
        await RuleEngine.shared.setBreakpointToolEnabled(backup.breakpointToolEnabled ?? true)
    }
}
