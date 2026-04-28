import Foundation
@testable import Rockxy
import Testing

struct RockxyUpdateConfigurationTests {
    @Test("Sparkle config is disabled when updates are off")
    func disabledByDefault() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "NO",
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "public-key",
        ])

        #expect(!configuration.updatesEnabled)
        #expect(!configuration.isConfigured)
    }

    @Test("Sparkle config ignores placeholder values")
    func ignoresPlaceholderValues() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "YES",
            "SUFeedURL": "__PENDING__",
            "SUPublicEDKey": "PLACEHOLDER",
        ])

        #expect(configuration.feedURL == nil)
        #expect(configuration.publicEDKey.isEmpty)
        #expect(!configuration.isConfigured)
    }

    @Test("Sparkle config is enabled only with feed and key")
    func requiresFeedAndKey() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "YES",
            "SUFeedURL": "https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml",
            "SUPublicEDKey": "OhLtaWdjixrruIOymzcROteZVpMNtv7fLQVSxbn+1ok=",
        ])

        #expect(configuration.updatesEnabled)
        #expect(configuration.feedURL?.absoluteString == "https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml")
        #expect(configuration.publicEDKey == "OhLtaWdjixrruIOymzcROteZVpMNtv7fLQVSxbn+1ok=")
        #expect(configuration.isConfigured)
    }

    @Test("Sparkle config trims values and parses the build release date")
    func parsesReleaseDateAndTrimmedValues() {
        let releaseDate = "2026-04-25T00:00:00Z"
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": " yes ",
            "SUFeedURL": " https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml ",
            "SUPublicEDKey": " test-public-key ",
            "CFBundleShortVersionString": " 1.2.3 ",
            "CFBundleVersion": " 45 ",
            "RockxyBuildReleaseDate": releaseDate,
        ])

        #expect(configuration.updatesEnabled)
        #expect(configuration.feedURL?.absoluteString == "https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml")
        #expect(configuration.publicEDKey == "test-public-key")
        #expect(configuration.appVersion == "1.2.3")
        #expect(configuration.buildNumber == "45")
        #expect(configuration.buildReleaseDate == ISO8601DateFormatter().date(from: releaseDate))
    }

    @Test("Sparkle config rejects invalid feed URLs even when updates are enabled")
    func rejectsInvalidFeedURL() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "YES",
            "SUFeedURL": "http://[::1",
            "SUPublicEDKey": "public-key",
        ])

        #expect(configuration.updatesEnabled)
        #expect(configuration.feedURL == nil)
        #expect(!configuration.isConfigured)
    }

    @Test("Manual update checks can stay available when automatic updates are off")
    func supportsManualChecksWithoutAutomaticUpdates() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "NO",
            "SUFeedURL": "https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml",
            "SUPublicEDKey": "public-key",
            "RockxyBuildReleaseDate": "2026-04-25T00:00:00Z",
        ])

        #expect(!configuration.updatesEnabled)
        #expect(!configuration.isConfigured)
        #expect(configuration.supportsUserInitiatedUpdateChecks)
        #expect(!configuration.supportsAutomaticUpdateChecks)
    }

    @Test("Sparkle config fails closed when the build release date is missing")
    func defaultsReleaseDateToDistantFuture() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "YES",
            "SUFeedURL": "https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml",
            "SUPublicEDKey": "public-key",
        ])

        #expect(configuration.buildReleaseDate == .distantFuture)
    }

    @Test("Release guidance points dry runs at publish confirm")
    func releaseGuidanceMentionsPublishConfirm() throws {
        let script = try loadRepoFile("scripts/rockxy-release.sh")

        #expect(script.contains("scripts/rockxy-publish.sh --confirm"))
    }

    @Test("Developer template inherits LocalDev defaults")
    func developerTemplateIncludesLocalDevDefaults() throws {
        let template = try loadRepoFile("Configuration/Developer.xcconfig.template")

        #expect(template.contains("#include \"LocalDev.xcconfig\""))
    }

    @Test("LocalDev keeps manual update feed while disabling automatic checks")
    func localDevKeepsManualUpdateFeed() throws {
        let localDev = try loadRepoFile("Configuration/LocalDev.xcconfig")

        #expect(localDev.contains("ROCKXY_UPDATES_ENABLED = NO"))
        #expect(localDev.contains("ROCKXY_SPARKLE_FEED_URL = $(ROCKXY_PUBLIC_APPCAST_FEED_URL)"))
    }
}

@MainActor
struct AppUpdaterTests {
    @Test("Unconfigured updater remains inert")
    func disabledUpdaterNoOps() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "NO",
        ])
        let updater = AppUpdater(configuration: configuration)

        #expect(!updater.isConfigured)
        #expect(!updater.canCheckForUpdates)

        updater.startIfConfigured()
        updater.checkForUpdates()
        updater.installUpdateCheckGate { _ in
            "blocked"
        }

        #expect(!updater.canCheckForUpdates)
    }

    @Test("Manual-only updater keeps user-initiated checks available")
    func manualOnlyUpdaterAvailability() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "NO",
            "SUFeedURL": "https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml",
            "SUPublicEDKey": "public-key",
            "RockxyBuildReleaseDate": "2026-04-25T00:00:00Z",
        ])
        let updater = AppUpdater(configuration: configuration)

        #expect(!updater.isConfigured)
        #expect(updater.supportsManualChecks)
        #expect(!updater.supportsAutomaticChecks)
        #expect(updater.canInitiateUpdateCheck)
    }

    @Test("Manual-only updater still allows user-initiated checks after startup path")
    func manualOnlyUpdaterRemainsInitiableAfterStartupPath() {
        let configuration = RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "NO",
            "SUFeedURL": "https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml",
            "SUPublicEDKey": "public-key",
            "RockxyBuildReleaseDate": "2026-04-25T00:00:00Z",
        ])
        let updater = AppUpdater(configuration: configuration)

        updater.startIfConfigured()

        #expect(updater.supportsManualChecks)
        #expect(updater.canInitiateUpdateCheck)
    }
}

private func loadRepoFile(_ relativePath: String) throws -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
}
