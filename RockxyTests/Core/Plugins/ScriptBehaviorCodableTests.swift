import Foundation
@testable import Rockxy
import Testing

// Tests the optional `scriptBehavior` block on `PluginManifest`.

struct ScriptBehaviorCodableTests {
    @Test("Round trip with all four fields preserves values")
    func roundTripAllFields() throws {
        let behavior = ScriptBehavior(
            matchCondition: RuleMatchCondition(
                urlPattern: "https://example.com/.*",
                method: "GET",
                headerName: nil,
                headerValue: nil
            ),
            runOnRequest: false,
            runOnResponse: true,
            runAsMock: true
        )
        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(ScriptBehavior.self, from: data)
        #expect(decoded == behavior)
    }

    @Test("Defaults helper returns match-all, request=true, response=true, mock=false")
    func defaultsAreCorrect() {
        let defaults = ScriptBehavior.defaults()
        #expect(defaults.matchCondition == nil)
        #expect(defaults.runOnRequest == true)
        #expect(defaults.runOnResponse == true)
        #expect(defaults.runAsMock == false)
    }

    @Test("Manifest decoded WITHOUT scriptBehavior leaves the field nil")
    func manifestWithoutScriptBehavior() throws {
        let json = """
        {
          "id": "test.legacy",
          "name": "Legacy",
          "version": "1.0.0",
          "author": { "name": "Tester" },
          "description": "",
          "types": ["script"],
          "entryPoints": { "script": "index.js" },
          "capabilities": []
        }
        """
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        #expect(manifest.scriptBehavior == nil)
    }

    @Test("Manifest with partial scriptBehavior fills in defaults for missing fields")
    func manifestWithPartialScriptBehavior() throws {
        let json = """
        {
          "id": "test.partial",
          "name": "Partial",
          "version": "1.0.0",
          "author": { "name": "Tester" },
          "description": "",
          "types": ["script"],
          "entryPoints": { "script": "index.js" },
          "capabilities": [],
          "scriptBehavior": { "runAsMock": true }
        }
        """
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        let behavior = try #require(manifest.scriptBehavior)
        #expect(behavior.runAsMock == true)
        #expect(behavior.runOnRequest == true)
        #expect(behavior.runOnResponse == true)
        #expect(behavior.matchCondition == nil)
    }

    @Test("Manifest with full scriptBehavior round-trips")
    func manifestWithFullScriptBehavior() throws {
        let original = PluginManifest(
            id: "test.full",
            name: "Full",
            version: "1.0.0",
            author: PluginAuthor(name: "Tester", url: nil),
            description: "",
            types: [.script],
            entryPoints: ["script": "index.js"],
            capabilities: [],
            configuration: nil,
            minRockxyVersion: nil,
            homepage: nil,
            license: nil,
            scriptBehavior: ScriptBehavior(
                matchCondition: RuleMatchCondition(urlPattern: ".*api.*", method: "POST"),
                runOnRequest: true,
                runOnResponse: false,
                runAsMock: false
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PluginManifest.self, from: data)
        #expect(decoded.scriptBehavior == original.scriptBehavior)
    }
}
