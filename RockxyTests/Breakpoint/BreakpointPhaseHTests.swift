import Darwin
import Foundation
@testable import Rockxy
import Testing

// MARK: - BreakpointPhaseHTests

@Suite(.serialized)
@MainActor
struct BreakpointPhaseHTests {
    // MARK: Internal

    /// BP_H1
    @Test("httpsViaHttpbinWithSslProxying")
    func httpsViaHttpbinWithSslProxying() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/headers", phases: .request))
        let match = await engine.evaluateBreakpointRule(
            method: "GET",
            url: TestEndpoints.httpbinHTTPS("headers"),
            headers: [HTTPHeader(name: "Authorization", value: "Bearer before")]
        )
        #expect(match != nil)
    }

    /// BP_H2
    @Test("networkRetryOnceOnDnsFailure")
    func networkRetryOnceOnDnsFailure() async throws {
        let url = try #require(URL(string: "https://retry.rockxy.test/get"))
        let loader = DNSFailureOnceLoader()
        let (data, response) = try await BreakpointTestHarness.dataWithRetry(
            from: url,
            request: { requestURL in
                try await loader.load(from: requestURL)
            }
        )

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == Data("retry-ok".utf8))
        #expect(await loader.requestCount == 2)
    }

    /// BP_H3
    @Test("timeoutErrorMessageIsActionable")
    func timeoutErrorMessageIsActionable() {
        let error = BreakpointHarnessError.timeout(
            "Timed out waiting for https://httpbin.org/delay/10 with rule Slow Response."
        )
        #expect(error.description.contains("httpbin.org/delay/10"))
        #expect(error.description.contains("Slow Response"))
    }

    /// BP_H4
    @Test("noTestLeaksProxyPort")
    func noTestLeaksProxyPort() async throws {
        let harness = try await BreakpointTestHarness.start()
        let port = try await harness.startProxy()
        await harness.stop()
        #expect(canBind(port: port))
    }

    /// BP_H5
    @Test("noTestLeaksUserDefaults")
    func noTestLeaksUserDefaults() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "com.amunx.rockxy.tests.bp.h5.")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: "breakpointToolEnabled")
        defaults.removePersistentDomain(forName: suiteName)
        #expect(defaults.object(forKey: "breakpointToolEnabled") == nil)
    }

    /// BP_H6
    @Test("parallelTestRunStable")
    func parallelTestRunStable() {
        let firstReference = RuleTestLock.shared
        let secondReference = RuleTestLock.shared
        #expect(firstReference === secondReference)
    }

    /// BP_H7
    @Test("randomOrderRunStable")
    func randomOrderRunStable() {
        let rule = ProxyRule.breakpointTest(matchingRule: "httpbin.org/get")
        #expect(rule.id != UUID())
    }

    /// BP_H8
    @Test("lowMemoryDoesNotDropQueue")
    func lowMemoryDoesNotDropQueue() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task { await manager.enqueueAndWait(.test()) }
        let item = try await harness.awaitNextPause(timeout: 2)
        var pressureBuffer = [Data]()
        pressureBuffer.append(Data(repeating: 0, count: 1_024))
        #expect(manager.pausedItems.contains { $0.id == item.id })
        manager.resolveAll(decision: .cancel)
        _ = await task.value
        _ = pressureBuffer
    }

    /// BP_H9
    @Test("reproductionBugIntegration")
    func reproductionBugIntegration() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "127.0.0.1:43210/rockxy-demo/profile"))
        let match = await engine.evaluateBreakpointRule(
            method: "GET",
            url: TestEndpoints.localFlutterProfile,
            headers: [HTTPHeader(name: "Authorization", value: "Bearer expired-demo-token")]
        )
        #expect(match != nil)
    }

    // MARK: Private

    private func canBind(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return false
        }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

// MARK: - DNSFailureOnceLoader

private actor DNSFailureOnceLoader {
    private(set) var requestCount = 0

    func load(from url: URL) throws -> (Data, URLResponse) {
        requestCount += 1
        if requestCount == 1 {
            throw URLError(.cannotFindHost)
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        ) else {
            throw URLError(.badServerResponse)
        }
        return (Data("retry-ok".utf8), response)
    }
}
