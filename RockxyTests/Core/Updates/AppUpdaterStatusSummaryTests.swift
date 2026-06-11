import Foundation
@testable import Rockxy
import Testing

@MainActor
struct AppUpdaterStatusSummaryTests {
    @Test("Update found creates a summary")
    func updateFoundCreatesSummary() {
        let updater = AppUpdater(configuration: makeConfiguration(appVersion: "0.12.0"))

        updater.recordUpdateFound(latestVersion: "0.17.0", fetchVersionsBehind: false)

        #expect(updater.updateStatusSummary?.title == "Update Available")
        #expect(updater.updateStatusSummary?.versionLine == "v0.12.0 -> v0.17.0")
        #expect(updater.updateStatusSummary?.versionsBehind == 5)
        #expect(updater.updateStatusSummary?.badgeTitle == "5 New Updates")
    }

    @Test("No update clears the summary")
    func noUpdateClearsSummary() {
        let updater = AppUpdater(configuration: makeConfiguration(appVersion: "0.12.0"))
        updater.recordUpdateFound(latestVersion: "0.17.0", fetchVersionsBehind: false)

        updater.clearUpdateStatusSummary()

        #expect(updater.updateStatusSummary == nil)
    }

    @Test("Same or older latest version hides the summary")
    func sameOrOlderLatestVersionHidesSummary() {
        let same = AppUpdater.makeUpdateStatusSummary(
            currentVersion: "0.17.0",
            latestVersion: "0.17.0"
        )
        let older = AppUpdater.makeUpdateStatusSummary(
            currentVersion: "0.17.0",
            latestVersion: "0.12.0"
        )

        #expect(same == nil)
        #expect(older == nil)
    }

    @Test("Cross-major update without appcast history keeps generic badge")
    func crossMajorUpdateWithoutAppcastHistoryKeepsGenericBadge() {
        let summary = AppUpdater.makeUpdateStatusSummary(
            currentVersion: "0.25.0",
            latestVersion: "1.0.0"
        )

        #expect(summary?.versionsBehind == nil)
        #expect(summary?.badgeTitle == "Update Available")
    }

    @Test("Appcast count returns versions behind")
    func appcastVersionsBehindCount() {
        let data = Data(
            """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item><enclosure sparkle:shortVersionString="0.17.0" sparkle:version="26" /></item>
                <item><enclosure sparkle:shortVersionString="0.16.0" sparkle:version="25" /></item>
                <item><enclosure sparkle:shortVersionString="0.15.0" sparkle:version="24" /></item>
                <item><enclosure sparkle:shortVersionString="0.12.0" sparkle:version="15" /></item>
              </channel>
            </rss>
            """.utf8
        )

        let count = AppUpdater.versionsBehind(
            currentVersion: "0.12.0",
            latestVersion: "0.17.0",
            appcastData: data
        )

        #expect(count == 3)
    }

    @Test("Compact appcast count falls back to semantic version distance")
    func compactAppcastCountFallsBackToSemanticVersionDistance() {
        let data = Data(
            """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item><enclosure sparkle:shortVersionString="0.25.0" sparkle:version="38" /></item>
              </channel>
            </rss>
            """.utf8
        )

        let summary = AppUpdater.makeUpdateStatusSummary(
            currentVersion: "0.22.0",
            appcastData: data
        )

        #expect(summary?.latestVersion == "0.25.0")
        #expect(summary?.versionsBehind == 3)
        #expect(summary?.badgeTitle == "3 New Updates")
        #expect(summary?.countLine == "3 versions behind")
    }

    @Test("Appcast summary uses latest release and update badge")
    func appcastSummaryUsesLatestReleaseAndBadge() {
        let data = Data(
            """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item><enclosure sparkle:shortVersionString="0.17.0" sparkle:version="26" /></item>
                <item><enclosure sparkle:shortVersionString="0.16.0" sparkle:version="25" /></item>
                <item><enclosure sparkle:shortVersionString="0.15.0" sparkle:version="24" /></item>
                <item><enclosure sparkle:shortVersionString="0.14.0" sparkle:version="23" /></item>
              </channel>
            </rss>
            """.utf8
        )

        let summary = AppUpdater.makeUpdateStatusSummary(
            currentVersion: "0.12.0",
            appcastData: data
        )

        #expect(summary?.latestVersion == "0.17.0")
        #expect(summary?.versionsBehind == 4)
        #expect(summary?.badgeTitle == "4 New Updates")
        #expect(summary?.countLine == "4 versions behind")
    }

    @Test("Appcast summary tolerates top-level Sparkle version attributes")
    func appcastSummaryReadsTopLevelSparkleVersionAttributes() {
        let data = Data(
            """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item sparkle:shortVersionString="0.21.1" sparkle:version="34">
                  <enclosure url="https://example.com/Rockxy-0.21.1.dmg" />
                </item>
                <item sparkle:shortVersionString="0.21.0" sparkle:version="33">
                  <enclosure url="https://example.com/Rockxy-0.21.0.dmg" />
                </item>
                <item sparkle:shortVersionString="0.20.1" sparkle:version="32">
                  <enclosure url="https://example.com/Rockxy-0.20.1.dmg" />
                </item>
              </channel>
            </rss>
            """.utf8
        )

        let summary = AppUpdater.makeUpdateStatusSummary(
            currentVersion: "0.20.0",
            appcastData: data
        )

        #expect(summary?.latestVersion == "0.21.1")
        #expect(summary?.versionsBehind == 3)
        #expect(summary?.badgeTitle == "3 New Updates")
    }

    @Test("Appcast count deduplicates repeated item and enclosure versions")
    func appcastCountDeduplicatesRepeatedVersionMetadata() {
        let data = Data(
            """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item sparkle:shortVersionString="0.21.1" sparkle:version="34">
                  <enclosure sparkle:shortVersionString="0.21.1" sparkle:version="34" />
                </item>
                <item><enclosure sparkle:shortVersionString="0.21.0" sparkle:version="33" /></item>
                <item><enclosure sparkle:shortVersionString="0.21.0" sparkle:version="33" /></item>
                <item><enclosure sparkle:shortVersionString="0.20.1" sparkle:version="32" /></item>
                <item><enclosure sparkle:shortVersionString="0.20.0" sparkle:version="31" /></item>
              </channel>
            </rss>
            """.utf8
        )

        let count = AppUpdater.versionsBehind(
            currentVersion: "0.20.0",
            latestVersion: "0.21.1",
            appcastData: data
        )

        #expect(count == 3)
    }

    @Test("Appcast count only includes versions newer than the current app")
    func appcastCountStopsAtCurrentVersion() {
        let data = Data(
            """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item><enclosure sparkle:shortVersionString="0.21.1" sparkle:version="34" /></item>
                <item><enclosure sparkle:shortVersionString="0.21.0" sparkle:version="33" /></item>
                <item><enclosure sparkle:shortVersionString="0.20.1" sparkle:version="32" /></item>
                <item><enclosure sparkle:shortVersionString="0.20.0" sparkle:version="31" /></item>
                <item><enclosure sparkle:shortVersionString="0.19.2" sparkle:version="30" /></item>
              </channel>
            </rss>
            """.utf8
        )

        let count = AppUpdater.versionsBehind(
            currentVersion: "0.20.0",
            latestVersion: "0.21.1",
            appcastData: data
        )

        #expect(count == 3)
    }

    @Test("Single version update badge uses clean singular copy")
    func singleAppcastUpdateBadgeUsesCleanSingularCopy() {
        let data = Data(
            """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item><enclosure sparkle:shortVersionString="0.17.0" sparkle:version="26" /></item>
              </channel>
            </rss>
            """.utf8
        )

        let summary = AppUpdater.makeUpdateStatusSummary(
            currentVersion: "0.16.0",
            appcastData: data
        )

        #expect(summary?.versionsBehind == 1)
        #expect(summary?.badgeTitle == "1 New Update")
        #expect(summary?.countLine == "1 version behind")
    }

    @Test("Malformed appcast count falls back to semantic version distance")
    func malformedAppcastCountFallsBackToSemanticVersionDistance() {
        let count = AppUpdater.versionsBehind(
            currentVersion: "0.12.0",
            latestVersion: "0.17.0",
            appcastData: Data("<rss><channel>".utf8)
        )

        #expect(count == 5)
    }

    private func makeConfiguration(appVersion: String) -> RockxyUpdateConfiguration {
        RockxyUpdateConfiguration(infoDictionary: [
            "RockxyUpdatesEnabled": "NO",
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "public-key",
            "CFBundleShortVersionString": appVersion,
            "CFBundleVersion": "1",
            "RockxyBuildReleaseDate": "2026-04-28T00:00:00Z",
        ])
    }
}
