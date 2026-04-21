import Foundation
@testable import Rockxy
import Testing

@MainActor
struct DeveloperSetupPinnedStoreTests {
    @Test("Pinned store defaults to the curated pinned targets")
    func defaultPinnedTargets() {
        let suiteName = "DeveloperSetupPinnedStoreDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeveloperSetupPinnedStore(
            defaults: defaults,
            defaultsKey: "developerSetup.pinnedTargets"
        )

        #expect(store.pinnedTargetIDs == Set(SetupTarget.defaultPinnedTargetIDs))
    }

    @Test("Pinned store persists pin changes")
    func persistsPinChanges() {
        let suiteName = "DeveloperSetupPinnedStorePersistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeveloperSetupPinnedStore(
            defaults: defaults,
            defaultsKey: "developerSetup.pinnedTargets"
        )
        store.setPinned(true, for: .ruby)
        store.setPinned(false, for: .python)

        let reloaded = DeveloperSetupPinnedStore(
            defaults: defaults,
            defaultsKey: "developerSetup.pinnedTargets"
        )

        #expect(reloaded.contains(.ruby))
        #expect(reloaded.contains(.python) == false)
    }
}
