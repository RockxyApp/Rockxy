import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
@testable import Rockxy
import Testing

// MARK: - MapLocalLoopbackIntegrationTests

/// Network-level integration tests for Map Local rules.
///
/// Each test boots a deterministic local origin fixture plus a real `ProxyServer` on
/// ephemeral loopback ports, installs Map Local rules through an isolated `RuleEngine`
/// instance, and drives explicit-proxy plain-HTTP requests through the proxy. Because the
/// tests own their `RuleEngine`/`ProxyServer` instances and never touch `RuleEngine.shared`
/// or the macOS system proxy, there is no global rule state to preserve — teardown only has
/// to stop the two servers and delete the temp fixtures.
@Suite(.serialized)
struct MapLocalLoopbackIntegrationTests {
    @Test("Matching URL is served from the local file with configured status, headers, and body")
    func matchingURLServedLocally() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let file = try harness.writeFixtureFile(
                named: "mapped.json",
                contents: Data(#"{"source":"map-local"}"#.utf8)
            )
            await harness.addRule(harness.mapLocalRule(
                name: "Mapped",
                path: "/mapped",
                filePath: file.path,
                statusCode: 201,
                responseHeaders: [
                    HTTPHeader(name: "Content-Type", value: "application/json"),
                    HTTPHeader(name: "X-Rockxy-Map", value: "local"),
                ]
            ))

            let response = try await harness.get("/mapped")

            #expect(response.status == 201)
            #expect(response.body == Data(#"{"source":"map-local"}"#.utf8))
            #expect(response.headerValue("X-Rockxy-Map") == "local")
            #expect(response.headerValue("Content-Type") == "application/json")
            // Content-Length is always recomputed from the served bytes.
            #expect(response.headerValue("Content-Length") == "22")
            // The origin must not have been reached.
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
        }
    }

    @Test("An origin that closes before responding yields a fast 502 and a failed row")
    func originClosingEarlyReturns502() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let started = ContinuousClock.now
            let response = try await harness.get("/close-without-response")
            let elapsed = ContinuousClock.now - started

            #expect(response.status == 502)
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
            #expect(elapsed < .seconds(5), "client waited \(elapsed) for the upstream close")

            try await Task.sleep(for: .milliseconds(300))
            let failed = await harness.capturedTransactions().first { $0.request.url.path == "/close-without-response" }
            #expect(failed?.state == .failed)
            #expect(failed?.response?.statusCode == 502)
            #expect(failed?.connectionLog?.failure?.stage == .response)
            #expect(failed?.connectionLog?.remoteAddress == "127.0.0.1")
        }
    }

    @Test("The Connection Log records the address Rockxy connected to for plain HTTP")
    func connectionLogRecordsPlainHTTPAddress() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let response = try await harness.get("/live?log=1")
            #expect(response.status == 200)

            try await Task.sleep(for: .milliseconds(300))
            let row = await harness.capturedTransactions().first { $0.request.url.query == "log=1" }
            let log = try #require(row?.connectionLog)
            #expect(log.remoteAddress == "127.0.0.1")
            #expect(log.remotePort == harness.originPort)
            #expect(log.route == .direct)
            #expect(log.connectHost == nil)
            #expect(log.tls == nil)
            #expect(log.failure == nil)
            #expect(log.connectDuration != nil)
            #expect(log.localAddress == "127.0.0.1")
        }
    }

    @Test("The Connection Log names each refused address when the server is unreachable")
    func connectionLogRecordsRefusedConnection() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let closedPort = try await harness.unusedLoopbackPort()
            let response = try await harness.get(host: "127.0.0.1", port: closedPort, path: "/refused")
            #expect(response.status == 502)

            try await Task.sleep(for: .milliseconds(300))
            let row = await harness.capturedTransactions().first { $0.request.url.path == "/refused" }
            let failure = try #require(row?.connectionLog?.failure)
            #expect(failure.stage == .connect)
            #expect(failure.message.contains("port \(closedPort)"))
            #expect(failure.attempts.contains { $0.hasPrefix("127.0.0.1 port \(closedPort):") && $0.contains("refused") })
        }
    }

    @Test("Network Conditions Offline drops the connection without reaching the origin")
    func offlineNetworkConditionDropsConnection() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let absolute = harness.absoluteURLString(path: "/offline")
            await harness.addRule(ProxyRule(
                name: "Offline",
                matchCondition: RuleMatchCondition(
                    urlPattern: absolute,
                    sourceURLPattern: absolute,
                    matchType: .wildcard,
                    includeSubpaths: false
                ),
                action: .networkCondition(preset: .offline, delayMs: 0)
            ))

            let response = try? await harness.get("/offline")
            #expect(response == nil || response?.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)

            let live = try await harness.get("/live")
            #expect(live.status == 200)

            try await Task.sleep(for: .milliseconds(300))
            let offline = await harness.capturedTransactions().first { $0.request.url.path == "/offline" }
            #expect(offline?.state == .failed)
            #expect(offline?.response == nil)
            #expect(offline?.matchedRuleName == "Offline")
        }
    }

    @Test("A Custom Network Conditions profile paces the response at its download limit")
    func customNetworkConditionPacesDownload() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let absolute = harness.absoluteURLString(path: "/large")
            await harness.addRule(ProxyRule(
                name: "Slow custom",
                matchCondition: RuleMatchCondition(
                    urlPattern: absolute,
                    sourceURLPattern: absolute,
                    matchType: .wildcard,
                    includeSubpaths: false
                ),
                // 80 kbps is 10,000 bytes per second, so a 20 KB body takes about two seconds.
                action: .networkCondition(
                    preset: .custom,
                    delayMs: 10,
                    custom: NetworkCustomProfile(downloadKbps: 80)
                )
            ))

            let started = ContinuousClock.now
            let response = try await harness.get("/large")
            let elapsed = ContinuousClock.now - started

            #expect(response.status == 200)
            #expect(response.body.count == 20_000 + "origin:/large".utf8.count)
            #expect(elapsed >= .milliseconds(1_500), "custom download limit was not applied (\(elapsed))")
            #expect(elapsed < .seconds(10))
        }
    }

    @Test("A Map Local rule scoped to a GraphQL operation mocks only that operation")
    func graphQLOperationScopedMapLocal() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let file = try harness.writeFixtureFile(
                named: "get-user.json",
                contents: Data(#"{"data":{"user":{"name":"Mocked"}}}"#.utf8)
            )
            var rule = harness.mapLocalRule(name: "GetUser mock", path: "/graphql", filePath: file.path)
            rule.matchCondition.graphQLOperationName = "GetUser"
            await harness.addRule(rule)

            let mocked = try await harness.post(
                "/graphql",
                json: #"{"operationName":"GetUser","query":"query GetUser { user { name } }"}"#
            )
            let live = try await harness.post(
                "/graphql",
                json: #"{"query":"query ListPosts { posts { id } }"}"#
            )

            #expect(mocked.body == Data(#"{"data":{"user":{"name":"Mocked"}}}"#.utf8))
            #expect(mocked.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
            #expect(live.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
        }
    }

    @Test("A reverse proxy listener relays origin-form requests to its server and captures them")
    func reverseProxyRelaysAndCaptures() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let reversePort = try await harness.startReverseProxy()

            let response = try await harness.getViaReverseProxy(port: reversePort, path: "/live?source=reverse")

            #expect(response.status == 200)
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
            #expect(response.body == Data("origin:/live".utf8))

            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions().first { $0.request.url.path == "/live" }
            #expect(captured?.request.url.absoluteString == harness.absoluteURLString(path: "/live?source=reverse"))
            #expect(captured?.state == .completed)
        }
    }

    @Test("A reverse proxy rule applies like any captured request")
    func reverseProxyHonorsRules() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let file = try harness.writeFixtureFile(named: "reverse.txt", contents: Data("MOCKED".utf8))
            await harness.addRule(harness.mapLocalRule(name: "Reverse mock", path: "/mocked", filePath: file.path))
            let reversePort = try await harness.startReverseProxy()

            let response = try await harness.getViaReverseProxy(port: reversePort, path: "/mocked")

            #expect(response.body == Data("MOCKED".utf8))
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
        }
    }

    @Test("A SOCKS5 client reaches the origin through Rockxy and the request is captured")
    func socks5PlainHTTPIsCaptured() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let socksPort = try await harness.startSOCKSListener()
            let originPort = harness.originPort

            let raw = try await Task.detached {
                try SOCKS5TestClient.exchange(
                    socksPort: socksPort,
                    destinationIPv4: [127, 0, 0, 1],
                    destinationPort: originPort,
                    payload: "GET /live?via=socks HTTP/1.1\r\nHost: 127.0.0.1:\(originPort)\r\nConnection: close\r\n\r\n"
                )
            }.value

            #expect(raw.hasPrefix("HTTP/1.1 200"))
            #expect(raw.contains("origin:/live"))

            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions().first { $0.request.url.query == "via=socks" }
            #expect(captured?.request.url.absoluteString == harness.absoluteURLString(path: "/live?via=socks"))
            #expect(captured?.state == .completed)
        }
    }

    @Test("Repeat Through Rules sends the request through the proxy so rules apply and it is recorded")
    func repeatThroughRulesAppliesRules() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let file = try harness.writeFixtureFile(named: "replayed.json", contents: Data(#"{"from":"rule"}"#.utf8))
            await harness.addRule(harness.mapLocalRule(name: "Replay", path: "/replay-target", filePath: file.path))
            let request = HTTPRequestData(
                method: "GET",
                url: try #require(URL(string: harness.absoluteURLString(path: "/replay-target"))),
                httpVersion: "HTTP/1.1",
                headers: []
            )

            let direct = try await RequestReplay.replay(request)
            #expect(direct.body == Data("origin:/replay-target".utf8))

            let throughRules = try await RequestReplay.replay(request, throughProxyPort: harness.listenerPort)
            #expect(throughRules.body == Data(#"{"from":"rule"}"#.utf8))

            try await Task.sleep(for: .milliseconds(300))
            let rows = await harness.capturedTransactions().filter { $0.request.url.path == "/replay-target" }
            #expect(rows.count == 1)
            #expect(rows.first?.matchedRuleName == "Replay")
        }
    }

    @Test("A hiding Block rule answers the client but leaves no row")
    func blockAndHideLeavesNoRow() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            var hidden = ProxyRule(
                name: "Hide analytics",
                matchCondition: RuleMatchCondition(urlPattern: ".*/analytics.*"),
                action: .block(statusCode: 403)
            )
            hidden.hidesMatchedTraffic = true
            await harness.addRule(hidden)
            await harness.addRule(ProxyRule(
                name: "Block ads",
                matchCondition: RuleMatchCondition(urlPattern: ".*/ads.*"),
                action: .block(statusCode: 403)
            ))

            let blocked = try await harness.get("/analytics/collect")
            let visible = try await harness.get("/ads/banner")
            #expect(blocked.status == 403)
            #expect(visible.status == 403)

            try await Task.sleep(for: .milliseconds(300))
            let paths = await harness.capturedTransactions().map(\.request.url.path)
            #expect(!paths.contains("/analytics/collect"))
            #expect(paths.contains("/ads/banner"))
        }
    }

    @Test("A Block rule scoped to an application blocks that process only")
    func blockScopedToClientApplication() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            await harness.addRule(ProxyRule(
                name: "Block curl",
                matchCondition: RuleMatchCondition(urlPattern: ".*/ads.*", clientApplication: "curl"),
                action: .block(statusCode: 403)
            ))

            // A separate curl process is identified through the OS connection table. A very
            // short-lived process can finish before the table lists its socket, so the lookup
            // is allowed a few attempts before the test concludes it was not identified.
            var fromCurl = try await harness.curlStatus(path: "/ads/banner")
            var attempts = 1
            while fromCurl != 403, attempts < 4 {
                attempts += 1
                fromCurl = try await harness.curlStatus(path: "/ads/banner")
            }
            #expect(fromCurl == 403)

            // The test process itself is the proxy's own pid, so it is never identified and
            // an application-scoped rule does not fire for it.
            let inProcess = try await harness.get("/ads/banner")
            #expect(inProcess.status != 403)
        }
    }

    @Test("SOCKS5 destinations honor Block rules and the listener loop guard")
    func socks5AppliesConnectPolicy() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let socksPort = try await harness.startSOCKSListener()
            let originPort = harness.originPort
            await harness.addRule(ProxyRule(
                name: "Block origin",
                matchCondition: RuleMatchCondition(urlPattern: ".*127\\.0\\.0\\.1:\(originPort).*"),
                action: .block(statusCode: 403)
            ))

            let blocked = try await Task.detached {
                try SOCKS5TestClient.connectReply(socksPort: socksPort, destinationIPv4: [127, 0, 0, 1], destinationPort: originPort)
            }.value
            #expect(blocked.count >= 2 && blocked[1] == 0x02)

            let loop = try await Task.detached {
                try SOCKS5TestClient.connectReply(socksPort: socksPort, destinationIPv4: [127, 0, 0, 1], destinationPort: socksPort)
            }.value
            #expect(loop.count >= 2 && loop[1] == 0x02)
        }
    }

    @Test("A SOCKS5 client that offers no usable method is refused")
    func socks5RefusesUnsupportedMethods() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let socksPort = try await harness.startSOCKSListener()

            let reply = try await Task.detached {
                try SOCKS5TestClient.greetingReply(socksPort: socksPort, methods: [0x02])
            }.value

            #expect(reply == [0x05, 0xFF])
        }
    }

    @Test("An emulator's 10.0.2.2 host alias reaches the Mac's loopback server")
    func emulatorHostAliasReachesLoopback() async throws {
        let onAliasSubnet = RootCADownloadServer.lanIPv4Addresses().contains { $0.hasPrefix("10.0.2.") }
        try await MapLocalLoopbackHarness.run { harness in
            guard !onAliasSubnet else {
                return
            }
            let response = try await harness.getViaEmulatorAlias("/live")

            #expect(response.status == 200)
            #expect(response.body == Data("origin:/live".utf8))
            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions().first { $0.request.url.host() == "10.0.2.2" }
            #expect(captured?.state == .completed)

            let loop = try await harness.connectToOwnPortViaEmulatorAlias()
            #expect(loop.status == 508)
        }
    }

    @Test("DNS Spoofing connects to another address and keeps the request's host")
    func dnsSpoofingKeepsHost() async throws {
        let host = "spoof-\(UUID().uuidString.prefix(8).lowercased()).rockxy.test"
        DNSSpoofingTable.shared.update([DNSSpoofingEntry(hostPattern: host, address: "127.0.0.1")])
        defer { DNSSpoofingTable.shared.update([]) }
        try await MapLocalLoopbackHarness.run { harness in
            let response = try await harness.get(host: host, path: "/live")

            #expect(response.status == 200)
            #expect(response.body == Data("origin:/live".utf8))
            #expect(response.headerValue("X-Rockxy-Origin-Host") == "\(host):\(harness.originPort)")
            try await Task.sleep(for: .milliseconds(300))
            let captured = await harness.capturedTransactions().first { $0.request.url.host() == host }
            #expect(captured?.state == .completed)
            #expect(captured?.connectionLog?.connectHost == "127.0.0.1")
        }
    }

    @Test("Non-matching URL passes through the proxy to the origin")
    func nonMatchingURLReachesOrigin() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let file = try harness.writeFixtureFile(named: "mapped.txt", contents: Data("LOCAL".utf8))
            await harness.addRule(harness.mapLocalRule(
                name: "Mapped",
                path: "/mapped",
                filePath: file.path
            ))

            let response = try await harness.get("/live")

            #expect(response.status == 200)
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
            #expect(response.body == Data("origin:/live".utf8))
        }
    }

    @Test("Matched rule with a missing local file falls back to the origin")
    func missingLocalFileFallsBackToOrigin() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let missingPath = harness.fixtureDirectory
                .appendingPathComponent("does-not-exist-\(UUID().uuidString).json").path
            await harness.addRule(harness.mapLocalRule(
                name: "Broken Mapping",
                path: "/fallback",
                filePath: missingPath,
                statusCode: 201
            ))

            let response = try await harness.get("/fallback")

            // A broken mapping degrades to normal traffic rather than a synthesized error.
            #expect(response.status == 200)
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
            #expect(response.body == Data("origin:/fallback".utf8))
        }
    }

    @Test("Binary file is served byte-for-byte with a recomputed Content-Length")
    func binaryFileServedExactly() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let bytes = Data([0x00, 0x01, 0xFF, 0x7F, 0x89, 0x50, 0x4E, 0x47])
            let file = try harness.writeFixtureFile(named: "payload.bin", contents: bytes)
            await harness.addRule(harness.mapLocalRule(
                name: "Binary",
                path: "/payload",
                filePath: file.path,
                statusCode: 200
            ))

            let response = try await harness.get("/payload")

            #expect(response.status == 200)
            #expect(response.body == bytes)
            #expect(response.headerValue("Content-Length") == "8")
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
        }
    }

    @Test("Empty file is served with a zero Content-Length")
    func emptyFileServed() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let file = try harness.writeFixtureFile(named: "empty.txt", contents: Data())
            await harness.addRule(harness.mapLocalRule(
                name: "Empty",
                path: "/empty",
                filePath: file.path,
                // Use a body-capable status so the wire-level assertion can verify Rockxy's
                // recomputed zero length. HTTP clients are allowed to strip Content-Length
                // from 204 No Content responses regardless of the handler's payload headers.
                statusCode: 200
            ))

            let response = try await harness.get("/empty")

            #expect(response.status == 200)
            #expect(response.body.isEmpty)
            #expect(response.headerValue("Content-Length") == "0")
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
        }
    }

    @Test("Directory mapping serves a nested subpath from the local directory")
    func directoryMappingServesSubpath() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            _ = try harness.writeFixtureFile(
                named: "app.js",
                contents: Data("console.log('local');".utf8)
            )
            await harness.addRule(harness.mapLocalDirectoryRule(
                name: "Assets",
                pathPrefix: "/assets",
                directoryPath: harness.fixtureDirectory.path
            ))

            let response = try await harness.get("/assets/app.js")

            #expect(response.status == 200)
            #expect(response.body == Data("console.log('local');".utf8))
            #expect(response.headerValue("Content-Type") == "application/javascript")
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
        }
    }

    @Test("Directory mapping with a missing subpath falls back to the origin")
    func directoryMappingMissingFallsBack() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            await harness.addRule(harness.mapLocalDirectoryRule(
                name: "Assets",
                pathPrefix: "/assets",
                directoryPath: harness.fixtureDirectory.path
            ))

            let response = try await harness.get("/assets/missing.js")

            #expect(response.status == 200)
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
            #expect(response.body == Data("origin:/assets/missing.js".utf8))
        }
    }

    @Test("First matching rule wins when several rules match the same URL")
    func firstMatchOrderIsHonored() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let firstFile = try harness.writeFixtureFile(named: "first.txt", contents: Data("FIRST".utf8))
            let secondFile = try harness.writeFixtureFile(named: "second.txt", contents: Data("SECOND".utf8))

            // Both rules match /ordered; the earlier-installed rule must win.
            await harness.addRule(harness.mapLocalRule(
                name: "First",
                path: "/ordered",
                filePath: firstFile.path,
                statusCode: 201
            ))
            await harness.addRule(harness.mapLocalRule(
                name: "Second",
                path: "/ordered",
                filePath: secondFile.path,
                statusCode: 202
            ))

            let response = try await harness.get("/ordered")

            #expect(response.status == 201)
            #expect(response.body == Data("FIRST".utf8))
        }
    }

    @Test("Trailing ? wildcard maps a one-character path but lets a trailing query reach the origin")
    func trailingQuestionMarkWildcardQueryReachesOrigin() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let file = try harness.writeFixtureFile(named: "item.txt", contents: Data("MAPPED".utf8))
            // Authored wildcard `/api/item?` (single-character `?`), includeSubpaths = false.
            await harness.addRule(harness.mapLocalRule(
                name: "Item",
                path: "/api/item?",
                filePath: file.path
            ))

            // `item` + exactly one character maps locally.
            let mapped = try await harness.get("/api/items")
            #expect(mapped.status == 200)
            #expect(mapped.body == Data("MAPPED".utf8))
            #expect(mapped.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)

            // Two characters is not one character — reaches the origin.
            let twoChar = try await harness.get("/api/itemss")
            #expect(twoChar.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")

            // The wildcard already consumed the boundary character, so a trailing query must NOT
            // map — it reaches the origin (the validated failure #1).
            let query = try await harness.get("/api/items?x=1")
            #expect(query.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
            #expect(query.body == Data("origin:/api/items".utf8))
        }
    }

    @Test("A local file containing a full HTTP message serves that status, headers, and body")
    func fullHTTPMessageFileIsServed() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let message = Data("""
            HTTP/1.1 203 Non-Authoritative Information\r
            Content-Type: application/problem+json\r
            Set-Cookie: session=one\r
            X-Map-Local: Rockxy\r
            \r
            {"from":"file"}
            """.utf8)
            let file = try harness.writeFixtureFile(named: "message.http", contents: message)
            // The rule's own status (500) must be ignored — the file message wins.
            await harness.addRule(harness.mapLocalRule(
                name: "Message",
                path: "/message",
                filePath: file.path,
                statusCode: 500
            ))

            let response = try await harness.get("/message")

            #expect(response.status == 203)
            #expect(response.body == Data(#"{"from":"file"}"#.utf8))
            #expect(response.headerValue("Content-Type") == "application/problem+json")
            #expect(response.headerValue("X-Map-Local") == "Rockxy")
            #expect(response.headerValue("Set-Cookie") == "session=one")
            // Content-Length is recomputed from the served body, not trusted from the file.
            #expect(response.headerValue("Content-Length") == "\(Data(#"{"from":"file"}"#.utf8).count)")
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
        }
    }

    @Test("A rule with an out-of-range status falls back to the origin instead of emitting it")
    func invalidStatusFallsBackToOrigin() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            let file = try harness.writeFixtureFile(named: "raw.txt", contents: Data("RAW".utf8))
            // 999 is not a valid HTTP status; a programmatic/imported rule must not emit it.
            await harness.addRule(harness.mapLocalRule(
                name: "Invalid Status",
                path: "/invalid-status",
                filePath: file.path,
                statusCode: 999
            ))

            let response = try await harness.get("/invalid-status")

            #expect(response.status == 200)
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
            #expect(response.body == Data("origin:/invalid-status".utf8))
        }
    }

    @Test("Directory mapping does not synthesize index.html for the mapped root")
    func directoryRootDoesNotSynthesizeIndex() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            _ = try harness.writeFixtureFile(named: "index.html", contents: Data("<html>local</html>".utf8))
            await harness.addRule(harness.mapLocalDirectoryRule(
                name: "Assets",
                pathPrefix: "/assets",
                directoryPath: harness.fixtureDirectory.path
            ))

            // `/assets/` resolves to an empty suffix (the directory root). No index synthesis —
            // the request falls through to the origin (validated failure #2).
            let response = try await harness.get("/assets/")

            #expect(response.status == 200)
            #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
            #expect(response.body == Data("origin:/assets/".utf8))
        }
    }

    @Test("Concurrent directory hits and missing-target fallbacks all complete without hanging")
    func concurrentDirectoryHitsAndFallbacks() async throws {
        try await MapLocalLoopbackHarness.run { harness in
            // Six real files plus six missing targets, interleaved across concurrent requests.
            for index in 0 ..< 6 {
                _ = try harness.writeFixtureFile(
                    named: "file\(index).txt",
                    contents: Data("local-\(index)".utf8)
                )
            }
            await harness.addRule(harness.mapLocalDirectoryRule(
                name: "Assets",
                pathPrefix: "/assets",
                directoryPath: harness.fixtureDirectory.path
            ))

            try await withThrowingTaskGroup(of: (Int, Bool, ProxyHTTPResponse).self) { group in
                for index in 0 ..< 12 {
                    let isHit = index % 2 == 0
                    let fileIndex = index / 2
                    group.addTask {
                        let path = isHit ? "/assets/file\(fileIndex).txt" : "/assets/missing\(index).txt"
                        let response = try await harness.get(path)
                        return (fileIndex, isHit, response)
                    }
                }

                var completed = 0
                for try await (fileIndex, isHit, response) in group {
                    completed += 1
                    if isHit {
                        // Directory hit served from the local file, origin never reached.
                        #expect(response.status == 200)
                        #expect(response.body == Data("local-\(fileIndex)".utf8))
                        #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == nil)
                    } else {
                        // Missing target falls back to the origin.
                        #expect(response.headerValue(MapLocalLoopbackHarness.originMarkerHeader) == "true")
                    }
                }
                // Every one of the 12 concurrent requests completed — no serialization deadlock.
                #expect(completed == 12)
            }
        }
    }
}

// MARK: - MapLocalLoopbackHarness

/// Owns an isolated `RuleEngine`, a real `ProxyServer`, a deterministic local origin
/// fixture, and a temp directory for Map Local files. Every collaborator is instance-scoped
/// so the harness never mutates shared rule state or the macOS system proxy.
private actor MapLocalLoopbackHarness {
    // MARK: Lifecycle

    private init(
        engine: RuleEngine,
        proxyServer: ProxyServer,
        proxyPort: Int,
        origin: MapLocalOriginFixtureServer,
        fixtureDirectory: URL,
        recorder: LoopbackTransactionRecorder
    ) {
        self.engine = engine
        self.proxyServer = proxyServer
        self.proxyPort = proxyPort
        self.origin = origin
        self.fixtureDirectory = fixtureDirectory
        self.recorder = recorder
    }

    // MARK: Internal

    static let originMarkerHeader = "X-Rockxy-Origin"

    nonisolated let fixtureDirectory: URL

    static func start() async throws -> MapLocalLoopbackHarness {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MapLocalLoopback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

        let origin = try await MapLocalOriginFixtureServer.start()
        let engine = RuleEngine()
        let proxyPort = try Self.reserveLoopbackPort()
        let recorder = LoopbackTransactionRecorder()
        let proxyServer = ProxyServer(
            configuration: ProxyConfiguration(port: proxyPort, listenAddress: "127.0.0.1", listenIPv6: false),
            ruleEngine: engine,
            onTransactionComplete: { recorder.record($0) }
        )

        do {
            try await proxyServer.start()
        } catch {
            await origin.stop()
            try? FileManager.default.removeItem(at: fixtureDirectory)
            throw error
        }

        return MapLocalLoopbackHarness(
            engine: engine,
            proxyServer: proxyServer,
            proxyPort: proxyPort,
            origin: origin,
            fixtureDirectory: fixtureDirectory,
            recorder: recorder
        )
    }

    /// Starts a harness, runs the body against it, and always awaits full teardown (both
    /// servers stopped, temp fixtures removed) — even if the body throws.
    static func run(_ body: (MapLocalLoopbackHarness) async throws -> Void) async throws {
        let harness = try await start()
        do {
            try await body(harness)
        } catch {
            await harness.stop()
            throw error
        }
        await harness.stop()
    }

    func stop() async {
        await proxyServer.stop()
        await origin.stop()
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    func capturedTransactions() -> [HTTPTransaction] {
        recorder.snapshot()
    }

    func addRule(_ rule: ProxyRule) async {
        await engine.addRule(rule)
    }

    /// HTTP status curl reports for `path` fetched through the proxy from its own process.
    func curlStatus(path: String) async throws -> Int {
        let port = proxyPort
        let url = origin.absoluteURLString(path: path)
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = [
                "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "10",
                "--proxy", "http://127.0.0.1:\(port)", url,
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Int(String(decoding: data, as: UTF8.self)) ?? -1
        }.value
    }

    /// Builds a Map Local rule whose wildcard pattern matches exactly one absolute request URL
    /// (`http://127.0.0.1:<originPort><path>`), anchored so sibling paths do not match.
    nonisolated func mapLocalRule(
        name: String,
        path: String,
        filePath: String,
        statusCode: Int = 200,
        responseHeaders: [HTTPHeader] = []
    )
        -> ProxyRule
    {
        let absolute = origin.absoluteURLString(path: path)
        return ProxyRule(
            name: name,
            matchCondition: RuleMatchCondition(
                urlPattern: absolute,
                sourceURLPattern: absolute,
                matchType: .wildcard,
                includeSubpaths: false
            ),
            action: .mapLocal(
                filePath: filePath,
                statusCode: statusCode,
                responseHeaders: responseHeaders
            )
        )
    }

    /// Builds a Map Local *directory* rule whose authored wildcard matches
    /// `http://127.0.0.1:<originPort>/<prefix>/*` and serves matching subpaths from
    /// `directoryPath`.
    nonisolated func mapLocalDirectoryRule(
        name: String,
        pathPrefix: String,
        directoryPath: String,
        statusCode: Int = 200
    )
        -> ProxyRule
    {
        let base = origin.absoluteURLString(path: pathPrefix)
        let authored = base.hasSuffix("/") ? "\(base)*" : "\(base)/*"
        return ProxyRule(
            name: name,
            matchCondition: RuleMatchCondition(
                urlPattern: authored,
                sourceURLPattern: authored,
                matchType: .wildcard,
                includeSubpaths: true
            ),
            action: .mapLocal(
                filePath: directoryPath,
                statusCode: statusCode,
                isDirectory: true
            )
        )
    }

    nonisolated func writeFixtureFile(named name: String, contents: Data) throws -> URL {
        let url = fixtureDirectory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    /// Sends an explicit-proxy `GET` for `path` and returns the parsed response.
    ///
    /// Uses a raw NIO HTTP/1.1 client that connects straight to the proxy and writes an
    /// absolute-form request line (`GET http://127.0.0.1:<originPort><path> HTTP/1.1`). This
    /// avoids URLSession's automatic loopback-proxy bypass, so the request is guaranteed to
    /// traverse the proxy and exercise the rule engine.
    nonisolated func absoluteURLString(path: String) -> String {
        origin.absoluteURLString(path: path)
    }

    func get(_ path: String) async throws -> ProxyHTTPResponse {
        let absolute = origin.absoluteURLString(path: path)
        return try await ProxyHTTPClient.get(
            absoluteURL: absolute,
            host: origin.host,
            originPort: origin.boundPort,
            proxyHost: "127.0.0.1",
            proxyPort: proxyPort
        )
    }

    /// Opens the SOCKS5 listener on a free loopback port and returns it.
    func startSOCKSListener() async throws -> Int {
        let port = try Self.reserveLoopbackPort()
        if let failure = await proxyServer.updateSOCKSListener(port: port) {
            throw MapLocalLoopbackError.connectionFailed("SOCKS bind failed: \(failure)")
        }
        return port
    }

    nonisolated var originPort: Int {
        origin.boundPort
    }

    /// Opens a reverse proxy listener that forwards to the origin fixture and returns its port.
    func startReverseProxy() async throws -> Int {
        let port = try Self.reserveLoopbackPort()
        let target = ReverseProxyTarget(
            id: UUID(),
            localPort: port,
            scheme: .http,
            host: origin.host,
            port: origin.boundPort,
            preserveHostHeader: false
        )
        let failures = await proxyServer.updateReverseProxies([target])
        guard failures.isEmpty else {
            throw MapLocalLoopbackError.connectionFailed("reverse proxy bind failed: \(failures)")
        }
        return port
    }

    /// Sends an origin-form request straight to a reverse proxy listener, like a client
    /// whose base URL was changed to `http://127.0.0.1:<port>`.
    func getViaReverseProxy(port: Int, path: String) async throws -> ProxyHTTPResponse {
        try await ProxyHTTPClient.get(
            absoluteURL: path,
            host: "127.0.0.1",
            originPort: port,
            proxyHost: "127.0.0.1",
            proxyPort: port
        )
    }

    /// Sends `GET http://10.0.2.2:<originPort><path>` the way an Android emulator names the Mac.
    func getViaEmulatorAlias(_ path: String) async throws -> ProxyHTTPResponse {
        try await ProxyHTTPClient.get(
            absoluteURL: "http://10.0.2.2:\(origin.boundPort)\(path)",
            host: "10.0.2.2",
            originPort: origin.boundPort,
            proxyHost: "127.0.0.1",
            proxyPort: proxyPort
        )
    }

    /// CONNECT to the emulator alias of Rockxy's own port, which must be refused as a loop.
    func connectToOwnPortViaEmulatorAlias() async throws -> ProxyHTTPResponse {
        try await ProxyHTTPClient.get(
            absoluteURL: "10.0.2.2:\(proxyPort)",
            host: "10.0.2.2",
            originPort: proxyPort,
            proxyHost: "127.0.0.1",
            proxyPort: proxyPort,
            method: .CONNECT
        )
    }

    nonisolated var listenerPort: Int {
        proxyPort
    }

    /// A loopback port nothing listens on, for connection-failure tests.
    func unusedLoopbackPort() throws -> Int {
        try Self.reserveLoopbackPort()
    }

    /// Sends `GET http://<host>:<port><path>` to an arbitrary port.
    func get(host: String, port: Int, path: String) async throws -> ProxyHTTPResponse {
        try await ProxyHTTPClient.get(
            absoluteURL: "http://\(host):\(port)\(path)",
            host: host,
            originPort: port,
            proxyHost: "127.0.0.1",
            proxyPort: proxyPort
        )
    }

    /// Sends `GET http://<host>:<originPort><path>`, for a host only DNS Spoofing can reach.
    func get(host: String, path: String) async throws -> ProxyHTTPResponse {
        try await ProxyHTTPClient.get(
            absoluteURL: "http://\(host):\(origin.boundPort)\(path)",
            host: host,
            originPort: origin.boundPort,
            proxyHost: "127.0.0.1",
            proxyPort: proxyPort
        )
    }

    func post(_ path: String, json: String) async throws -> ProxyHTTPResponse {
        try await ProxyHTTPClient.get(
            absoluteURL: origin.absoluteURLString(path: path),
            host: origin.host,
            originPort: origin.boundPort,
            proxyHost: "127.0.0.1",
            proxyPort: proxyPort,
            method: .POST,
            body: Data(json.utf8)
        )
    }

    // MARK: Private

    private let engine: RuleEngine
    private let proxyServer: ProxyServer
    private let proxyPort: Int
    private let origin: MapLocalOriginFixtureServer
    private let recorder: LoopbackTransactionRecorder

    private static func reserveLoopbackPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw MapLocalLoopbackError.socket("Unable to create reservation socket.")
        }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

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
            throw MapLocalLoopbackError.socket("Unable to bind reservation socket.")
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw MapLocalLoopbackError.socket("Unable to inspect reservation socket port.")
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

// MARK: - MapLocalOriginFixtureServer

/// Minimal deterministic origin. Any request is answered `200` with body `origin:<path>` and a
/// distinctive `X-Rockxy-Origin: true` marker header so tests can prove a request reached the
/// origin rather than being served from a local file.
private actor MapLocalOriginFixtureServer {
    // MARK: Internal

    nonisolated let host = "127.0.0.1"
    nonisolated let portBox = MapLocalPortBox()

    nonisolated var boundPort: Int {
        portBox.value
    }

    static func start() async throws -> MapLocalOriginFixtureServer {
        let server = MapLocalOriginFixtureServer()
        try await server.startListening()
        return server
    }

    nonisolated func absoluteURLString(path: String) -> String {
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        return "http://\(host):\(boundPort)\(normalized)"
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
    }

    // MARK: Private

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    private func startListening() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        eventLoopGroup = group
        do {
            let channel = try await ServerBootstrap(group: group)
                .serverChannelOption(.backlog, value: 16)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline
                            .addHandler(MapLocalOriginHandler(markerHeader: MapLocalLoopbackHarness.originMarkerHeader))
                    }
                }
                .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .bind(host: host, port: 0)
                .get()
            guard let boundPort = channel.localAddress?.port else {
                try await channel.close().get()
                throw MapLocalLoopbackError.socket("Unable to inspect origin fixture port.")
            }
            serverChannel = channel
            portBox.value = boundPort
        } catch {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
            throw error
        }
    }
}

// MARK: - MapLocalPortBox

private final class MapLocalPortBox: @unchecked Sendable {
    // MARK: Internal

    var value: Int {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }

    // MARK: Private

    private let lock = NSLock()
    private var storedValue = 0
}

// MARK: - LoopbackTransactionRecorder

private final class LoopbackTransactionRecorder: @unchecked Sendable {
    func record(_ transaction: HTTPTransaction) {
        lock.lock()
        transactions.append(transaction)
        lock.unlock()
    }

    func snapshot() -> [HTTPTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return transactions
    }

    private let lock = NSLock()
    private var transactions: [HTTPTransaction] = []
}

// MARK: - MapLocalOriginHandler

private final class MapLocalOriginHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(markerHeader: String) {
        self.markerHeader = markerHeader
    }

    // MARK: Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            requestPath = URLComponents(string: head.uri)?.path ?? head.uri
            receivedHost = head.headers.first(name: "Host")
        case .body:
            break
        case .end:
            respond(context: context)
            requestPath = nil
        }
    }

    // MARK: Private

    private let markerHeader: String
    private var requestPath: String?
    private var receivedHost: String?

    private func respond(context: ChannelHandlerContext) {
        let path = requestPath ?? "/"
        // Simulates an origin that drops the connection before writing any response byte.
        if path == "/close-without-response" {
            context.close(promise: nil)
            return
        }
        var buffer = context.channel.allocator.buffer(capacity: path.utf8.count + 8)
        buffer.writeString("origin:\(path)")
        // A 20 KB body, large enough for bandwidth pacing to be measurable.
        if path == "/large" {
            buffer.writeRepeatingByte(UInt8(ascii: "x"), count: 20_000)
        }

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: markerHeader, value: "true")
        headers.add(name: "X-Rockxy-Origin-Host", value: receivedHost ?? "")
        headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

// MARK: - ProxyHTTPResponse

/// The parsed result of a single proxied HTTP exchange.
private struct ProxyHTTPResponse: Sendable {
    let status: Int
    let headers: HTTPHeaders
    let body: Data

    /// Case-insensitive header lookup (first occurrence).
    func headerValue(_ name: String) -> String? {
        headers.first(name: name)
    }
}

// MARK: - ProxyHTTPClient

/// Minimal explicit-proxy HTTP/1.1 client built on NIO. Connects directly to the proxy and
/// writes an absolute-form request line so the request always traverses the proxy — unlike
/// `URLSession`, which silently bypasses proxies for loopback destinations.
private enum ProxyHTTPClient {
    static func get(
        absoluteURL: String,
        host: String,
        originPort: Int,
        proxyHost: String,
        proxyPort: Int,
        method: HTTPMethod = .GET,
        body: Data? = nil
    )
        async throws -> ProxyHTTPResponse
    {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(host):\(originPort)")
        headers.add(name: "Connection", value: "close")
        if let body {
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Content-Length", value: String(body.count))
        }
        let requestHead = HTTPRequestHead(version: .http1_1, method: method, uri: absoluteURL, headers: headers)

        let promise = group.next().makePromise(of: ProxyHTTPResponse.self)
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(
                        ProxyClientResponseHandler(requestHead: requestHead, body: body, promise: promise)
                    )
                }
            }

        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: proxyHost, port: proxyPort).get()
        } catch {
            promise.fail(error)
            try? await group.shutdownGracefully()
            throw MapLocalLoopbackError.connectionFailed(error.localizedDescription)
        }

        // Fail-safe so a stuck proxy cannot hang the test indefinitely.
        let timeout = channel.eventLoop.scheduleTask(in: .seconds(12)) {
            promise.fail(MapLocalLoopbackError.timeout)
        }

        do {
            let response = try await promise.futureResult.get()
            timeout.cancel()
            try? await channel.close().get()
            try? await group.shutdownGracefully()
            return response
        } catch {
            timeout.cancel()
            try? await channel.close().get()
            try? await group.shutdownGracefully()
            throw error
        }
    }
}

// MARK: - ProxyClientResponseHandler

private final class ProxyClientResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(requestHead: HTTPRequestHead, body: Data? = nil, promise: EventLoopPromise<ProxyHTTPResponse>) {
        self.requestHead = requestHead
        requestBody = body
        self.promise = promise
    }

    // MARK: Internal

    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    func channelActive(context: ChannelHandlerContext) {
        context.write(wrapOutboundOut(.head(requestHead)), promise: nil)
        if let requestBody {
            var buffer = context.channel.allocator.buffer(capacity: requestBody.count)
            buffer.writeBytes(requestBody)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            status = Int(head.status.code)
            headers = head.headers
        case var .body(buffer):
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            promise.succeed(ProxyHTTPResponse(status: status, headers: headers, body: body))
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }

    // MARK: Private

    private let requestHead: HTTPRequestHead
    private let requestBody: Data?
    private let promise: EventLoopPromise<ProxyHTTPResponse>
    private var status = 0
    private var headers = HTTPHeaders()
    private var body = Data()
}

// MARK: - MapLocalLoopbackError

private enum MapLocalLoopbackError: Error, CustomStringConvertible {
    case socket(String)
    case connectionFailed(String)
    case timeout

    // MARK: Internal

    var description: String {
        switch self {
        case let .socket(message):
            message
        case let .connectionFailed(message):
            "Unable to connect to the proxy: \(message)"
        case .timeout:
            "Timed out waiting for the proxied response."
        }
    }
}

// MARK: - SOCKS5TestClient

/// Blocking POSIX SOCKS5 client used only by the loopback tests.
private enum SOCKS5TestClient {
    static func connectReply(socksPort: Int, destinationIPv4: [UInt8], destinationPort: Int) throws -> [UInt8] {
        let fd = try connect(port: socksPort)
        defer { close(fd) }
        try send(fd, [0x05, 0x01, 0x00])
        _ = try receive(fd, count: 2)
        try send(fd, [0x05, 0x01, 0x00, 0x01] + destinationIPv4 + [UInt8(destinationPort >> 8), UInt8(destinationPort & 0xFF)])
        return try receive(fd, count: 10)
    }

    static func greetingReply(socksPort: Int, methods: [UInt8]) throws -> [UInt8] {
        let fd = try connect(port: socksPort)
        defer { close(fd) }
        try send(fd, [0x05, UInt8(methods.count)] + methods)
        return try receive(fd, count: 2)
    }

    static func exchange(
        socksPort: Int,
        destinationIPv4: [UInt8],
        destinationPort: Int,
        payload: String
    ) throws -> String {
        let fd = try connect(port: socksPort)
        defer { close(fd) }
        try send(fd, [0x05, 0x01, 0x00])
        guard try receive(fd, count: 2) == [0x05, 0x00] else {
            throw MapLocalLoopbackError.connectionFailed("SOCKS greeting refused")
        }
        try send(fd, [0x05, 0x01, 0x00, 0x01] + destinationIPv4 + [UInt8(destinationPort >> 8), UInt8(destinationPort & 0xFF)])
        let reply = try receive(fd, count: 10)
        guard reply.count == 10, reply[1] == 0x00 else {
            throw MapLocalLoopbackError.connectionFailed("SOCKS CONNECT refused: \(reply)")
        }
        try send(fd, Array(payload.utf8))
        var response: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = recv(fd, &chunk, chunk.count, 0)
            if count <= 0 {
                break
            }
            response.append(contentsOf: chunk[0 ..< count])
        }
        return String(decoding: response, as: UTF8.self)
    }

    private static func connect(port: Int) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw MapLocalLoopbackError.socket("socket() failed")
        }
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw MapLocalLoopbackError.connectionFailed("connect() failed")
        }
        return fd
    }

    private static func send(_ fd: Int32, _ bytes: [UInt8]) throws {
        let sent = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, bytes.count, 0) }
        guard sent == bytes.count else {
            throw MapLocalLoopbackError.connectionFailed("send() failed")
        }
    }

    private static func receive(_ fd: Int32, count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var received = 0
        while received < count {
            let result = buffer.withUnsafeMutableBytes {
                recv(fd, $0.baseAddress! + received, count - received, 0)
            }
            if result <= 0 {
                break
            }
            received += result
        }
        return Array(buffer[0 ..< received])
    }
}
