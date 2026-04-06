import Foundation
import os

// Renders the main content coordinator interface for the main workspace.

// MARK: - MainContentCoordinator

/// Central coordinator for all Rockxy UI state, bridging the proxy engine, log engine,
/// analytics engine, and rule engine to SwiftUI views. Uses @Observable (not ObservableObject)
/// for fine-grained property-level observation without manual `objectWillChange` calls.
/// Domain-specific logic is split across extension files in `Views/Main/Extensions/` to keep
/// each file focused and within SwiftLint size limits.
@MainActor @Observable
final class MainContentCoordinator {
    // MARK: Internal

    static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MainContentCoordinator")

    // MARK: - Engine References

    var proxyServer = ProxyServer()
    let certificateManager = CertificateManager.shared
    let sessionManager = TrafficSessionManager()
    let logEngine = LogCaptureEngine()

    // MARK: - Rules

    var rules: [ProxyRule] = []
    var rulesLoaded = false

    // MARK: - Persistence

    var cachedSessionStore: SessionStore?

    // MARK: - UI State — Selection

    var selectedTransactionIDs: Set<UUID> = []

    // MARK: - Sequence Numbering (request-list ordering metadata)

    var nextSequenceNumber: Int = 0

    // MARK: - UI State — Traffic

    var transactions: [HTTPTransaction] = []
    var persistedFavorites: [HTTPTransaction] = []
    var isProxyRunning = false
    var activeProxyPort = AppSettingsManager.shared.settings.proxyPort
    var isRecording = true
    var proxyError: String?
    var isSystemProxyConfigured = false

    let readiness = ReadinessCoordinator.shared

    // MARK: - UI State — Logs

    var logEntries: [LogEntry] = []

    // MARK: - UI State — Bandwidth

    var totalDataSize: Int64 = 0
    var uploadSpeed: Int64 = 0
    var downloadSpeed: Int64 = 0
    var totalUploadBytes: Int64 = 0
    var totalDownloadBytes: Int64 = 0
    var trafficSamples: [(timestamp: Date, upload: Int64, download: Int64)] = []
    var bandwidthTimer: Timer?
    var isProxyOverridden = false
    var isAutoSelectEnabled = true
    var evictionObserver: NSObjectProtocol?

    // MARK: - UI State — Engine Status

    var proxyStartedAt: Date?
    var errorCount: Int = 0

    // MARK: - Breakpoint

    var breakpointManager = BreakpointManager.shared

    // MARK: - UI State — Navigation

    var favorites: [SidebarItem] = []
    var showProxyStatusPopover = false

    // MARK: - Workspace Tabs

    var workspaceStore = WorkspaceStore()
    var previewTabStore = PreviewTabStore()
    var headerColumnStore = HeaderColumnStore()

    // MARK: - UI State — Import/Export

    var importPreview: ImportPreview?
    var showExportScope = false
    var exportScopeContext: ExportScopeContext?
    var sessionProvenance: SessionProvenance?
    var activeToast: ToastMessage?

    var systemProxyWarning: SystemProxyWarning? {
        guard let warning = readiness.activeWarning else {
            return nil
        }
        let action: SystemProxyWarning.Action? = switch warning.action {
        case .retry: .retry
        case .openGeneralSettings: .openGeneralSettings
        case .openAdvancedProxySettings: .openAdvancedProxySettings
        case nil: nil
        }
        return SystemProxyWarning(message: warning.message, action: action, isDismissible: warning.isDismissible)
    }

    var activeWorkspace: WorkspaceState {
        workspaceStore.activeWorkspace
    }

    // MARK: - Workspace Forwarding (backward compatibility)

    var filteredTransactions: [HTTPTransaction] {
        get { activeWorkspace.filteredTransactions }
        set { activeWorkspace.filteredTransactions = newValue }
    }

    var selectedTransaction: HTTPTransaction? {
        get { activeWorkspace.selectedTransaction }
        set { activeWorkspace.selectedTransaction = newValue }
    }

    var filterCriteria: FilterCriteria {
        get { activeWorkspace.filterCriteria }
        set { activeWorkspace.filterCriteria = newValue }
    }

    var filterRules: [FilterRule] {
        get { activeWorkspace.filterRules }
        set { activeWorkspace.filterRules = newValue }
    }

    var isFilterBarVisible: Bool {
        get { activeWorkspace.isFilterBarVisible }
        set { activeWorkspace.isFilterBarVisible = newValue }
    }

    var activeMainTab: MainTab {
        get { activeWorkspace.activeMainTab }
        set { activeWorkspace.activeMainTab = newValue }
    }

    var sidebarSelection: SidebarItem? {
        get { activeWorkspace.sidebarSelection }
        set { activeWorkspace.sidebarSelection = newValue }
    }

    var inspectorTab: InspectorTab {
        get { activeWorkspace.inspectorTab }
        set { activeWorkspace.inspectorTab = newValue }
    }

    var inspectorLayout: InspectorLayout {
        get { activeWorkspace.inspectorLayout }
        set { activeWorkspace.inspectorLayout = newValue }
    }

    var selectedLogEntry: LogEntry? {
        get { activeWorkspace.selectedLogEntry }
        set { activeWorkspace.selectedLogEntry = newValue }
    }

    var domainTree: [DomainNode] {
        get { activeWorkspace.domainTree }
        set { activeWorkspace.domainTree = newValue }
    }

    var domainIndexMap: [String: Int] {
        get { activeWorkspace.domainIndexMap }
        set { activeWorkspace.domainIndexMap = newValue }
    }

    var appNodes: [AppInfo] {
        get { activeWorkspace.appNodes }
        set { activeWorkspace.appNodes = newValue }
    }

    var appNodeIndexMap: [String: Int] {
        get { activeWorkspace.appNodeIndexMap }
        set { activeWorkspace.appNodeIndexMap = newValue }
    }

    // MARK: - Table-Facing Derived State (read-only forwarding)

    var filteredRows: [RequestListRow] {
        activeWorkspace.filteredRows
    }

    var activeSortDescriptors: [NSSortDescriptor] {
        get { activeWorkspace.activeSortDescriptors }
        set { activeWorkspace.activeSortDescriptors = newValue }
    }

    var refreshToken: Int {
        activeWorkspace.refreshToken
    }

    // MARK: - Sidebar Favorites (live + persisted, deduplicated)

    var allPinnedTransactions: [HTTPTransaction] {
        let live = transactions.filter(\.isPinned)
        let persisted = persistedFavorites.filter(\.isPinned)
        let liveIds = Set(live.map(\.id))
        return live + persisted.filter { !liveIds.contains($0.id) }
    }

    var allSavedTransactions: [HTTPTransaction] {
        let live = transactions.filter(\.isSaved)
        let persisted = persistedFavorites.filter(\.isSaved)
        let liveIds = Set(live.map(\.id))
        return live + persisted.filter { !liveIds.contains($0.id) }
    }

    // MARK: - Transaction Lookup (migration seam — O(n), next issue replaces with indexed/store lookup)

    func transaction(for id: UUID) -> HTTPTransaction? {
        if let live = transactions.first(where: { $0.id == id }) {
            return live
        }
        return persistedFavorites.first(where: { $0.id == id })
    }

    func setupRulesObserver() {
        guard rulesObserver == nil else {
            return
        }
        rulesObserver = NotificationCenter.default.addObserver(
            forName: .rulesDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            if let allRules = notification.object as? [ProxyRule] {
                Task { @MainActor in
                    self?.rules = allRules
                }
            }
        }
    }

    func loadInitialRules() {
        guard !rulesLoaded else {
            return
        }
        rulesLoaded = true
        Task { await RuleSyncService.loadFromDisk() }
    }

    func resolveSessionStore() throws -> SessionStore {
        if let store = cachedSessionStore {
            return store
        }
        let store = try SessionStore()
        cachedSessionStore = store
        return store
    }

    // MARK: - Startup

    func loadPersistedFavorites() {
        do {
            let store = try resolveSessionStore()
            Task {
                do {
                    let persisted = try await store.loadPinnedAndSavedTransactions()
                    self.persistedFavorites = persisted
                    // Assign deterministic sequence numbers starting from current counter
                    // to avoid collisions with live rows assigned while the load suspended
                    let base = self.nextSequenceNumber
                    for (index, transaction) in persisted.enumerated() {
                        transaction.sequenceNumber = base + index
                    }
                    self.nextSequenceNumber = base + persisted.count
                } catch {
                    Self.logger.error("Failed to load persisted favorites: \(error.localizedDescription)")
                }
            }
        } catch {
            Self.logger.error("Failed to create SessionStore: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    private var rulesObserver: NSObjectProtocol?
}

// MARK: - SystemProxyWarning

struct SystemProxyWarning {
    enum Action {
        case retry
        case openGeneralSettings
        case openAdvancedProxySettings

        // MARK: Internal

        var title: String {
            switch self {
            case .retry:
                String(localized: "Retry")
            case .openGeneralSettings:
                String(localized: "Open Certificate Settings")
            case .openAdvancedProxySettings:
                String(localized: "Open Advanced Proxy Settings")
            }
        }
    }

    let message: String
    let action: Action?
    let isDismissible: Bool
}

// MARK: - AppInfo

/// Groups captured transactions by originating application for the sidebar "Apps" tree.
struct AppInfo: Identifiable {
    let name: String
    var domains: [String]
    var requestCount: Int

    var id: String {
        name
    }
}

// MARK: - DomainNode

/// Represents a single domain in the sidebar source list, tracking its aggregate request count.
struct DomainNode: Identifiable, Hashable {
    let id: String
    let domain: String
    var requestCount: Int
    var children: [DomainNode]

    static func == (lhs: DomainNode, rhs: DomainNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
