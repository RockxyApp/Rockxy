import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

// Regression tests for `RuleAction` in the core rule engine layer.

struct RuleActionTests {
    @Test("Block action returns correct status code")
    func blockAction() async throws {
        let engine = RuleEngine()
        await engine.addRule(ProxyRule(
            name: "Block",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*blocked\\.com.*"),
            action: .block(statusCode: 403)
        ))

        let url = try #require(URL(string: "https://blocked.com/path"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .block(statusCode) = result {
            #expect(statusCode == 403)
        } else {
            Issue.record("Expected .block action")
        }
    }

    @Test("MapLocal action returns file path")
    func mapLocalAction() async throws {
        let engine = RuleEngine()
        await engine.addRule(ProxyRule(
            name: "Map Local",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*api\\.test.*"),
            action: .mapLocal(filePath: "/tmp/mock.json")
        ))

        let url = try #require(URL(string: "https://api.test/data"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .mapLocal(filePath, statusCode, isDirectory) = result {
            #expect(filePath == "/tmp/mock.json")
            #expect(statusCode == 200)
            #expect(isDirectory == false)
        } else {
            Issue.record("Expected .mapLocal action")
        }
    }

    @Test("MapRemote action returns target URL")
    func mapRemoteAction() async throws {
        let engine = RuleEngine()
        await engine.addRule(ProxyRule(
            name: "Map Remote",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*old-api\\.com.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "https", host: "new-api.com", path: "/v2"
            ))
        ))

        let url = try #require(URL(string: "https://old-api.com/data"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .mapRemote(config) = result {
            #expect(config.host == "new-api.com")
            #expect(config.path == "/v2")
        } else {
            Issue.record("Expected .mapRemote action")
        }
    }

    @Test("Throttle action returns delay in milliseconds")
    func throttleAction() async throws {
        let engine = RuleEngine()
        await engine.addRule(ProxyRule(
            name: "Throttle",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*slow\\.com.*"),
            action: .throttle(delayMs: 2_000)
        ))

        let url = try #require(URL(string: "https://slow.com/api"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .throttle(delayMs) = result {
            #expect(delayMs == 2_000)
        } else {
            Issue.record("Expected .throttle action")
        }
    }

    @Test("ModifyHeader add operation")
    func modifyHeaderAddAction() async throws {
        let engine = RuleEngine()
        let operation = HeaderOperation(
            type: .add,
            headerName: "X-Debug",
            headerValue: "true"
        )
        await engine.addRule(ProxyRule(
            name: "Add Header",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .modifyHeader(operations: [operation])
        ))

        let url = try #require(URL(string: "https://example.com/test"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .modifyHeader(ops) = result {
            #expect(ops.count == 1)
            #expect(ops[0].type == .add)
            #expect(ops[0].headerName == "X-Debug")
            #expect(ops[0].headerValue == "true")
        } else {
            Issue.record("Expected .modifyHeader action")
        }
    }

    @Test("ModifyHeader remove operation")
    func modifyHeaderRemoveAction() async throws {
        let engine = RuleEngine()
        let operation = HeaderOperation(
            type: .remove,
            headerName: "Authorization",
            headerValue: nil
        )
        await engine.addRule(ProxyRule(
            name: "Remove Auth",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .modifyHeader(operations: [operation])
        ))

        let url = try #require(URL(string: "https://example.com/test"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .modifyHeader(ops) = result {
            #expect(ops.count == 1)
            #expect(ops[0].type == .remove)
            #expect(ops[0].headerName == "Authorization")
        } else {
            Issue.record("Expected .modifyHeader action")
        }
    }

    @Test("ModifyHeader replace operation")
    func modifyHeaderReplaceAction() async throws {
        let engine = RuleEngine()
        let operation = HeaderOperation(
            type: .replace,
            headerName: "Content-Type",
            headerValue: "text/plain"
        )
        await engine.addRule(ProxyRule(
            name: "Replace Content-Type",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*"),
            action: .modifyHeader(operations: [operation])
        ))

        let url = try #require(URL(string: "https://example.com/test"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .modifyHeader(ops) = result {
            #expect(ops.count == 1)
            #expect(ops[0].type == .replace)
            #expect(ops[0].headerValue == "text/plain")
        } else {
            Issue.record("Expected .modifyHeader action")
        }
    }

    @Test("Breakpoint action matches")
    func breakpointAction() async throws {
        let engine = RuleEngine()
        await engine.addRule(ProxyRule(
            name: "Breakpoint",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: ".*debug\\.com.*"),
            action: .breakpoint()
        ))

        let url = try #require(URL(string: "https://debug.com/api"))
        let result = await engine.evaluate(method: "POST", url: url, headers: [])

        if case .breakpoint = result {
            // pass
        } else {
            Issue.record("Expected .breakpoint action")
        }
    }

    @Test("Combined URL + method filter")
    func combinedFilters() async throws {
        let engine = RuleEngine()
        await engine.addRule(ProxyRule(
            name: "Block POST to API",
            isEnabled: true,
            matchCondition: RuleMatchCondition(
                urlPattern: ".*api\\.example\\.com.*",
                method: "POST"
            ),
            action: .block(statusCode: 405)
        ))

        let url = try #require(URL(string: "https://api.example.com/data"))

        let postResult = await engine.evaluate(method: "POST", url: url, headers: [])
        let getResult = await engine.evaluate(method: "GET", url: url, headers: [])

        #expect(postResult != nil)
        #expect(getResult == nil)
    }

    @Test("No rules returns nil")
    func emptyEngine() async throws {
        let engine = RuleEngine()
        let url = try #require(URL(string: "https://example.com"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])
        #expect(result == nil)
    }

    @Test("Rule action Codable roundtrip")
    func actionCodableRoundtrip() throws {
        let actions: [RuleAction] = [
            .block(statusCode: 403),
            .mapLocal(filePath: "/tmp/test.json"),
            .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "https",
                host: "mirror.example.com",
                path: "/api"
            )),
            .throttle(delayMs: 1_500),
            .breakpoint(),
            .modifyHeader(operations: [HeaderOperation(type: .add, headerName: "X-Test", headerValue: "1")]),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for action in actions {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(RuleAction.self, from: data)

            switch (action, decoded) {
            case let (.block(a), .block(b)):
                #expect(a == b)
            case let (.mapLocal(aPath, aStatus, aIsDir), .mapLocal(bPath, bStatus, bIsDir)):
                #expect(aPath == bPath)
                #expect(aStatus == bStatus)
                #expect(aIsDir == bIsDir)
            case let (.mapRemote(a), .mapRemote(b)):
                #expect(a == b)
            case let (.throttle(a), .throttle(b)):
                #expect(a == b)
            case (.breakpoint, .breakpoint):
                break
            case let (.modifyHeader(aOps), .modifyHeader(bOps)):
                #expect(aOps.count == bOps.count)
                for (a, b) in zip(aOps, bOps) {
                    #expect(a.type == b.type)
                    #expect(a.headerName == b.headerName)
                    #expect(a.headerValue == b.headerValue)
                    #expect(a.phase == b.phase)
                }
            default:
                Issue.record("Action type mismatch after decode")
            }
        }
    }

    @Test("MapLocal decodes without statusCode field (backward compat)")
    func mapLocalBackwardCompat() throws {
        let json = """
        {"type":"mapLocal","filePath":"/tmp/old.json"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuleAction.self, from: json)
        if case let .mapLocal(path, code, isDir) = decoded {
            #expect(path == "/tmp/old.json")
            #expect(code == 200)
            #expect(isDir == false)
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    @Test("MapLocal encodes and decodes statusCode")
    func mapLocalStatusCodeRoundtrip() throws {
        let action = RuleAction.mapLocal(filePath: "/tmp/test.json", statusCode: 404)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)
        if case let .mapLocal(path, code, _) = decoded {
            #expect(path == "/tmp/test.json")
            #expect(code == 404)
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    @Test("MapLocal default statusCode is 200")
    func mapLocalDefaultStatusCode() {
        let action = RuleAction.mapLocal(filePath: "/tmp/test.json")
        if case let .mapLocal(_, code, _) = action {
            #expect(code == 200)
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    @Test("MapLocal directory flag defaults to false")
    func mapLocalDefaultIsDirectory() {
        let action = RuleAction.mapLocal(filePath: "/tmp/dir")
        if case let .mapLocal(_, _, isDir) = action {
            #expect(isDir == false)
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    @Test("MapLocal directory flag round-trips through Codable")
    func mapLocalDirectoryRoundtrip() throws {
        let action = RuleAction.mapLocal(filePath: "/tmp/webroot", statusCode: 200, isDirectory: true)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)
        if case let .mapLocal(path, code, isDir) = decoded {
            #expect(path == "/tmp/webroot")
            #expect(code == 200)
            #expect(isDir == true)
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    @Test("MapLocal backward compat: missing isDirectory defaults to false")
    func mapLocalBackwardCompatIsDirectory() throws {
        let json = """
        {"type":"mapLocal","filePath":"/tmp/old.json","statusCode":200}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuleAction.self, from: json)
        if case let .mapLocal(_, _, isDir) = decoded {
            #expect(isDir == false)
        } else {
            Issue.record("Expected .mapLocal")
        }
    }

    // MARK: - Header Modify: Multi-Operation + Phase Tests

    @Test("Multiple operations encode and decode correctly")
    func multipleOperationsRoundtrip() throws {
        let operations = [
            HeaderOperation(type: .add, headerName: "X-Debug", headerValue: "true", phase: .request),
            HeaderOperation(type: .remove, headerName: "Server", headerValue: nil, phase: .response),
            HeaderOperation(type: .replace, headerName: "Cache-Control", headerValue: "no-cache", phase: .both),
        ]
        let action = RuleAction.modifyHeader(operations: operations)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)

        if case let .modifyHeader(decodedOps) = decoded {
            #expect(decodedOps.count == 3)
            #expect(decodedOps[0].type == .add)
            #expect(decodedOps[0].phase == .request)
            #expect(decodedOps[1].type == .remove)
            #expect(decodedOps[1].phase == .response)
            #expect(decodedOps[2].type == .replace)
            #expect(decodedOps[2].phase == .both)
            #expect(decodedOps[2].headerValue == "no-cache")
        } else {
            Issue.record("Expected .modifyHeader")
        }
    }

    @Test("Backward compat: single operation JSON decodes into 1-element array with request phase")
    func backwardCompatSingleOperation() throws {
        let json = """
        {"type":"modifyHeader","operation":{"type":"add","headerName":"X-Test","headerValue":"1"}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuleAction.self, from: json)

        if case let .modifyHeader(ops) = decoded {
            #expect(ops.count == 1)
            #expect(ops[0].type == .add)
            #expect(ops[0].headerName == "X-Test")
            #expect(ops[0].headerValue == "1")
            #expect(ops[0].phase == .request)
        } else {
            Issue.record("Expected .modifyHeader")
        }
    }

    @Test("Backward compat: HeaderOperation without phase defaults to request")
    func backwardCompatMissingPhase() throws {
        let json = """
        {"type":"modifyHeader","operations":[{"type":"remove","headerName":"Authorization"}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuleAction.self, from: json)

        if case let .modifyHeader(ops) = decoded {
            #expect(ops.count == 1)
            #expect(ops[0].phase == .request)
        } else {
            Issue.record("Expected .modifyHeader")
        }
    }

    @Test("Empty operations array roundtrips")
    func emptyOperationsArray() throws {
        let action = RuleAction.modifyHeader(operations: [])
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)

        if case let .modifyHeader(ops) = decoded {
            #expect(ops.isEmpty)
        } else {
            Issue.record("Expected .modifyHeader")
        }
    }

    @Test("Request phase filter returns request and both operations")
    func requestPhaseFilter() {
        let ops = [
            HeaderOperation(type: .add, headerName: "A", headerValue: "1", phase: .request),
            HeaderOperation(type: .add, headerName: "B", headerValue: "2", phase: .response),
            HeaderOperation(type: .add, headerName: "C", headerValue: "3", phase: .both),
        ]
        let filtered = HeaderOperation.requestPhase(from: ops)
        #expect(filtered.count == 2)
        #expect(filtered[0].headerName == "A")
        #expect(filtered[1].headerName == "C")
    }

    @Test("Response phase filter returns response and both operations")
    func responsePhaseFilter() {
        let ops = [
            HeaderOperation(type: .add, headerName: "A", headerValue: "1", phase: .request),
            HeaderOperation(type: .add, headerName: "B", headerValue: "2", phase: .response),
            HeaderOperation(type: .add, headerName: "C", headerValue: "3", phase: .both),
        ]
        let filtered = HeaderOperation.responsePhase(from: ops)
        #expect(filtered.count == 2)
        #expect(filtered[0].headerName == "B")
        #expect(filtered[1].headerName == "C")
    }

    @Test("Phase field encodes and decodes correctly")
    func phaseFieldEncodeDecode() throws {
        let ops = [
            HeaderOperation(type: .add, headerName: "A", headerValue: "1", phase: .response),
            HeaderOperation(type: .remove, headerName: "B", headerValue: nil, phase: .both),
        ]
        let action = RuleAction.modifyHeader(operations: ops)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)

        if case let .modifyHeader(decodedOps) = decoded {
            #expect(decodedOps[0].phase == .response)
            #expect(decodedOps[1].phase == .both)
        } else {
            Issue.record("Expected .modifyHeader")
        }
    }

    @Test("Operations applied in order: later row wins for same header")
    func applyOperationsOrder() {
        var headers = [
            HTTPHeader(name: "X-Test", value: "original"),
        ]
        let ops = [
            HeaderOperation(type: .replace, headerName: "X-Test", headerValue: "first"),
            HeaderOperation(type: .replace, headerName: "X-Test", headerValue: "second"),
        ]
        for op in ops {
            switch op.type {
            case .add:
                if let value = op.headerValue {
                    headers.append(HTTPHeader(name: op.headerName, value: value))
                }
            case .remove:
                headers.removeAll { $0.name.lowercased() == op.headerName.lowercased() }
            case .replace:
                headers.removeAll { $0.name.lowercased() == op.headerName.lowercased() }
                if let value = op.headerValue {
                    headers.append(HTTPHeader(name: op.headerName, value: value))
                }
            }
        }
        #expect(headers.count == 1)
        #expect(headers[0].value == "second")
    }

    @Test("Remove matches header names case-insensitively")
    func mixedCaseHeaderRemove() {
        var headers = [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Authorization", value: "Bearer token"),
        ]
        let op = HeaderOperation(type: .remove, headerName: "content-type", headerValue: nil)
        headers.removeAll { $0.name.lowercased() == op.headerName.lowercased() }
        #expect(headers.count == 1)
        #expect(headers[0].name == "Authorization")
    }

    @Test("Both phase appears in both request and response filter results")
    func bothPhaseAffectsBothPaths() {
        let ops = [
            HeaderOperation(type: .add, headerName: "X-Both", headerValue: "1", phase: .both),
        ]
        let reqFiltered = HeaderOperation.requestPhase(from: ops)
        let respFiltered = HeaderOperation.responsePhase(from: ops)
        #expect(reqFiltered.count == 1)
        #expect(respFiltered.count == 1)
        #expect(reqFiltered[0].headerName == "X-Both")
        #expect(respFiltered[0].headerName == "X-Both")
    }

    // MARK: - Post-Review: Missing Coverage

    @Test("Both-only operations produce Both summary label")
    func bothOnlyPhaseSummary() {
        let ops = [
            HeaderOperation(type: .add, headerName: "X-A", headerValue: "1", phase: .both),
            HeaderOperation(type: .remove, headerName: "X-B", headerValue: nil, phase: .both),
        ]
        #expect(ops.phaseSummaryLabel == "Both")
    }

    @Test("HeaderMutator applies response operations to NIO HTTPHeaders")
    func responseMutationViaHeaderMutator() {
        var headers = HTTPHeaders([
            ("Server", "Apache"),
            ("Content-Type", "text/html"),
        ])
        let ops = [
            HeaderOperation(type: .remove, headerName: "Server", headerValue: nil, phase: .response),
            HeaderOperation(type: .add, headerName: "X-Rockxy", headerValue: "1", phase: .response),
        ]
        HeaderMutator.apply(ops, to: &headers)
        #expect(headers["Server"].isEmpty)
        #expect(headers["X-Rockxy"] == ["1"])
        #expect(headers["Content-Type"] == ["text/html"])
    }

    @Test("HeaderMutator applies request operations to HTTPHeader array")
    func requestMutationViaHeaderMutator() {
        var headers = [
            HTTPHeader(name: "Authorization", value: "Bearer token"),
            HTTPHeader(name: "Accept", value: "application/json"),
        ]
        let ops = [
            HeaderOperation(type: .remove, headerName: "Authorization", headerValue: nil, phase: .request),
            HeaderOperation(type: .add, headerName: "X-Debug", headerValue: "true", phase: .request),
        ]
        HeaderMutator.apply(ops, to: &headers)
        #expect(headers.count == 2)
        #expect(!headers.contains { $0.name == "Authorization" })
        #expect(headers.contains { $0.name == "X-Debug" && $0.value == "true" })
    }

    @Test("Mixed phases produce correct summary labels")
    func mixedPhaseSummaryLabels() {
        let reqOnly = [HeaderOperation(type: .add, headerName: "A", headerValue: "1", phase: .request)]
        #expect(reqOnly.phaseSummaryLabel == "Req")

        let respOnly = [HeaderOperation(type: .add, headerName: "A", headerValue: "1", phase: .response)]
        #expect(respOnly.phaseSummaryLabel == "Resp")

        let mixed = [
            HeaderOperation(type: .add, headerName: "A", headerValue: "1", phase: .request),
            HeaderOperation(type: .add, headerName: "B", headerValue: "2", phase: .response),
        ]
        #expect(mixed.phaseSummaryLabel == "Mixed")

        let empty: [HeaderOperation] = []
        #expect(empty.phaseSummaryLabel == "")
    }

    // MARK: - Network Condition Codec

    @Test("networkCondition codec roundtrip")
    func networkConditionCodecRoundtrip() throws {
        let action = RuleAction.networkCondition(preset: .threeG, delayMs: 400)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)
        if case let .networkCondition(preset, delayMs) = decoded {
            #expect(preset == .threeG)
            #expect(delayMs == 400)
        } else {
            Issue.record("Expected .networkCondition, got \(decoded)")
        }
    }

    @Test("networkCondition custom preset codec roundtrip")
    func networkConditionCustomCodecRoundtrip() throws {
        let action = RuleAction.networkCondition(preset: .custom, delayMs: 1_234)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(RuleAction.self, from: data)
        if case let .networkCondition(preset, delayMs) = decoded {
            #expect(preset == .custom)
            #expect(delayMs == 1_234)
        } else {
            Issue.record("Expected .networkCondition, got \(decoded)")
        }
    }
}
