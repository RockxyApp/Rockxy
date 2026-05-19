import Foundation
@testable import Rockxy
import Testing

// Regression tests for autoSelectPort default migration in settings storage.

@Suite(.serialized)
struct AutoSelectPortMigrationTests {
    @Test("unset key loads as true (new default)")
    func unsetKeyDefaultsToTrue() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        UserDefaults.standard.removeObject(forKey: autoSelectPortKey)
        let settings = AppSettingsStorage.load()
        #expect(settings.autoSelectPort == true)
    }

    @Test("explicitly set to false loads as false")
    func explicitFalseRespected() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        UserDefaults.standard.set(false, forKey: autoSelectPortKey)
        let settings = AppSettingsStorage.load()
        #expect(settings.autoSelectPort == false)
    }

    @Test("explicitly set to true loads as true")
    func explicitTrueRespected() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        UserDefaults.standard.set(true, forKey: autoSelectPortKey)
        let settings = AppSettingsStorage.load()
        #expect(settings.autoSelectPort == true)
    }

    private var autoSelectPortKey: String {
        RockxyIdentity.current.defaultsKey("autoSelectPort")
    }
}
