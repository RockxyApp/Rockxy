import Foundation
@testable import Rockxy
import Testing

@MainActor
struct ScriptFolderStoreTests {
    @Test("Reconcile restores folders missing from rootOrder")
    func reconcileRestoresOrphanedFolders() throws {
        let (defaults, suiteName) = TestFixtures.makeNamedIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folder = ScriptFolder(name: "Recovered Folder", expanded: true, scriptIDs: [])
        let malformedIndex = ScriptFolderIndex(folders: [folder], rootOrder: [])
        let data = try JSONEncoder().encode(malformedIndex)
        defaults.set(data, forKey: RockxyIdentity.current.defaultsKey("scripting.folderIndex"))

        let store = ScriptFolderStore(defaults: defaults)
        store.reconcile(with: [])

        #expect(store.index.rootOrder.contains(.folder(folder.id)))
    }
}
