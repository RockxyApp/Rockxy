import Foundation
@testable import Rockxy
import Testing

@MainActor
struct FilterPresetStoreTests {
    @Test("Saved presets persist rules and connectors")
    func savedPresetsPersistRulesAndConnectors() throws {
        let suiteName = "FilterPresetStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "filter-presets"

        let store = FilterPresetStore(userDefaults: defaults, storageKey: key)
        let rules = [
            FilterRule(isEnabled: true, field: .requestHeader, filterOperator: .contains, value: "Host"),
            FilterRule(
                isEnabled: true,
                connector: .or,
                field: .responseHeader,
                filterOperator: .contains,
                value: "unsafe-inline"
            ),
        ]

        let preset = try #require(store.savePreset(name: "CSP Debug", rules: rules))
        let reloaded = FilterPresetStore(userDefaults: defaults, storageKey: key)

        #expect(reloaded.presets.count == 1)
        #expect(reloaded.presets.first?.id == preset.id)
        #expect(reloaded.presets.first?.rules.count == 2)
        #expect(reloaded.presets.first?.rules[1].connector == .or)
    }

    @Test("Preset save ignores disabled and empty rules")
    func presetSaveIgnoresInactiveRules() throws {
        let suiteName = "FilterPresetStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FilterPresetStore(userDefaults: defaults, storageKey: "filter-presets")
        let preset = try #require(store.savePreset(name: "Active Only", rules: [
            FilterRule(isEnabled: false, field: .url, filterOperator: .contains, value: "hidden"),
            FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: ""),
            FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: "api"),
        ]))

        #expect(preset.rules.count == 1)
        #expect(preset.rules.first?.value == "api")
    }

    @Test("Presets can be renamed and updated with the current filter, and both persist")
    func renameAndOverwrite() throws {
        let suiteName = "FilterPresetStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FilterPresetStore(userDefaults: defaults, storageKey: "p")
        let first = try #require(store.savePreset(
            name: "Errors",
            rules: [FilterRule(isEnabled: true, field: .statusCode, filterOperator: .contains, value: "5")]
        ))
        _ = try #require(store.savePreset(
            name: "Auth",
            rules: [FilterRule(isEnabled: true, field: .url, filterOperator: .contains, value: "login")]
        ))

        #expect(store.renamePreset(id: first.id, to: "  Server errors "))
        #expect(!store.renamePreset(id: first.id, to: "auth"))
        #expect(!store.renamePreset(id: first.id, to: "   "))
        #expect(store.overwritePreset(
            id: first.id,
            with: [FilterRule(isEnabled: true, field: .statusCode, filterOperator: .contains, value: "50")]
        ))
        #expect(!store.overwritePreset(id: first.id, with: [FilterRule()]))

        let reloaded = FilterPresetStore(userDefaults: defaults, storageKey: "p")
        let saved = try #require(reloaded.presets.first { $0.id == first.id })
        #expect(saved.name == "Server errors")
        #expect(saved.rules.map(\.value) == ["50"])
        #expect(reloaded.presets.count == 2)
    }
}
