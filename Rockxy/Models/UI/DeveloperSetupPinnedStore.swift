import Foundation

// MARK: - DeveloperSetupPinnedStore

@MainActor
final class DeveloperSetupPinnedStore {
    // MARK: Lifecycle

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = RockxyIdentity.current.defaultsKey("developerSetup.pinnedTargets")
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        pinnedTargetIDs = Self.load(defaults: defaults, defaultsKey: defaultsKey)
    }

    // MARK: Internal

    static let shared = DeveloperSetupPinnedStore()

    private(set) var pinnedTargetIDs: Set<SetupTarget.ID>

    func contains(_ targetID: SetupTarget.ID) -> Bool {
        pinnedTargetIDs.contains(targetID)
    }

    func toggle(_ targetID: SetupTarget.ID) {
        if pinnedTargetIDs.contains(targetID) {
            pinnedTargetIDs.remove(targetID)
        } else {
            pinnedTargetIDs.insert(targetID)
        }
        save()
    }

    func setPinned(_ pinned: Bool, for targetID: SetupTarget.ID) {
        if pinned {
            pinnedTargetIDs.insert(targetID)
        } else {
            pinnedTargetIDs.remove(targetID)
        }
        save()
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let defaultsKey: String

    private static func load(defaults: UserDefaults, defaultsKey: String) -> Set<SetupTarget.ID> {
        guard let stored = defaults.array(forKey: defaultsKey) as? [String] else {
            return Set(SetupTarget.defaultPinnedTargetIDs)
        }

        let decoded = stored.compactMap(SetupTarget.ID.init(rawValue:))
        return Set(decoded)
    }

    private func save() {
        defaults.set(pinnedTargetIDs.map(\.rawValue).sorted(), forKey: defaultsKey)
    }
}
