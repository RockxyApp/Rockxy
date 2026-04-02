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

    // MARK: Private

    private static let key = "com.amunx.Rockxy.autoSelectPort"
}
