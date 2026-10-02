import Foundation
@testable import Rockxy
import Testing

// MARK: - SettingsBackupTests

@MainActor
struct SettingsBackupTests {
    // MARK: Internal

    @Test("A backup round-trips every section and rejects other files")
    func roundTrip() throws {
        let document = SettingsBackupDocument(
            appVersion: "1.0",
            settings: sampleSettings(),
            mapLocalFiles: [SettingsBackupFile(name: "user.json", data: Data("{\"ok\":true}".utf8))],
            scripts: [SettingsBackupScript(
                name: "Add header",
                source: "function onRequest(c, r) { return r }",
                behavior: nil
            )]
        )
        let decoded = try SettingsBackupDocument.decode(document.encoded())

        #expect(decoded.settings.rules.map(\.name) == ["Mock user", "Slow", "Offline"])
        #expect(decoded.settings.sslProxying?.rules.map(\.domain) == ["api.example.com"])
        #expect(decoded.settings.allowList?.rules.map(\.rawPattern) == ["https://api.example.com/*"])
        #expect(decoded.settings.bypassDomains.map(\.domain) == ["*.apple.com"])
        #expect(decoded.settings.reverseProxies.map(\.localPort) == [10_001])
        #expect(decoded.settings.dnsSpoofing.map(\.host) == ["api.example.com"])
        #expect(decoded.settings.toolsEnabled["mapLocalToolEnabled"] == false)
        #expect(decoded.mapLocalFiles.first?.name == "user.json")
        #expect(decoded.scripts.first?.name == "Add header")

        #expect(throws: SettingsBackupError.notABackup) {
            try SettingsBackupDocument.decode(Data(#"{"format":"something-else","version":1}"#.utf8))
        }
        #expect(throws: SettingsBackupError.newerVersion(99)) {
            try SettingsBackupDocument.decode(Data(#"{"format":"rockxy-settings-backup","version":99}"#.utf8))
        }
        #expect(throws: SettingsBackupError.unreadable) {
            try SettingsBackupDocument.decode(Data("not json".utf8))
        }
        // An older file with only some sections still decodes.
        let partial = try SettingsBackupDocument.decode(Data(#"{"format":"rockxy-settings-backup","version":1}"#.utf8))
        #expect(partial.settings.rules.isEmpty)
    }

    @Test("Rule folders round-trip, and importing them replaces or adds without touching other tools")
    func ruleFoldersRoundTripAndImport() throws {
        let ruleID = UUID()
        var snapshot = SettingsBackupSnapshot()
        snapshot.ruleFolders = ["mapLocal": [RuleFolder(id: UUID(), name: "API mocks", ruleIDs: [ruleID])]]
        let decoded = try SettingsBackupDocument.decode(SettingsBackupDocument(settings: snapshot).encoded())
        #expect(decoded.settings.ruleFolders["mapLocal"]?.first?.name == "API mocks")
        #expect(decoded.settings.ruleFolders["mapLocal"]?.first?.ruleIDs == [ruleID])

        let defaults = UserDefaults(suiteName: "RockxyRuleFolderBackupTests-\(UUID().uuidString)") ?? .standard
        let store = RuleFolderStore(tool: "test", defaults: defaults)
        store.importFolders(decoded.settings.ruleFolders["mapLocal"] ?? [], replacing: false)
        #expect(store.folders.count == 1)
        // Adding the same folders again does not duplicate them.
        store.importFolders(decoded.settings.ruleFolders["mapLocal"] ?? [], replacing: false)
        #expect(store.folders.count == 1)
        store.importFolders([], replacing: true)
        #expect(store.folders.isEmpty)
    }

    @Test("Exporting enabled rules only leaves disabled entries out")
    func enabledOnly() {
        let filtered = sampleSettings().enabledOnly()
        #expect(filtered.rules.map(\.name) == ["Mock user", "Slow"])
        #expect(filtered.dnsSpoofing.isEmpty)
    }

    @Test("Append keeps current settings, adds new entries, and resolves collisions")
    func appendMerge() {
        let current = sampleSettings()
        var backup = sampleSettings()
        backup.rules.append(ProxyRule(
            name: "Broken",
            matchCondition: RuleMatchCondition(urlPattern: "(unclosed", matchType: .regex),
            action: .block(statusCode: 403)
        ))
        backup.reverseProxies.append(ReverseProxyRule(
            name: "New",
            localPort: 10_002,
            remoteHost: "staging.example.com",
            remotePort: 443
        ))
        backup.toolsEnabled = ["mapLocalToolEnabled": true]
        var renamed = backup.rules[0]
        renamed.name = "Mock user v2"
        backup.rules.append(renamed)

        let result = SettingsBackupMerger.merge(backup, into: current, mode: .append, proxyPort: 9_090)
        let settings = result.settings

        // Identical rules are not added twice, a changed rule that reuses an identifier gets a
        // fresh one, and the broken regex is skipped.
        #expect(settings.rules.count == 4)
        #expect(Set(settings.rules.map(\.id)).count == 4)
        #expect(settings.rules.last?.name == "Mock user v2")
        #expect(result.addedRuleCount == 1)
        #expect(!settings.rules.contains { $0.name == "Broken" })
        // Only one network condition stays on.
        let enabledConditions = settings.rules.filter { rule in
            if case .networkCondition = rule.action {
                return rule.isEnabled
            }
            return false
        }
        #expect(enabledConditions.count == 1)
        // Duplicates of what is already there are not added again.
        #expect(settings.sslProxying?.rules.count == 1)
        #expect(settings.allowList?.rules.count == 1)
        #expect(settings.bypassDomains.count == 1)
        // The reverse proxy on an occupied port is skipped; the new port is added.
        #expect(settings.reverseProxies.map(\.localPort) == [10_001, 10_002])
        #expect(result.addedReverseProxyCount == 1)
        #expect(result.addedDNSSpoofingCount == 0)
        // The duplicate DNS host is skipped.
        #expect(settings.dnsSpoofing.count == 1)
        // Append never changes tool switches.
        #expect(settings.toolsEnabled["mapLocalToolEnabled"] == false)
        #expect(result.skippedCount == 3)
    }

    @Test("Replace makes every section match the backup")
    func replaceMerge() {
        let current = sampleSettings()
        let backup = SettingsBackupSnapshot(
            rules: [],
            toolsEnabled: ["breakpointToolEnabled": false, "unknownKey": true],
            sslProxying: SSLProxyingBackup(isEnabled: false, bypassDomains: "", rules: [], applicationRules: []),
            noCaching: true
        )
        let settings = SettingsBackupMerger.merge(backup, into: current, mode: .replace, proxyPort: 9_090).settings
        #expect(settings.rules.isEmpty)
        #expect(settings.toolsEnabled == ["breakpointToolEnabled": false])
        #expect(settings.sslProxying?.isEnabled == false)
        #expect(settings.bypassDomains.isEmpty)
        #expect(settings.reverseProxies.isEmpty)
        #expect(settings.noCaching == true)
        // Sections absent from the backup keep their current value.
        #expect(settings.allowList?.rules.count == 1)
    }

    @Test("Map Local bodies from Rockxy's folder travel with the backup and land in the new folder")
    func mapLocalBodies() throws {
        let source = try temporaryDirectory().appendingPathComponent("map-local", isDirectory: true)
        let destination = try temporaryDirectory().appendingPathComponent("map-local", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("{\"id\":1}".utf8).write(to: source.appendingPathComponent("user.json"))
        try Data("different".utf8).write(to: destination.appendingPathComponent("user.json"))

        let inside = mapLocalRule(path: source.appendingPathComponent("user.json").path)
        let outside = mapLocalRule(path: "/Users/someone/Desktop/elsewhere.json")
        let files = SettingsBackupService.mapLocalFiles(for: [inside, outside], root: source)
        #expect(files == [SettingsBackupFile(name: "user.json", data: Data("{\"id\":1}".utf8))])

        let relocated = SettingsBackupService.relocateMapLocalFiles(files, rules: [inside, outside], root: destination)
        guard case let .mapLocal(newPath, _, _, _, _) = relocated[0].action,
              case let .mapLocal(untouched, _, _, _, _) = relocated[1].action else
        {
            Issue.record("Map Local actions changed kind")
            return
        }
        #expect(newPath.hasPrefix(destination.path))
        #expect(newPath != destination.appendingPathComponent("user.json").path, "an existing different file is kept")
        #expect(try Data(contentsOf: URL(fileURLWithPath: newPath)) == Data("{\"id\":1}".utf8))
        #expect(untouched == "/Users/someone/Desktop/elsewhere.json")

        // Names that could escape the folder are never written.
        let hostile = [SettingsBackupFile(name: "../escape.json", data: Data("x".utf8))]
        _ = SettingsBackupService.relocateMapLocalFiles(hostile, rules: [], root: destination)
        #expect(!FileManager.default.fileExists(atPath: destination.deletingLastPathComponent()
                .appendingPathComponent("escape.json").path))
    }

    @Test("Scripts are read with their source and re-added as new plugins")
    func scripts() throws {
        let plugins = try temporaryDirectory()
        try ScriptPluginFactory.create(id: "abc", name: "Tag requests", source: "// tag", in: plugins)
        let exported = SettingsBackupService.scripts(onlyEnabled: false, root: plugins)
        #expect(exported.map(\.name) == ["Tag requests"])
        #expect(exported.first?.source == "// tag")

        let target = try temporaryDirectory()
        #expect(SettingsBackupService.installScripts(exported, root: target) == 1)
        let installed = SettingsBackupService.scripts(onlyEnabled: false, root: target)
        #expect(installed.map(\.source) == ["// tag"])
    }

    @Test("The import summary lists what the backup holds")
    func summary() {
        let document = SettingsBackupDocument(settings: sampleSettings())
        let text = SettingsBackupFlow.summary(of: document)
        #expect(text.contains("3 rules"))
        #expect(text.contains("1 DNS Spoofing rule"))
        #expect(SettingsBackupFlow.summary(of: SettingsBackupDocument(settings: SettingsBackupSnapshot()))
            == "The backup contains no rules.")
    }

    @Test("An import that only adds reverse proxies or DNS rules says so instead of 'already here'")
    @MainActor
    func reportCountsReverseProxiesAndDNSRules() {
        let lines = SettingsBackupFlow.reportLines(SettingsBackupImportReport(reverseProxyCount: 1, dnsSpoofingCount: 2))
        #expect(lines == ["1 reverse proxy added.", "2 DNS Spoofing rules added."])
        #expect(SettingsBackupFlow.reportLines(SettingsBackupImportReport()) == [
            "No new rules were added; the backup's rules are already here.",
        ])
    }

    // MARK: Private

    private func sampleSettings() -> SettingsBackupSnapshot {
        SettingsBackupSnapshot(
            rules: [
                mapLocalRule(path: "/tmp/user.json"),
                ProxyRule(
                    name: "Slow",
                    matchCondition: RuleMatchCondition(urlPattern: ".*"),
                    action: .networkCondition(preset: .threeG, delayMs: 400)
                ),
                ProxyRule(
                    name: "Offline",
                    isEnabled: false,
                    matchCondition: RuleMatchCondition(urlPattern: ".*"),
                    action: .networkCondition(preset: .offline, delayMs: 0)
                ),
            ],
            toolsEnabled: ["mapLocalToolEnabled": false],
            sslProxying: SSLProxyingBackup(
                isEnabled: true,
                bypassDomains: "",
                rules: [SSLProxyingRule(domain: "api.example.com")],
                applicationRules: []
            ),
            allowList: AllowListBackup(
                isActive: false,
                rules: [AllowListRule(name: "API", rawPattern: "https://api.example.com/*")]
            ),
            bypassDomains: [BypassDomain(domain: "*.apple.com")],
            reverseProxies: [ReverseProxyRule(
                name: "API",
                localPort: 10_001,
                remoteHost: "api.example.com",
                remotePort: 443
            )],
            dnsSpoofing: [DNSSpoofingRule(isEnabled: false, host: "api.example.com", address: "10.0.0.5")],
            noCaching: false
        )
    }

    private func mapLocalRule(path: String) -> ProxyRule {
        ProxyRule(
            name: "Mock user",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/user"),
            action: .mapLocal(filePath: path)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SettingsBackupTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
