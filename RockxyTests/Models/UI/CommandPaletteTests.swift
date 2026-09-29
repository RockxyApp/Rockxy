import Foundation
@testable import Rockxy
import Testing

// MARK: - CommandPaletteTests

struct CommandPaletteTests {
    // MARK: Internal

    @Test("Fuzzy search finds commands by initials, words, and keywords")
    func fuzzyRanking() {
        let commands = CommandPaletteCatalog.commands

        #expect(CommandPaletteMatcher.rank(commands, query: "map local").first?.id == "tools.mapLocal")
        #expect(CommandPaletteMatcher.rank(commands, query: "exp csv").first?.id == "file.exportCSV")
        #expect(CommandPaletteMatcher.rank(commands, query: "throttle").first?.id == "tools.network")
        #expect(CommandPaletteMatcher.rank(commands, query: "zzqx").isEmpty)
        #expect(CommandPaletteMatcher.rank(commands, query: "   ").count == commands.count)
    }

    @Test("Characters must appear in order")
    func orderMatters() {
        #expect(CommandPaletteMatcher.score(query: "mlc", candidate: "Map Local") != nil)
        #expect(CommandPaletteMatcher.score(query: "clm", candidate: "Map Local") == nil)
    }

    @Test("Every palette window command opens a declared window scene")
    func windowIDsExist() throws {
        let source = try projectFile("Rockxy/RockxyApp.swift")
            + projectFile("Rockxy/Views/Settings/SettingsWindowScene.swift")
            + projectFile("Rockxy/Views/Rules/ReverseProxyWindowView.swift")
        for command in CommandPaletteCatalog.commands {
            guard case let .openWindow(id) = command.action else {
                continue
            }
            #expect(source.contains("id: \"\(id)\""), "Missing window scene for \(id)")
        }
    }

    @Test("Command identifiers are unique")
    func uniqueIDs() {
        let ids = CommandPaletteCatalog.commands.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: Private

    private func projectFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
