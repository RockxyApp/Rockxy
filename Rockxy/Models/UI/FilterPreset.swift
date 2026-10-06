import Foundation

// MARK: - FilterPreset

struct FilterPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var rules: [FilterRule]
    var createdAt = Date()
    var updatedAt = Date()
}

// MARK: - FilterPresetStore

@MainActor @Observable
final class FilterPresetStore {
    // MARK: Lifecycle

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = RockxyIdentity.current.defaultsKey("advancedFilterPresets")
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        presets = Self.loadPresets(from: userDefaults, key: storageKey)
    }

    // MARK: Internal

    var presets: [FilterPreset] = []

    @discardableResult
    func savePreset(name: String, rules: [FilterRule]) -> FilterPreset? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabledRules = FilterRuleEvaluator.activeRules(in: rules, isFilterBarVisible: true)
        guard !trimmedName.isEmpty, !enabledRules.isEmpty else {
            return nil
        }

        var preset = FilterPreset(name: trimmedName, rules: enabledRules)
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            preset.id = presets[index].id
            preset.createdAt = presets[index].createdAt
            preset.updatedAt = Date()
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persist()
        return preset
    }

    @discardableResult
    func saveGeneratedPreset(rules: [FilterRule]) -> FilterPreset? {
        savePreset(name: generatedPresetName(for: rules), rules: rules)
    }

    /// Suggested name for saving `rules`, e.g. "URL: api + 1".
    func suggestedName(for rules: [FilterRule]) -> String {
        generatedPresetName(for: rules)
    }

    /// Renames a preset; refuses an empty name or one another preset already uses.
    @discardableResult
    func renamePreset(id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = presets.firstIndex(where: { $0.id == id }),
              !presets.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else {
            return false
        }
        presets[index].name = trimmed
        presets[index].updatedAt = Date()
        persist()
        return true
    }

    /// Replaces a preset's rules with the currently enabled rules, keeping its name.
    @discardableResult
    func overwritePreset(id: UUID, with rules: [FilterRule]) -> Bool {
        let enabledRules = FilterRuleEvaluator.activeRules(in: rules, isFilterBarVisible: true)
        guard !enabledRules.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else {
            return false
        }
        presets[index].rules = enabledRules
        presets[index].updatedAt = Date()
        persist()
        return true
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    // MARK: Private

    private let userDefaults: UserDefaults
    private let storageKey: String

    private static func loadPresets(from userDefaults: UserDefaults, key: String) -> [FilterPreset] {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FilterPreset].self, from: data) else
        {
            return []
        }
        return decoded
    }

    private func generatedPresetName(for rules: [FilterRule]) -> String {
        let activeRules = FilterRuleEvaluator.activeRules(in: rules, isFilterBarVisible: true)
        guard let first = activeRules.first else {
            return String(localized: "Advanced Filter", bundle: RockxyLocalization.bundle)
        }
        let base = "\(first.field.displayName): \(first.value)"
        if activeRules.count == 1 {
            return base
        }
        return "\(base) + \(activeRules.count - 1)"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}
