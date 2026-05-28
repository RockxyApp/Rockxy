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
}
