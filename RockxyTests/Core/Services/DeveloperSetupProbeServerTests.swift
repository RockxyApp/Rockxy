import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

// MARK: - DeveloperSetupProbeSessionTests

struct DeveloperSetupProbeSessionTests {
    @Test("session URL includes loopback host target and path token")
    func sessionURLIncludesLoopbackHostTargetAndToken() {
        let session = DeveloperSetupProbeSession.make(
            port: 12_345,
            targetID: .python,
            token: "test-token"
        )

        #expect(session.host == "127.0.0.1")
        #expect(session.method == "GET")
        #expect(session.path == "/.well-known/rockxy/dev-setup/python/test-token")
        #expect(session.url.absoluteString == "http://127.0.0.1:12345/.well-known/rockxy/dev-setup/python/test-token")
    }
}

// MARK: - DeveloperSetupProbeResponderTests

struct DeveloperSetupProbeResponderTests {
    @Test("valid token path returns ok without reflected request data")
    func validTokenPathReturnsOK() {
        let session = DeveloperSetupProbeSession.make(port: 12_345, targetID: .python, token: "token")

        let response = DeveloperSetupProbeResponder.response(
            method: .GET,
            uri: session.path,
            session: session
        )

        #expect(response.status == .ok)
        #expect(header("Cache-Control", in: response) == "no-store")
        #expect(header("X-Content-Type-Options", in: response) == "nosniff")
        #expect(header("Content-Type", in: response) == "application/json; charset=utf-8")
        #expect(String(bytes: response.body, encoding: .utf8) == "{\"ok\":true}\n")
        #expect(String(bytes: response.body, encoding: .utf8)?.contains(session.token) == false)
    }

    @Test("wrong token path returns not found")
    func wrongTokenPathReturnsNotFound() {
        let session = DeveloperSetupProbeSession.make(port: 12_345, targetID: .python, token: "token")

        let response = DeveloperSetupProbeResponder.response(
            method: .GET,
            uri: "/.well-known/rockxy/dev-setup/python/wrong-token",
            session: session
        )

        #expect(response.status == .notFound)
    }

    @Test("non GET returns method not allowed")
    func nonGETReturnsMethodNotAllowed() {
        let session = DeveloperSetupProbeSession.make(port: 12_345, targetID: .python, token: "token")

        let response = DeveloperSetupProbeResponder.response(
            method: .POST,
            uri: session.path,
            session: session
        )

        #expect(response.status == .methodNotAllowed)
    }

    private func header(_ name: String, in response: DeveloperSetupProbeResponse) -> String? {
        response.headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }
}

// MARK: - DeveloperSetupProbeServerTests

struct DeveloperSetupProbeServerTests {
    @Test("server binds loopback and serves active session")
    func serverBindsLoopbackAndServesActiveSession() async throws {
        let server = DeveloperSetupProbeServer()
        let session = try await server.start(targetID: .python)
        defer { Task { await server.stop() } }

        #expect(session.host == "127.0.0.1")
        #expect(session.port > 0)

        let (data, response) = try await URLSession.shared.data(from: session.url)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(String(bytes: data, encoding: .utf8) == "{\"ok\":true}\n")

        await server.stop()
        #expect(await server.isRunning == false)
    }

    @Test("Concurrent starts publish only the newest target session")
    func concurrentStartsPublishNewestSession() async throws {
        let server = DeveloperSetupProbeServer()
        let firstStart = Task {
            try await server.start(targetID: .python)
        }
        await Task.yield()
        let secondStart = Task {
            try await server.start(targetID: .ruby)
        }

        _ = try? await firstStart.value
        let newestSession = try await secondStart.value

        #expect(newestSession.targetID == .ruby)
        #expect(await server.activeSession?.targetID == .ruby)
        await server.stop()
    }

    @Test("A stale session cannot stop the newer probe server")
    func staleSessionStopPreservesNewestServer() async throws {
        let server = DeveloperSetupProbeServer()
        let staleSession = try await server.start(targetID: .python)
        let newestSession = try await server.start(targetID: .ruby)

        await server.stop(ifCurrent: staleSession)

        #expect(await server.activeSession == newestSession)
        #expect(await server.isRunning)
        await server.stop()
    }

    @Test("Stop prevents an in-flight start from publishing afterward")
    func stopIsPublicationBarrier() async {
        let server = DeveloperSetupProbeServer()
        let startTask = Task {
            try await server.start(targetID: .python)
        }
        await Task.yield()

        await server.stop()
        _ = try? await startTask.value
        await Task.yield()

        #expect(await server.activeSession == nil)
        #expect(await server.isRunning == false)
    }
}
