import Foundation
@testable import Rockxy
import Testing

/// Every wall-clock time Rockxy shows comes from `TimestampFormatter`, so one transaction reads
/// the same way in the request list, the Diff candidate picker, the WebSocket frame list, and the
/// script console. Two of those built a `DateFormatter` with a hardcoded `"HH:mm:ss"`, which is
/// locale-blind and ignores the user's 24-Hour Time preference: on `en_US` the request list said
/// "21:19:10" for the row the Diff picker called "9:19:10 PM".
struct TimestampFormatterTests {
    // MARK: Internal

    @Test("A time of day follows the viewer's locale and clock preference")
    func timeOfDayFollowsTheLocale() {
        // A 12-hour locale must not get a 24-hour clock, which is exactly what the fixed pattern
        // forced on every user whose region spells this time "9:19:10 PM".
        let twelveHour = Self.reference(locale: "en_US", template: "jms")
        let twentyFourHour = Self.reference(locale: "en_GB", template: "jms")

        // The formatter renders in the Mac's time zone, so derive the expected hour from it
        // instead of hardcoding the hour one machine happens to see.
        let hour = Calendar.current.component(.hour, from: Self.sample)
        let twelveHourClockHour = hour % 12 == 0 ? 12 : hour % 12
        #expect(twelveHour != twentyFourHour)
        #expect(twelveHour.contains(String(twelveHourClockHour)))
        #expect(twentyFourHour.contains(String(format: "%02d", hour)))
        #expect(TimestampFormatter.timeOfDay(Self.sample, locale: Locale(identifier: "en_US")) == twelveHour)
        #expect(TimestampFormatter.timeOfDay(Self.sample, locale: Locale(identifier: "en_GB")) == twentyFourHour)
    }

    @Test("Rockxy's language changes the words in a time, never the region's clock")
    func pinnedLanguageKeepsTheRegionalClock() {
        // A Chinese interface on a US Mac keeps the 12-hour clock and says so in Chinese.
        let chineseOnUSMac = AppLanguagePreference.formattingLocale(
            languageIdentifier: "zh-Hans",
            regionalBase: Locale(identifier: "en_US")
        )
        let time = TimestampFormatter.timeOfDay(Self.sample, locale: chineseOnUSMac)
        // A Chinese day-period word proves both halves: a 12-hour clock, spelled in Chinese.
        #expect(["凌晨", "早上", "上午", "中午", "下午", "晚上"].contains { time.contains($0) })
        #expect(!time.contains("PM") && !time.contains("AM"))

        // Relative dates follow the same locale instead of the Mac's language.
        let now = Self.sample.addingTimeInterval(300)
        let relative = TimestampFormatter.relative(Self.sample, to: now, locale: chineseOnUSMac)
        #expect(relative.contains("5"))
        #expect(!relative.contains("minutes"))
    }

    @Test("Frame timestamps keep their milliseconds")
    func frameTimestampsKeepMilliseconds() {
        // WebSocket frames arrive milliseconds apart; dropping the sub-second digits would make
        // the frame list unorderable by eye.
        let locale = Locale(identifier: "en_GB")
        let formatted = TimestampFormatter.timeOfDayWithMilliseconds(Self.sample, locale: locale)

        #expect(formatted == Self.reference(locale: "en_GB", template: "jmsSSS"))
        #expect(formatted.contains("123"))
        #expect(formatted != TimestampFormatter.timeOfDay(Self.sample, locale: locale))
    }

    @Test("No view formats a wall-clock time with a fixed pattern")
    func noViewPinsAClockFormat() throws {
        // `en_US_POSIX` with a fixed pattern is correct for machine-readable output — the MCP
        // version string parses that way on purpose — and is the only place it belongs.
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() where !Self.fixedPatternOwners.contains(path) {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines where line.contains("dateFormat =") {
                offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(
            offenders.isEmpty,
            "These lines pin a date pattern instead of using TimestampFormatter: \(offenders.sorted())"
        )
    }

    @Test("Dates and relative times go through TimestampFormatter's locale")
    func noViewFormatsADateInTheMacLanguage() throws {
        // `Date.formatted(date:time:)`, `.formatted(.dateTime…)` and a bare
        // `RelativeDateTimeFormatter` follow the Mac's language, so after the user picks another
        // language in Rockxy they printed "Sep 23, 2026" inside a Chinese interface.
        let spellings = [".formatted(date:", ".formatted(.dateTime", "RelativeDateTimeFormatter()"]
        var offenders: [String] = []
        for (path, source) in try Self.projectSources() where path != "Rockxy/Core/Utilities/TimestampFormatter.swift" {
            for line in source.split(separator: "\n") {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), spellings.contains(where: { code.contains($0) }) else {
                    continue
                }
                offenders.append("\(path): \(code)")
            }
        }
        #expect(offenders.isEmpty, "Format these through TimestampFormatter: \(offenders.sorted())")
    }

    // MARK: Private

    private enum ResolveError: Error {
        case rootNotFound(filePath: String)
    }

    /// 2026-09-22 21:19:10.123 local time, the row that exposed the divergence.
    private static let sample = Date(timeIntervalSince1970: 1_790_086_750.123)

    /// `MCPProtocolMessages` parses a `yyyy-MM-dd` version string with a pinned `en_US_POSIX`
    /// calendar and locale. That is machine-readable output, not a time anyone reads.
    private static let fixedPatternOwners: Set<String> = [
        "Rockxy/Core/MCPServer/MCPProtocolMessages.swift",
    ]

    /// The app plus the three targets that ship beside it. `Shared/`, `RockxyHelperTool/` and
    /// `RockxyMCP/` cannot see `TimestampFormatter`, but scanning only `Rockxy/` let a pinned date
    /// pattern there pass while the identical one in the app was caught. They hold no offender
    /// today; a new one needs a reasoned entry in `fixedPatternOwners`.
    private static let sourceDirectories = ["Rockxy", "Shared", "RockxyHelperTool", "RockxyMCP"]

    private static func reference(locale identifier: String, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: identifier)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: sample)
    }

    private static func projectSources() throws -> [(path: String, source: String)] {
        var root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while root.lastPathComponent != "RockxyTests", root.path != "/" {
            root.deleteLastPathComponent()
        }
        guard root.lastPathComponent == "RockxyTests" else {
            throw ResolveError.rootNotFound(filePath: #filePath)
        }
        root.deleteLastPathComponent()
        let prefix = root.path + "/"
        var sources: [(path: String, source: String)] = []
        for directory in sourceDirectories {
            let sourceRoot = root.appendingPathComponent(directory)
            var contributed = 0
            let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else {
                    continue
                }
                let resolved = url.resolvingSymlinksInPath().path
                let path = resolved.hasPrefix(prefix) ? String(resolved.dropFirst(prefix.count)) : resolved
                try sources.append((path, String(contentsOf: url, encoding: .utf8)))
                contributed += 1
            }
            // A directory that is renamed or removed would silently shrink the scan.
            #expect(contributed > 0, "Scanned directory contributes no Swift sources: \(directory)")
        }
        return sources
    }
}
