import Foundation
@testable import Rockxy
import Testing

// MARK: - GitHubSettingsStoreTests

struct GitHubSettingsStoreTests {
    @Test("Stores only GitHub auth metadata in defaults, never token")
    func tokenNeverEntersUserDefaults() throws {
        let suiteName = IsolatedDefaultsSuite.uniqueName(prefix: "GitHubSettingsStoreTests-")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let metadata = GitHubAuthMetadata(
            method: .personalAccessToken,
            login: "ada",
            scopes: ["gist"],
            tokenSuffix: "1234",
            connectedAt: Date()
        )
        GitHubSettingsStore.saveMetadata(metadata, userDefaults: defaults)

        #expect(GitHubSettingsStore.loadMetadata(userDefaults: defaults) == metadata)
        #expect(!GitHubSettingsStore.userDefaultsContainsToken("ghp_super_secret_token", userDefaults: defaults))
        #expect(!GitHubSettingsStore.userDefaultsContainsToken("super_secret", userDefaults: defaults))
    }
}
