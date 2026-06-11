import AppKit
import Combine
import Foundation
import os
import Sparkle

enum UpdateCheckIntervalOption: Double, CaseIterable, Identifiable {
    case daily = 86_400
    case weekly = 604_800
    case monthly = 2_592_000

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .daily:
            String(localized: "Daily")
        case .weekly:
            String(localized: "Weekly")
        case .monthly:
            String(localized: "Monthly")
        }
    }

    static func closest(to interval: TimeInterval) -> Self {
        let supported = Self.allCases
        return supported.min { lhs, rhs in
            abs(lhs.rawValue - interval) < abs(rhs.rawValue - interval)
        } ?? .daily
    }
}

private final class AppcastVersionParser: NSObject, XMLParserDelegate {
    static func versions(from data: Data) -> [String]? {
        let delegate = AppcastVersionParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }
        return delegate.versions
    }

    private var versions: [String] = []
    private var currentItemVersion: String?
    private var isParsingItem = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "item":
            isParsingItem = true
            currentItemVersion = versionString(in: attributeDict)

        case "enclosure":
            guard let version = versionString(in: attributeDict) else {
                return
            }
            if isParsingItem {
                currentItemVersion = currentItemVersion ?? version
            } else {
                versions.append(version)
            }

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "item" else {
            return
        }

        if let currentItemVersion {
            versions.append(currentItemVersion)
        }
        currentItemVersion = nil
        isParsingItem = false
    }

    private func versionString(in attributes: [String: String]) -> String? {
        let version = attributes["sparkle:shortVersionString"]
            ?? attributes["shortVersionString"]
            ?? attributes["http://www.andymatuschak.org/xml-namespaces/sparkle:shortVersionString"]
        if let version, !version.isEmpty {
            return version
        }
        return nil
    }
}

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    struct UpdateStatusSummary: Equatable {
        let currentVersion: String
        let latestVersion: String
        let versionsBehind: Int?

        var title: String {
            String(localized: "Update Available")
        }

        var versionLine: String {
            "v\(currentVersion) -> v\(latestVersion)"
        }

        var countLine: String? {
            guard let versionsBehind, versionsBehind > 0 else {
                return nil
            }
            if versionsBehind == 1 {
                return String(localized: "1 version behind")
            }
            return String(localized: "\(versionsBehind) versions behind")
        }

        var badgeTitle: String {
            guard let versionsBehind, versionsBehind > 0 else {
                return title
            }
            if versionsBehind == 1 {
                return String(localized: "1 New Update")
            }
            return String(localized: "\(versionsBehind) New Updates")
        }

        func replacingVersionsBehind(_ count: Int?) -> Self {
            .init(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                versionsBehind: count
            )
        }
    }

    // MARK: Lifecycle

    init(configuration: RockxyUpdateConfiguration) {
        self.configuration = configuration
        updateCheckGate = nil
        userDriver = nil
        updater = nil
        updateStatusTask = nil
        sparkleCancellables = []
        super.init()

        if configuration.supportsUserInitiatedUpdateChecks, !configuration.supportsAutomaticUpdateChecks {
            Self.installManualOnlyOverrides()
        }

        if configuration.supportsUserInitiatedUpdateChecks {
            let userDriver = RockxyUpdateUserDriver(
                hostBundle: .main,
                configuration: configuration
            )
            userDriver.updateFoundHandler = { [weak self] item in
                self?.recordUpdateFound(item)
            }
            userDriver.noUpdateHandler = { [weak self] _ in
                self?.clearUpdateStatusSummary()
            }
            self.userDriver = userDriver
            updater = SPUUpdater(
                hostBundle: .main,
                applicationBundle: .main,
                userDriver: userDriver,
                delegate: self
            )
            bindSparkleState()
        }
    }

    // MARK: Internal

    static let shared = AppUpdater(configuration: .current)

    static let fullChangelogURL: URL = {
        guard let url = URL(string: "https://github.com/RockxyApp/Rockxy/releases") else {
            preconditionFailure("Invalid full changelog URL")
        }
        return url
    }()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var sendsSystemProfile = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var updateCheckInterval: TimeInterval = UpdateCheckIntervalOption.daily.rawValue
    @Published private(set) var sessionInProgress = false
    @Published private(set) var updateStatusSummary: UpdateStatusSummary?

    let configuration: RockxyUpdateConfiguration

    var isConfigured: Bool {
        supportsAutomaticChecks
    }

    var supportsManualChecks: Bool {
        configuration.supportsUserInitiatedUpdateChecks
    }

    var supportsAutomaticChecks: Bool {
        configuration.supportsAutomaticUpdateChecks
    }

    var canInitiateUpdateCheck: Bool {
        guard supportsManualChecks else {
            return false
        }

        return !hasStartedUpdater || canCheckForUpdates
    }

    var currentVersionSummary: String {
        "\(configuration.appVersion) (\(configuration.buildNumber))"
    }

    var updateAvailabilitySummary: String {
        if supportsAutomaticChecks {
            return String(localized: "Signed updates are enabled for this build.")
        } else if supportsManualChecks {
            return String(
                localized: "Manual update checks are available in this local build. Automatic checks stay off while developing in Xcode."
            )
        } else {
            return String(localized: "Software updates are unavailable in this local build.")
        }
    }

    var lastCheckedDescription: String {
        guard let lastUpdateCheckDate else {
            return String(localized: "Never")
        }

        return lastUpdateCheckDate.formatted(date: .abbreviated, time: .shortened)
    }

    func installUpdateCheckGate(_ gate: @escaping @MainActor (SPUUpdateCheck) -> String?) {
        updateCheckGate = gate
    }

    func startIfConfigured() {
        guard supportsAutomaticChecks else {
            if supportsManualChecks {
                Self.logger.info("Sparkle automatic checks skipped for this build; manual checks remain available.")
                refreshUpdateStatusFromAppcast()
            } else {
                Self.logger.info("Sparkle updater skipped: feed or public key is not configured.")
            }
            return
        }

        do {
            try ensureUpdaterStarted()
            refreshUpdateStatusFromAppcast()
        } catch {
            presentUpdaterStartError(error)
        }
    }

    func checkForUpdates() {
        guard let updater, supportsManualChecks else {
            return
        }

        do {
            try ensureUpdaterStarted()
        } catch {
            presentUpdaterStartError(error)
            return
        }

        updater.checkForUpdates()
        refreshSparkleState()
    }

    func showUpdatesFromStatusBadge() {
        if sessionInProgress {
            userDriver?.showUpdateInFocus()
            return
        }

        checkForUpdates()
    }

    func openFullChangelog() {
        NSWorkspace.shared.open(Self.fullChangelogURL)
    }

    func refreshUpdateStatusFromAppcast() {
        guard let feedURL = configuration.feedURL else {
            return
        }

        updateStatusTask?.cancel()
        let currentVersion = configuration.appVersion
        updateStatusTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: feedURL)
                let summary = Self.makeUpdateStatusSummary(
                    currentVersion: currentVersion,
                    appcastData: data
                )
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.updateStatusSummary = summary
                }
            } catch {
                Self.logger.debug("Unable to refresh update status from appcast: \(error.localizedDescription)")
            }
        }
    }

    func recordUpdateFound(_ item: SUAppcastItem) {
        recordUpdateFound(latestVersion: item.displayVersionString)
    }

    func recordUpdateFound(latestVersion: String, fetchVersionsBehind: Bool = true) {
        updateStatusTask?.cancel()
        guard let summary = Self.makeUpdateStatusSummary(
            currentVersion: configuration.appVersion,
            latestVersion: latestVersion
        ) else {
            updateStatusSummary = nil
            return
        }

        updateStatusSummary = summary

        guard fetchVersionsBehind, let feedURL = configuration.feedURL else {
            return
        }

        updateStatusTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: feedURL)
                let count = Self.versionsBehind(
                    currentVersion: summary.currentVersion,
                    latestVersion: summary.latestVersion,
                    appcastData: data
                )
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard self?.updateStatusSummary?.latestVersion == summary.latestVersion else {
                        return
                    }
                    self?.updateStatusSummary = summary.replacingVersionsBehind(count)
                }
            } catch {
                Self.logger.debug("Unable to compute versions behind from appcast: \(error.localizedDescription)")
            }
        }
    }

    func clearUpdateStatusSummary() {
        updateStatusTask?.cancel()
        updateStatusTask = nil
        updateStatusSummary = nil
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater, supportsAutomaticChecks else {
            return
        }

        updater.automaticallyChecksForUpdates = enabled
        refreshSparkleState()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let updater, supportsAutomaticChecks, updater.allowsAutomaticUpdates else {
            return
        }

        updater.automaticallyDownloadsUpdates = enabled
        refreshSparkleState()
    }

    func setSendsSystemProfile(_ enabled: Bool) {
        guard let updater, supportsAutomaticChecks else {
            return
        }

        updater.sendsSystemProfile = enabled
        refreshSparkleState()
    }

    func setUpdateCheckInterval(_ interval: TimeInterval) {
        guard let updater, supportsAutomaticChecks else {
            return
        }

        updater.updateCheckInterval = interval
        refreshSparkleState()
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "AppUpdater"
    )

    private var userDriver: RockxyUpdateUserDriver?
    private var updater: SPUUpdater?
    private var hasStartedUpdater = false
    private var updateCheckGate: (@MainActor (SPUUpdateCheck) -> String?)?
    private var updateStatusTask: Task<Void, Never>?
    private var sparkleCancellables: [AnyCancellable]

    static func makeUpdateStatusSummary(
        currentVersion: String,
        latestVersion: String,
        versionsBehind: Int? = nil
    ) -> UpdateStatusSummary? {
        guard compareVersions(latestVersion, currentVersion) == .orderedDescending else {
            return nil
        }
        let resolvedVersionsBehind = versionsBehind ?? semanticVersionsBehind(
            currentVersion: currentVersion,
            latestVersion: latestVersion
        )
        return UpdateStatusSummary(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            versionsBehind: resolvedVersionsBehind
        )
    }

    static func makeUpdateStatusSummary(
        currentVersion: String,
        appcastData: Data
    ) -> UpdateStatusSummary? {
        guard let latestVersion = AppcastVersionParser.versions(from: appcastData)?.first else {
            return nil
        }
        return makeUpdateStatusSummary(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            versionsBehind: versionsBehind(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                appcastData: appcastData
            )
        )
    }

    static func versionsBehind(
        currentVersion: String,
        latestVersion: String,
        appcastData: Data
    ) -> Int? {
        let semanticCount = semanticVersionsBehind(
            currentVersion: currentVersion,
            latestVersion: latestVersion
        )
        guard let versions = AppcastVersionParser.versions(from: appcastData) else {
            return semanticCount
        }

        var seen: Set<String> = []
        let newerVersions = versions.filter { version in
            guard seen.insert(version).inserted else {
                return false
            }
            return compareVersions(version, currentVersion) == .orderedDescending
                && compareVersions(version, latestVersion) != .orderedDescending
        }
        let appcastCount = newerVersions.isEmpty ? nil : newerVersions.count
        if let appcastCount, appcastCount > 1 {
            return appcastCount
        }
        return [appcastCount, semanticCount].compactMap { $0 }.max()
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = versionComponents(lhs)
        let rhsComponents = versionComponents(rhs)
        let count = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<count {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0
            if lhsValue < rhsValue {
                return .orderedAscending
            }
            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    private static func semanticVersionsBehind(currentVersion: String, latestVersion: String) -> Int? {
        guard compareVersions(latestVersion, currentVersion) == .orderedDescending else {
            return nil
        }

        let current = semanticVersionComponents(currentVersion)
        let latest = semanticVersionComponents(latestVersion)
        guard current.major == latest.major else {
            return nil
        }

        if current.minor == latest.minor {
            let count = latest.patch - current.patch
            return count > 0 ? count : nil
        }

        guard current.patch == 0 else {
            return nil
        }

        let minorCount = latest.minor - current.minor
        guard minorCount > 0 else {
            return nil
        }
        return minorCount + latest.patch
    }

    private static func semanticVersionComponents(_ version: String) -> (major: Int, minor: Int, patch: Int) {
        let components = versionComponents(version)
        return (
            major: versionComponent(at: 0, in: components),
            minor: versionComponent(at: 1, in: components),
            patch: versionComponent(at: 2, in: components)
        )
    }

    private static func versionComponent(at index: Int, in components: [Int]) -> Int {
        components.indices.contains(index) ? components[index] : 0
    }

    private static func installManualOnlyOverrides(defaults: UserDefaults = .standard) {
        var argumentDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        argumentDomain["SUEnableAutomaticChecks"] = false
        argumentDomain["SUAllowsAutomaticUpdates"] = false
        defaults.setVolatileDomain(argumentDomain, forName: UserDefaults.argumentDomain)
    }

    private func ensureUpdaterStarted() throws {
        guard let updater else {
            throw NSError(
                domain: "Rockxy.AppUpdater",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        localized: "Software updates are not configured for this build."
                    )
                ]
            )
        }
        guard !hasStartedUpdater else {
            return
        }

        hasStartedUpdater = true

        do {
            try updater.start()
            refreshSparkleState()
            Self.logger.info("Sparkle updater started.")
        } catch {
            hasStartedUpdater = false
            Self.logger.error("Sparkle updater failed to start: \(error.localizedDescription)")
            throw error
        }
    }

    private func bindSparkleState() {
        guard let updater else {
            return
        }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &sparkleCancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &sparkleCancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }
            .store(in: &sparkleCancellables)

        updater.publisher(for: \.allowsAutomaticUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.allowsAutomaticUpdates = $0 }
            .store(in: &sparkleCancellables)

        updater.publisher(for: \.sendsSystemProfile)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.sendsSystemProfile = $0 }
            .store(in: &sparkleCancellables)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastUpdateCheckDate = $0 }
            .store(in: &sparkleCancellables)

        updater.publisher(for: \.updateCheckInterval)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateCheckInterval = $0 }
            .store(in: &sparkleCancellables)

        updater.publisher(for: \.sessionInProgress)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.sessionInProgress = $0 }
            .store(in: &sparkleCancellables)
    }

    private func refreshSparkleState() {
        guard let updater else {
            canCheckForUpdates = false
            automaticallyChecksForUpdates = false
            automaticallyDownloadsUpdates = false
            allowsAutomaticUpdates = false
            sendsSystemProfile = false
            lastUpdateCheckDate = nil
            updateCheckInterval = UpdateCheckIntervalOption.daily.rawValue
            sessionInProgress = false
            return
        }

        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        sendsSystemProfile = updater.sendsSystemProfile
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        updateCheckInterval = updater.updateCheckInterval
        sessionInProgress = updater.sessionInProgress
    }

    private func presentUpdaterStartError(_ error: Error) {
        let nsError = error as NSError
        guard let userDriver else {
            Self.logger.error(
                "Unable to present updater start error because the Sparkle user driver is unavailable. domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) message=\(nsError.localizedDescription, privacy: .public)"
            )
            return
        }

        userDriver.controller.showError(nsError) {}
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if let message = updateCheckGate?(updateCheck) {
            throw NSError(
                domain: "Rockxy.AppUpdater",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Self.logger.info(
            "User chose update action \(choice.rawValue, privacy: .public) for \(updateItem.displayVersionString, privacy: .public) at stage \(state.stage.rawValue, privacy: .public)"
        )
    }
}
