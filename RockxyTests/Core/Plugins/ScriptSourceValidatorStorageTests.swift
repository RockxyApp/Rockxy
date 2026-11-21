import Foundation
@testable import Rockxy
import Testing

// MARK: - ScriptSourceValidatorStorageTests

// Validation runs untrusted script source on an ordinary user path (editing and saving a
// script). Its `$rockxy.storage` bridge must never persist anything: no preference file
// left behind, and no write into the user's real defaults domain.

@Suite(.serialized)
struct ScriptSourceValidatorStorageTests {
    // MARK: Internal

    @Test("Validation leaves no preference file behind and never writes to the standard domain")
    func validationDoesNotPersist() async {
        let probeKey = "validationprobe\(UUID().uuidString.prefix(8).lowercased())"
        let standardKey = RockxyIdentity.current.pluginStoragePrefix(pluginID: "validation") + probeKey
        let before = Self.validationPlists()

        let result = await ScriptSourceValidator.validate(
            source: """
            $rockxy.storage.set("\(probeKey)", "value");
            if ($rockxy.storage.get("\(probeKey)") !== "value") { throw new Error("storage round trip failed"); }
            $rockxy.storage.delete("\(probeKey)");
            $rockxy.storage.set("\(probeKey)", "value");
            function onRequest(request) { return request; }
            """,
            runOnRequest: true,
            runOnResponse: false,
            runAsMock: false
        )

        #expect(result == .valid)
        #expect(UserDefaults.standard.object(forKey: standardKey) == nil)
        #expect(Self.validationPlists() == before)
    }

    @Test("The validation store is in memory and isolated per instance")
    func validationStoreIsInMemory() {
        let first = ScriptValidationDefaults()
        let second = ScriptValidationDefaults()
        let key = "rockxy-test.validation-store.\(UUID().uuidString)"

        first.set("value", forKey: key)
        #expect(first.object(forKey: key) as? String == "value")
        #expect(second.object(forKey: key) == nil)
        #expect(UserDefaults.standard.object(forKey: key) == nil)

        first.removeObject(forKey: key)
        #expect(first.object(forKey: key) == nil)
        #expect(first.storedKeys.isEmpty)
    }

    // MARK: Private

    private static func validationPlists() -> Set<String> {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("RockxyScriptValidation") })
    }
}
