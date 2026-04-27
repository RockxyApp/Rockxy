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

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    // MARK: Lifecycle

    init(configuration: RockxyUpdateConfiguration) {
        self.configuration = configuration
        updateCheckGate = nil
        userDriver = nil
        updater = nil
        sparkleCancellables = []
        super.init()

        if configuration.isConfigured {
            let userDriver = RockxyUpdateUserDriver(
                hostBundle: .main,
                configuration: configuration
            )
            self.userDriver = userDriver
            updater = SPUUpdater(
                hostBundle: .main,
                applicationBundle: .main,
                userDriver: userDriver,
                delegate: self
            )
            bindSparkleState()
            refreshSparkleState()
        }
    }

    // MARK: Internal

    static let shared = AppUpdater(configuration: .current)

    static let fullChangelogURL: URL = {
        if let url = URL(string: "https://github.com/RockxyApp/Rockxy/releases") {
            return url
        }
        return URL(fileURLWithPath: "/")
    }()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var sendsSystemProfile = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var updateCheckInterval: TimeInterval = UpdateCheckIntervalOption.daily.rawValue
    @Published private(set) var sessionInProgress = false

    let configuration: RockxyUpdateConfiguration

    var isConfigured: Bool {
        updater != nil
    }

    var currentVersionSummary: String {
        "\(configuration.appVersion) (\(configuration.buildNumber))"
    }

    var updateAvailabilitySummary: String {
        if isConfigured {
            return String(localized: "Signed updates are enabled for this build.")
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
        guard let updater else {
            Self.logger.info("Sparkle updater skipped: feed or public key is not configured.")
            return
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
        }
    }

    func checkForUpdates() {
        guard let updater else {
            return
        }

        updater.checkForUpdates()
        refreshSparkleState()
    }

    func openFullChangelog() {
        NSWorkspace.shared.open(Self.fullChangelogURL)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater else {
            return
        }

        updater.automaticallyChecksForUpdates = enabled
        refreshSparkleState()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let updater, updater.allowsAutomaticUpdates else {
            return
        }

        updater.automaticallyDownloadsUpdates = enabled
        refreshSparkleState()
    }

    func setSendsSystemProfile(_ enabled: Bool) {
        guard let updater else {
            return
        }

        updater.sendsSystemProfile = enabled
        refreshSparkleState()
    }

    func setUpdateCheckInterval(_ interval: TimeInterval) {
        guard let updater else {
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
    private var sparkleCancellables: [AnyCancellable]

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
