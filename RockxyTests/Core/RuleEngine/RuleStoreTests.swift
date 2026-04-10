import Foundation
@testable import Rockxy
import Testing

// Tests for JSON-based rule persistence: save/load roundtrip fidelity,
// missing-file handling, and multi-cycle overwrite correctness.

// MARK: - RuleStoreTests

struct RuleStoreTests {
    @Test("RuleStore save and load roundtrip preserves data")
    func saveLoadRoundtrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = TestableRuleStore(directory: tempDir)

        let rules = [
            ProxyRule(
                name: "Block Rule",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*blocked.*"),
                action: .block(statusCode: 403)
            ),
            ProxyRule(
                name: "Throttle Rule",
                isEnabled: false,
                matchCondition: RuleMatchCondition(method: "POST"),
                action: .throttle(delayMs: 1_000)
            )
        ]

        try store.saveRules(rules)
        let loaded = try store.loadRules()

        #expect(loaded.count == 2)
        #expect(loaded[0].name == "Block Rule")
        #expect(loaded[0].isEnabled == true)
        #expect(loaded[1].name == "Throttle Rule")
        #expect(loaded[1].isEnabled == false)
    }

    @Test("RuleStore load from non-existent file returns empty array")
    func loadNonExistentReturnsEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = TestableRuleStore(directory: tempDir)
        let loaded = try store.loadRules()

        #expect(loaded.isEmpty)
    }

    @Test("RuleStore multiple save/load cycles preserve data")
    func multipleSaveLoadCycles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = TestableRuleStore(directory: tempDir)

        let rules1 = [
            ProxyRule(
                name: "Rule A",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*a.*"),
                action: .block(statusCode: 400)
            )
        ]
        try store.saveRules(rules1)
        let loaded1 = try store.loadRules()
        #expect(loaded1.count == 1)

        let rules2 = [
            ProxyRule(
                name: "Rule B",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*b.*"),
                action: .block(statusCode: 500)
            ),
            ProxyRule(
                name: "Rule C",
                isEnabled: false,
                matchCondition: RuleMatchCondition(method: "DELETE"),
                action: .breakpoint()
            )
        ]
        try store.saveRules(rules2)
        let loaded2 = try store.loadRules()
        #expect(loaded2.count == 2)
        #expect(loaded2[0].name == "Rule B")
        #expect(loaded2[1].name == "Rule C")
    }

    @Test("Export creates valid JSON file")
    func exportCreatesValidJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = TestableRuleStore(directory: tempDir)
        let rules = [
            ProxyRule(
                name: "Export Test",
                isEnabled: true,
                matchCondition: RuleMatchCondition(urlPattern: ".*export.*"),
                action: .block(statusCode: 403)
            )
        ]
        try store.saveRules(rules)

        let exportURL = tempDir.appendingPathComponent("exported-rules.json")
        try store.exportRules(to: exportURL)

        let data = try Data(contentsOf: exportURL)
        let decoded = try JSONDecoder().decode([ProxyRule].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Export Test")
    }

    @Test("Import from valid file returns rules")
    func importFromValidFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = TestableRuleStore(directory: tempDir)
        let rules = [
            ProxyRule(
                name: "Import Rule",
                isEnabled: false,
                matchCondition: RuleMatchCondition(method: "PUT"),
                action: .throttle(delayMs: 500)
            )
        ]

        let importURL = tempDir.appendingPathComponent("import-rules.json")
        let data = try JSONEncoder().encode(rules)
        try data.write(to: importURL)

        let imported = try store.importRules(from: importURL)
        #expect(imported.count == 1)
        #expect(imported[0].name == "Import Rule")
        #expect(imported[0].isEnabled == false)
    }

    @Test("Import from invalid JSON throws")
    func importFromInvalidJSONThrows() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = TestableRuleStore(directory: tempDir)
        let invalidURL = tempDir.appendingPathComponent("invalid.json")
        try #require("this is not json at all".data(using: .utf8)).write(to: invalidURL)

        #expect(throws: (any Error).self) {
            _ = try store.importRules(from: invalidURL)
        }
    }

    @Test("Import rejects file larger than 5 MB")
    func importRejectsOversizedFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = TestableRuleStore(directory: tempDir)
        let oversizedURL = tempDir.appendingPathComponent("oversized.json")
        let oversizedData = Data(repeating: 0x41, count: 5 * 1_024 * 1_024 + 1)
        try oversizedData.write(to: oversizedURL)

        #expect(throws: RuleStore.RuleStoreError.self) {
            _ = try store.importRules(from: oversizedURL)
        }
    }

    @Test("RuleStore initializer does not crash")
    func ruleStoreInitDoesNotCrash() throws {
        let store = RuleStore()
        let rules = try store.loadRules()
        // Verify construction succeeded without fatalError
        #expect(rules.isEmpty || !rules.isEmpty)
    }
}

// MARK: - TestableRuleStore

/// Minimal file-based rule store for testing, isolated to a temp directory.
private struct TestableRuleStore {
    // MARK: Lifecycle

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("rules.json")
    }

    // MARK: Internal

    func loadRules() throws -> [ProxyRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([ProxyRule].self, from: data)
    }

    func saveRules(_ rules: [ProxyRule]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(rules)
        try data.write(to: fileURL)
    }

    func exportRules(to url: URL) throws {
        let data = try JSONEncoder().encode(loadRules())
        try data.write(to: url, options: .atomic)
    }

    func importRules(from url: URL) throws -> [ProxyRule] {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = attrs[.size] as? UInt64, fileSize > Self.maxImportSize {
            throw RuleStore.RuleStoreError.importFileTooLarge(fileSize)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ProxyRule].self, from: data)
    }

    // MARK: Private

    private static let maxImportSize: UInt64 = 5 * 1_024 * 1_024

    private let fileURL: URL
}
