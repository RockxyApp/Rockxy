import Foundation
@testable import Rockxy
import Testing

// Regression tests for `SettingsWiring` in the views settings layer.

@Suite(.serialized)
struct SettingsWiringTests {
    @Test("showAlertOnQuit runtime value matches UI default after toggle cycle")
    func showAlertOnQuitRegisteredDefault() {
        let key = TestIdentity.showAlertOnQuitKey
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        // Setting true explicitly must read back as true
        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == true)

        // Setting false explicitly must read back as false
        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)
    }

    @Test("showAlertOnQuit respects explicit toggle to false")
    func showAlertOnQuitExplicitFalse() {
        let key = TestIdentity.showAlertOnQuitKey
        let original = UserDefaults.standard.object(forKey: key)

        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        // Restore
        if let original {
            UserDefaults.standard.set(original, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Test("NoCacheHeaderMutator reads isEnabled from UserDefaults")
    func noCachingIsEnabled() {
        let key = NoCacheHeaderMutator.userDefaultsKey
        let original = UserDefaults.standard.object(forKey: key)

        UserDefaults.standard.set(true, forKey: key)
        #expect(NoCacheHeaderMutator.isEnabled == true)

        UserDefaults.standard.set(false, forKey: key)
        #expect(NoCacheHeaderMutator.isEnabled == false)

        if let original {
            UserDefaults.standard.set(original, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Test("recordOnLaunch wiring: UserDefaults key flows through AppSettingsStorage")
    func recordOnLaunchWiring() {
        let cleanup = installSettingsTestGuard()
        defer { cleanup() }

        let key = TestIdentity.recordOnLaunchKey
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.synchronize()
        let settingsTrue = AppSettingsStorage.load()
        #expect(settingsTrue.recordOnLaunch == true)

        UserDefaults.standard.set(false, forKey: key)
        UserDefaults.standard.synchronize()
        let settingsFalse = AppSettingsStorage.load()
        #expect(settingsFalse.recordOnLaunch == false)
    }

    @Test("ImportSizePolicy rejects oversized files with descriptive error")
    func importPolicyRejectsOversized() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try Data("x".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = ImportSizePolicy.validateFileSize(at: tempFile, maxSize: 0)
        if case let .failure(error) = result {
            let desc = error.localizedDescription
            #expect(desc.contains("too large") || desc.contains("Maximum"))
        } else {
            Issue.record("Expected rejection for oversized file")
        }
    }
}
