import Foundation
@testable import Rockxy
import Testing

// Regression tests for autoSelectPort default migration in settings storage.

@Suite(.serialized)
struct AutoSelectPortMigrationTests {
    // MARK: Internal

    @Test("unset key loads as true (new default)")
    func unsetKeyDefaultsToTrue() {
        let original = UserDefaults.standard.object(forKey: Self.key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }

        UserDefaults.standard.removeObject(forKey: Self.key)
        let settings = AppSettingsStorage.load()
        #expect(settings.autoSelectPort == true)
    }

    @Test("explicitly set to false loads as false")
    func explicitFalseRespected() {
        let original = UserDefaults.standard.object(forKey: Self.key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }

        UserDefaults.standard.set(false, forKey: Self.key)
        let settings = AppSettingsStorage.load()
        #expect(settings.autoSelectPort == false)
    }

    @Test("explicitly set to true loads as true")
    func explicitTrueRespected() {
        let original = UserDefaults.standard.object(forKey: Self.key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }

        UserDefaults.standard.set(true, forKey: Self.key)
        let settings = AppSettingsStorage.load()
        #expect(settings.autoSelectPort == true)
    }

    @Test("key set then cleared reverts to default true")
    func setThenClearedRevertsToDefault() {
        let original = UserDefaults.standard.object(forKey: Self.key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }

        // Simulate a user who had autoSelectPort = false (old default)
        // and then their settings entry is cleared (e.g., fresh install migration)
        UserDefaults.standard.set(false, forKey: Self.key)
        let beforeClear = AppSettingsStorage.load()
        #expect(beforeClear.autoSelectPort == false)

        UserDefaults.standard.removeObject(forKey: Self.key)
        let afterClear = AppSettingsStorage.load()
        #expect(afterClear.autoSelectPort == true)
    }

    @Test("save with autoSelectPort false then load preserves false")
    func saveLoadRoundtripFalse() {
        let original = AppSettingsStorage.load()
        defer { AppSettingsStorage.save(original) }

        var settings = AppSettings()
        settings.autoSelectPort = false
        AppSettingsStorage.save(settings)

        let loaded = AppSettingsStorage.load()
        #expect(loaded.autoSelectPort == false)
    }

    // MARK: Private

    private static let key = "com.amunx.Rockxy.autoSelectPort"
}