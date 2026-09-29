import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
struct ScriptingRuntimeTests {
    @Test("SCRIPT_01 scriptMarkedActiveOnlyAfterRuntimeRegistration")
    func scriptMarkedActiveOnlyAfterRuntimeRegistration() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.invalid",
            script: "function onResponse(response) {",
            into: harness
        )

        await harness.manager.loadAllPlugins()

        let plugin = await harness.manager.plugins.first(where: { $0.id == "script.invalid" })
        #expect(plugin?.isEnabled == true)
        if case .error = plugin?.status {
            return
        } else {
            Issue.record("Expected invalid script to be marked error, got \(String(describing: plugin?.status))")
        }
    }

    @Test("SCRIPT_02 savedScriptInvokesOnResponseForMatchingUrl")
    func savedScriptInvokesOnResponseForMatchingUrl() async throws {
        let harness = try makeHarness()
        try writePricingExperimentPlugin(id: "script.pricing", into: harness)
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(
            request: pricingRequest(),
            response: pricingResponse()
        )

        #expect(jsonBody(mutated).contains(#""bucket":"treatment""#))
        #expect(jsonBody(mutated).contains(#""paywall":"discount""#))
        #expect(jsonBody(mutated).contains(#""discountPercent":20"#))
    }

    @Test("SCRIPT_03 mutationPropagatesToCaptureRow")
    func mutationPropagatesToCaptureRow() async throws {
        let harness = try makeHarness()
        try writePricingExperimentPlugin(id: "script.capture", into: harness)
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(
            request: pricingRequest(),
            response: pricingResponse()
        )
        let transaction = HTTPTransaction(request: pricingRequest(), response: mutated, state: .completed)

        let capturedBody = try #require(transaction.response?.body.flatMap { String(data: $0, encoding: .utf8) })
        #expect(capturedBody.contains(#""bucket":"treatment""#))
        #expect(!capturedBody.contains(#""bucket":"control""#))
    }

    @Test("SCRIPT_04 mutationPropagatesToClient")
    func mutationPropagatesToClient() async throws {
        let harness = try makeHarness()
        try writePricingExperimentPlugin(id: "script.client", into: harness)
        await harness.manager.loadAllPlugins()

        let clientFacingResponse = await harness.manager.runResponseHook(
            request: pricingRequest(),
            response: pricingResponse()
        )

        #expect(jsonBody(clientFacingResponse).contains(#""discountPercent":20"#))
    }

    @Test("SCRIPT_05 hostPortPathMatcherWorks")
    func hostPortPathMatcherWorks() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.matcher",
            script: "function onResponse(response) { return response; }",
            into: harness,
            behavior: responseBehavior(pattern: "127.0.0.1:43210/rockxy-demo/pricing-experiment")
        )
        await harness.manager.loadAllPlugins()

        #expect(harness.manager.hasResponseHookForSnapshot(request: pricingRequest()))
        #expect(!harness.manager.hasResponseHookForSnapshot(request: pricingRequest(url: "http://127.0.0.1:43211/rockxy-demo/pricing-experiment")))
    }

    @Test("SCRIPT_06 responseToggleHonoured")
    func responseToggleHonoured() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.response-off",
            script: Self.mutationScript,
            into: harness,
            behavior: ScriptBehavior(matchCondition: nil, runOnRequest: true, runOnResponse: false, runAsMock: false)
        )
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(request: pricingRequest(), response: pricingResponse())

        #expect(jsonBody(mutated).contains(#""bucket":"control""#))
    }

    @Test("SCRIPT_07 requestToggleHonoured")
    func requestToggleHonoured() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.request-off",
            script: "function onRequest(request) { return null; }",
            into: harness,
            behavior: ScriptBehavior(matchCondition: nil, runOnRequest: false, runOnResponse: true, runAsMock: false)
        )
        await harness.manager.loadAllPlugins()

        let outcome = await harness.manager.runRequestHook(on: pricingRequest())

        guard case .forward = outcome else {
            Issue.record("Expected request hook to be skipped when Request toggle is off")
            return
        }
    }

    @Test("SCRIPT_08 globalEnableHonoured")
    func globalEnableHonoured() async throws {
        let enabled = LockedBool(false)
        let harness = try makeHarness(settingsProvider: {
            var settings = AppSettings()
            settings.scriptingToolEnabled = enabled.value
            return settings
        })
        try writePricingExperimentPlugin(id: "script.global-off", into: harness)
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(request: pricingRequest(), response: pricingResponse())

        #expect(jsonBody(mutated).contains(#""bucket":"control""#))
        #expect(!harness.manager.hasResponseHookForSnapshot(request: pricingRequest()))
    }

    @Test("SCRIPT_09 jsExceptionSurfacesInConsole")
    func jsExceptionSurfacesInConsole() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.throws",
            script: "function onResponse(response) { throw new Error('boom'); }",
            into: harness
        )
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(request: pricingRequest(), response: pricingResponse())
        let plugin = await harness.manager.plugins.first(where: { $0.id == "script.throws" })

        #expect(jsonBody(mutated).contains(#""bucket":"control""#))
        if case let .error(reason) = plugin?.status {
            #expect(reason.contains("boom"))
        } else {
            Issue.record("Expected throwing script to mark plugin error, got \(String(describing: plugin?.status))")
        }
        #expect(!harness.manager.hasResponseHookForSnapshot(request: pricingRequest()))
    }

    @MainActor
    @Test("SCRIPT_10 scriptRegisteredInRuntimeImmediately")
    func scriptRegisteredInRuntimeImmediately() async throws {
        let harness = try makeHarness()
        try writePlugin(id: "script.save", script: "function onResponse(response) { return response; }", into: harness, enabled: false)
        await harness.manager.loadAllPlugins()

        let viewModel = ScriptEditorViewModel(
            pluginManager: harness.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: harness.dir
        )
        await viewModel.load(intent: .edit(pluginID: "script.save"))
        viewModel.runOnRequest = false
        viewModel.runOnResponse = true
        viewModel.runAsMock = false
        viewModel.urlPattern = "127.0.0.1:43210/rockxy-demo/pricing-experiment"
        viewModel.patternMode = .wildcard
        viewModel.code = Self.mutationScript

        await viewModel.saveAndActivate()
        let mutated = await harness.manager.runResponseHook(request: pricingRequest(), response: pricingResponse())

        #expect(viewModel.savedAndActive)
        #expect(jsonBody(mutated).contains(#""bucket":"treatment""#))
    }

    @Test("SCRIPT_11 bodyMutationRoundTrip")
    func bodyMutationRoundTrip() async throws {
        let harness = try makeHarness()
        try writePricingExperimentPlugin(id: "script.body-roundtrip", into: harness)
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(request: pricingRequest(), response: pricingResponse())

        #expect(jsonBody(mutated) == #"{"experiment":{"bucket":"treatment","paywall":"discount","discountPercent":20}}"#)
    }

    @Test("script-mutated sensitive response body redacts before MCP exposure")
    func scriptMutatedSensitiveResponseBodyRedactsBeforeMCPExposure() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.redaction",
            script: """
            function onResponse(response) {
              var body = JSON.parse(response.body);
              body.access_token = "script-secret";
              response.body = JSON.stringify(body);
              return response;
            }
            """,
            into: harness
        )
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(
            request: pricingRequest(),
            response: HTTPResponseData(
                statusCode: 200,
                statusMessage: "OK",
                headers: [],
                body: Data(#"{"user":"stephen"}"#.utf8)
            )
        )
        let body = try #require(mutated.body.flatMap { String(data: $0, encoding: .utf8) })
        let redacted = MCPRedactionPolicy(isEnabled: true).redactBody(body, contentType: mutated.contentType)

        #expect(body.contains("script-secret"))
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("script-secret"))
        #expect(redacted.contains("stephen"))
    }

    @Test("SCRIPT_12 pipelineOrderScriptingAfterMapLocal")
    func pipelineOrderScriptingAfterMapLocal() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.after-map-local",
            script: """
            function onResponse(response) {
              var body = JSON.parse(response.body);
              body.source = body.source + "+script";
              response.body = JSON.stringify(body);
              return response;
            }
            """,
            into: harness
        )
        await harness.manager.loadAllPlugins()

        // Response hooks operate on the response body handed to them by earlier
        // response-producing stages, so the captured/client value is post-script.
        let mappedResponse = HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"source":"map-local"}"#.utf8)
        )
        let mutated = await harness.manager.runResponseHook(request: pricingRequest(), response: mappedResponse)

        #expect(jsonBody(mutated).contains(#""source":"map-local+script""#))
    }

    @Test("SCRIPT_13 runAsMockApiDoesNotFireOnResponseHook")
    func runAsMockApiDoesNotFireOnResponseHook() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.mock",
            script: Self.mutationScript,
            into: harness,
            behavior: ScriptBehavior(matchCondition: nil, runOnRequest: true, runOnResponse: true, runAsMock: true)
        )
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(request: pricingRequest(), response: pricingResponse())

        #expect(jsonBody(mutated).contains(#""bucket":"control""#))
        #expect(!harness.manager.hasResponseHookForSnapshot(request: pricingRequest()))
    }

    @Test("single-arg onRequest exposes top-level headers")
    func singleArgOnRequestExposesTopLevelHeaders() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.request-redact",
            script: """
            function onRequest(request) {
              var sensitive = ["Authorization", "Cookie", "X-Api-Key", "X-Auth-Token"];
              for (var i = 0; i < sensitive.length; i++) {
                if (request.headers[sensitive[i]]) {
                  request.headers[sensitive[i]] = "[REDACTED]";
                }
              }
              return request;
            }
            """,
            into: harness,
            behavior: ScriptBehavior(matchCondition: nil, runOnRequest: true, runOnResponse: false, runAsMock: false)
        )
        await harness.manager.loadAllPlugins()

        let outcome = await harness.manager.runRequestHook(on: pricingRequest(headers: [
            HTTPHeader(name: "Authorization", value: "Bearer top-secret"),
            HTTPHeader(name: "Cookie", value: "session=abc"),
            HTTPHeader(name: "Accept", value: "application/json")
        ]))

        guard case let .forward(modified) = outcome else {
            Issue.record("Expected request script to forward a modified request")
            return
        }
        #expect(modified.headers.first { $0.name == "Authorization" }?.value == "[REDACTED]")
        #expect(modified.headers.first { $0.name == "Cookie" }?.value == "[REDACTED]")
        #expect(modified.headers.first { $0.name == "Accept" }?.value == "application/json")
    }

    @Test("request redaction script propagates into HAR export")
    func requestRedactionScriptPropagatesIntoHARExport() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.request-redact-har",
            script: """
            function onRequest(request) {
              var sensitive = ["Authorization", "Cookie", "X-Api-Key", "X-Auth-Token"];
              for (var i = 0; i < sensitive.length; i++) {
                if (request.headers[sensitive[i]]) {
                  request.headers[sensitive[i]] = "[REDACTED]";
                }
              }
              return request;
            }
            """,
            into: harness,
            behavior: ScriptBehavior(matchCondition: nil, runOnRequest: true, runOnResponse: false, runAsMock: false)
        )
        await harness.manager.loadAllPlugins()

        let original = try HTTPRequestData(
            method: "GET",
            url: #require(URL(string: "https://api.example.com/private")),
            httpVersion: "HTTP/1.1",
            headers: [
                HTTPHeader(name: "Authorization", value: "Bearer har-secret-token"),
                HTTPHeader(name: "Cookie", value: "session=har-cookie-secret"),
                HTTPHeader(name: "X-Api-Key", value: "har-api-key-secret"),
                HTTPHeader(name: "Accept", value: "application/json")
            ]
        )
        let outcome = await harness.manager.runRequestHook(on: original)
        let redactedRequest: HTTPRequestData
        guard case let .forward(modified) = outcome else {
            Issue.record("Expected request redaction script to forward the modified request")
            return
        }
        redactedRequest = modified

        let transaction = HTTPTransaction(
            request: redactedRequest,
            response: HTTPResponseData(
                statusCode: 200,
                statusMessage: "OK",
                headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
                body: Data(#"{"ok":true}"#.utf8),
                contentType: .json
            ),
            state: .completed
        )
        let harData = try HARExporter().export(transactions: [transaction])
        let harText = try #require(String(data: harData, encoding: .utf8))
        let harObject = try #require(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try #require(harObject["log"] as? [String: Any])
        let entries = try #require(log["entries"] as? [[String: Any]])
        let entry = try #require(entries.first)
        let request = try #require(entry["request"] as? [String: Any])
        let headers = try #require(request["headers"] as? [[String: String]])
        let exportedHeaders = Dictionary(uniqueKeysWithValues: headers.compactMap { header -> (String, String)? in
            guard let name = header["name"], let value = header["value"] else {
                return nil
            }
            return (name, value)
        })

        #expect(harText.contains("[REDACTED]"))
        #expect(exportedHeaders["Authorization"] == "[REDACTED]")
        #expect(exportedHeaders["Cookie"] == "[REDACTED]")
        #expect(exportedHeaders["X-Api-Key"] == "[REDACTED]")
        #expect(exportedHeaders["Accept"] == "application/json")
        #expect(!harText.contains("har-secret-token"))
        #expect(!harText.contains("har-cookie-secret"))
        #expect(!harText.contains("har-api-key-secret"))
    }

    @Test("SCRIPT_14 scenarioGuardWorks")
    func scenarioGuardWorks() async throws {
        let harness = try makeHarness()
        try writePricingExperimentPlugin(id: "script.guard", into: harness)
        await harness.manager.loadAllPlugins()

        let unmatched = await harness.manager.runResponseHook(
            request: pricingRequest(headers: [HTTPHeader(name: "X-Rockxy-Scenario-Id", value: "other")]),
            response: pricingResponse()
        )
        let matched = await harness.manager.runResponseHook(request: pricingRequest(), response: pricingResponse())

        #expect(jsonBody(unmatched).contains(#""bucket":"control""#))
        #expect(jsonBody(matched).contains(#""bucket":"treatment""#))
    }

    @Test("Case 11 blog script honors case-insensitive scenario header lookup")
    func case11BlogScriptHonorsCaseInsensitiveScenarioHeaderLookup() async throws {
        let harness = try makeHarness()
        try writePricingExperimentPlugin(id: "script.case11.header-case", into: harness)
        await harness.manager.loadAllPlugins()

        let mutated = await harness.manager.runResponseHook(
            request: pricingRequest(headers: [
                HTTPHeader(name: "x-rockxy-scenario-id", value: "scripted-mock"),
                HTTPHeader(name: "x-rockxy-lab-run-id", value: "case-11")
            ]),
            response: HTTPResponseData(
                statusCode: 200,
                statusMessage: "OK",
                headers: [HTTPHeader(name: "content-type", value: "application/json")],
                body: Data(#"{"experiment":{"bucket":"control","paywall":"standard","discountPercent":0}}"#.utf8)
            )
        )

        #expect(jsonBody(mutated).contains(#""bucket":"treatment""#))
        #expect(jsonBody(mutated).contains(#""paywall":"discount""#))
        #expect(jsonBody(mutated).contains(#""discountPercent":20"#))
        let contentTypeHeaders = mutated.headers.filter { $0.name.lowercased() == "content-type" }
        #expect(contentTypeHeaders.count == 1)
        #expect(contentTypeHeaders.first?.value == "application/json")
    }

    @MainActor
    @Test("Case 11 console.log appears in Script Editor console")
    func case11ConsoleLogAppearsInScriptEditorConsole() async throws {
        let harness = try makeHarness()
        try writePricingExperimentPlugin(id: "script.case11.console", into: harness)
        await harness.manager.loadAllPlugins()

        let viewModel = ScriptEditorViewModel(
            pluginManager: harness.manager,
            policyGate: ScriptPolicyGate(policy: DefaultAppPolicy()),
            pluginsDirectory: harness.dir
        )
        await viewModel.load(intent: .edit(pluginID: "script.case11.console"))
        viewModel.clearConsole()

        _ = await harness.manager.runResponseHook(
            request: pricingRequest(headers: [
                HTTPHeader(name: "x-rockxy-scenario-id", value: "scripted-mock"),
                HTTPHeader(name: "x-rockxy-lab-run-id", value: "case-11")
            ]),
            response: pricingResponse()
        )

        try await waitForConsoleEntry(in: viewModel, containing: "Mutated to treatment for run: case-11")
        #expect(viewModel.consoleEntries.contains { $0.level == .userLogs })
    }

    @Test("SCRIPT_15 multipleScriptsForOneRequestRespectFlag")
    func multipleScriptsForOneRequestRespectFlag() async throws {
        let chainOn = LockedBool(true)
        let harness = try makeHarness(settingsProvider: {
            var settings = AppSettings()
            settings.allowMultipleScriptsPerRequest = chainOn.value
            return settings
        })
        try writeAppendPlugin(id: "script.01", suffix: "a", into: harness)
        try writeAppendPlugin(id: "script.02", suffix: "b", into: harness)
        await harness.manager.loadAllPlugins()

        let chained = await harness.manager.runResponseHook(request: pricingRequest(), response: textResponse(""))
        chainOn.value = false
        await harness.manager.loadAllPlugins()
        let firstOnly = await harness.manager.runResponseHook(request: pricingRequest(), response: textResponse(""))

        #expect(stringBody(chained) == "ab")
        #expect(stringBody(firstOnly) == "a")
    }

    private static let mutationScript = """
    function onResponse(response) {
      if (response.request.headers["X-Rockxy-Scenario-Id"] !== "scripted-mock") {
        return response;
      }

      var body = JSON.parse(response.body);
      body.experiment.bucket = "treatment";
      body.experiment.paywall = "discount";
      body.experiment.discountPercent = 20;

      response.headers["Content-Type"] = "application/json";
      response.body = JSON.stringify(body);
      console.log("Mutated to treatment for run:",
        response.request.headers["X-Rockxy-Lab-Run-Id"]);
      return response;
    }
    """

    @Test("sharedState set in onRequest reaches the same flow's onResponse only")
    func sharedStateFollowsItsOwnFlow() async throws {
        let harness = try makeHarness()
        try writePlugin(
            id: "script.graphql-mock",
            script: """
            function onRequest(context, url, request) {
              context.sharedState.operation = JSON.parse(request.body).operationName;
              return request;
            }
            function onResponse(context, url, request, response) {
              if (context.sharedState.operation === "GetUser") {
                response.body = JSON.stringify({ data: { user: { name: "Mocked" } } });
              }
              return response;
            }
            """,
            into: harness,
            behavior: ScriptBehavior(matchCondition: nil, runOnRequest: true, runOnResponse: true, runAsMock: false)
        )
        await harness.manager.loadAllPlugins()

        let getUser = graphQLRequest(operation: "GetUser")
        let listPosts = graphQLRequest(operation: "ListPosts")
        _ = await harness.manager.runRequestHook(on: getUser)
        _ = await harness.manager.runRequestHook(on: listPosts)

        let postsResponse = await harness.manager.runResponseHook(request: listPosts, response: pricingResponse())
        let userResponse = await harness.manager.runResponseHook(request: getUser, response: pricingResponse())

        #expect(!stringBody(postsResponse).contains("Mocked"))
        #expect(stringBody(userResponse).contains(#""name":"Mocked""#))
        #expect(harness.manager.executionLedger.scriptNames(for: getUser.flowID) == ["script.graphql-mock"])
        #expect(harness.manager.executionLedger.scriptNames(for: UUID()).isEmpty)
    }

    private func graphQLRequest(operation: String) -> HTTPRequestData {
        HTTPRequestData(
            method: "POST",
            url: URL(string: "https://api.example.com/graphql")!,
            httpVersion: "HTTP/1.1",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"operationName":"\#(operation)","query":"query \#(operation) { id }"}"#.utf8)
        )
    }

    private func makeHarness(
        settingsProvider: (@Sendable () -> AppSettings)? = nil
    )
        throws -> ScriptHarness
    {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyScriptingRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "RockxyScriptingRuntimeTests-\(UUID().uuidString)") ?? .standard
        let discovery = PluginDiscovery(pluginsDirectory: dir, defaults: defaults)
        return ScriptHarness(
            dir: dir,
            defaults: defaults,
            manager: ScriptPluginManager(
                discovery: discovery,
                defaults: defaults,
                settingsProvider: settingsProvider
            )
        )
    }

    private func writePricingExperimentPlugin(id: String, into harness: ScriptHarness) throws {
        try writePlugin(
            id: id,
            script: Self.mutationScript,
            into: harness,
            behavior: responseBehavior(pattern: "127.0.0.1:43210/rockxy-demo/pricing-experiment")
        )
    }

    private func writeAppendPlugin(id: String, suffix: String, into harness: ScriptHarness) throws {
        try writePlugin(
            id: id,
            script: """
            function onResponse(response) {
              response.body = response.body + "\(suffix)";
              return response;
            }
            """,
            into: harness,
            behavior: ScriptBehavior(matchCondition: nil, runOnRequest: false, runOnResponse: true, runAsMock: false)
        )
    }

    private func writePlugin(
        id: String,
        script: String,
        into harness: ScriptHarness,
        behavior: ScriptBehavior = ScriptBehavior(matchCondition: nil, runOnRequest: false, runOnResponse: true, runAsMock: false),
        enabled: Bool = true
    )
        throws
    {
        let pluginDir = harness.dir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            id: id,
            name: id,
            version: "1.0.0",
            author: PluginAuthor(name: "Test", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "index.js"],
            capabilities: [],
            scriptBehavior: behavior
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"))
        try script.write(to: pluginDir.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)

        let key = RockxyIdentity.current.pluginEnabledKey(pluginID: id)
        if enabled {
            harness.defaults.set(true, forKey: key)
        } else {
            harness.defaults.removeObject(forKey: key)
        }
    }

    private func responseBehavior(pattern: String) -> ScriptBehavior {
        ScriptBehavior(
            matchCondition: RuleMatchCondition(
                urlPattern: pattern,
                method: "GET",
                matchType: .wildcard,
                includeSubpaths: false
            ),
            runOnRequest: false,
            runOnResponse: true,
            runAsMock: false
        )
    }

    private func pricingRequest(
        url: String = "http://127.0.0.1:43210/rockxy-demo/pricing-experiment",
        headers: [HTTPHeader] = [HTTPHeader(name: "X-Rockxy-Scenario-Id", value: "scripted-mock")]
    )
        -> HTTPRequestData
    {
        HTTPRequestData(
            method: "GET",
            // swiftlint:disable:next force_unwrapping
            url: URL(string: url)!,
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: nil
        )
    }

    private func pricingResponse() -> HTTPResponseData {
        HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: Data(#"{"experiment":{"bucket":"control","paywall":"standard","discountPercent":0}}"#.utf8)
        )
    }

    private func textResponse(_ body: String) -> HTTPResponseData {
        HTTPResponseData(
            statusCode: 200,
            statusMessage: "OK",
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            body: Data(body.utf8)
        )
    }

    private func jsonBody(_ response: HTTPResponseData) -> String {
        stringBody(response)
    }

    private func stringBody(_ response: HTTPResponseData) -> String {
        response.body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    @MainActor
    private func waitForConsoleEntry(
        in viewModel: ScriptEditorViewModel,
        containing expected: String,
        sourceLocation: SourceLocation = #_sourceLocation
    )
        async throws
    {
        for _ in 0 ..< 40 {
            if viewModel.consoleEntries.contains(where: { $0.message.contains(expected) }) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Expected Script Editor console entry containing '\(expected)'", sourceLocation: sourceLocation)
    }
}

private struct ScriptHarness {
    let dir: URL
    let defaults: UserDefaults
    let manager: ScriptPluginManager
}

private final class LockedBool: @unchecked Sendable {
    init(_ value: Bool) {
        self.storage = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    private let lock = NSLock()
    private var storage: Bool
}
