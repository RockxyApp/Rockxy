import Foundation
import os

/// Bundle-driven Sparkle configuration. Missing or placeholder values are treated
/// as disabled so local and test builds do not perform accidental update checks.
struct RockxyUpdateConfiguration {
    // MARK: Lifecycle

    init(bundle: Bundle) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary info: [String: Any]) {
        updatesEnabled = Self.bool(
            named: "RockxyUpdatesEnabled",
            in: info,
            fallback: false
        )

        let rawFeedURL = Self.string(named: "SUFeedURL", in: info)
        let normalizedFeedURL = Self.normalizedValue(rawFeedURL)
        feedURL = normalizedFeedURL.flatMap(URL.init(string:))

        publicEDKey = Self.normalizedValue(
            Self.string(named: "SUPublicEDKey", in: info)
        ) ?? ""

        appVersion = Self.normalizedValue(
            Self.string(named: "CFBundleShortVersionString", in: info)
        ) ?? "0"
        buildNumber = Self.normalizedValue(
            Self.string(named: "CFBundleVersion", in: info)
        ) ?? "0"

        if let parsedBuildReleaseDate = Self.date(
            named: "RockxyBuildReleaseDate",
            in: info
        ) {
            buildReleaseDate = parsedBuildReleaseDate
        } else {
            Self.logger.error("Missing or invalid RockxyBuildReleaseDate; failing update eligibility closed.")
            buildReleaseDate = .distantFuture
        }
    }

    // MARK: Internal

    static let current = RockxyUpdateConfiguration(bundle: .main)

    let updatesEnabled: Bool
    let feedURL: URL?
    let publicEDKey: String
    let appVersion: String
    let buildNumber: String
    let buildReleaseDate: Date

    var isConfigured: Bool {
        updatesEnabled && feedURL != nil && !publicEDKey.isEmpty
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "RockxyUpdateConfiguration"
    )
    private static let iso8601Formatter = ISO8601DateFormatter()

    private static func string(named key: String, in info: [String: Any]) -> String {
        (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func bool(
        named key: String,
        in info: [String: Any],
        fallback: Bool
    ) -> Bool {
        if let value = info[key] as? Bool {
            return value
        }

        let raw = string(named: key, in: info).lowercased()
        if raw.isEmpty {
            return fallback
        }

        switch raw {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return fallback
        }
    }

    private static func normalizedValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.contains("__PENDING__") || trimmed.localizedCaseInsensitiveContains("placeholder") {
            return nil
        }

        return trimmed
    }

    private static func date(named key: String, in info: [String: Any]) -> Date? {
        guard let raw = normalizedValue(string(named: key, in: info)) else {
            return nil
        }
        return iso8601Formatter.date(from: raw)
    }
}
