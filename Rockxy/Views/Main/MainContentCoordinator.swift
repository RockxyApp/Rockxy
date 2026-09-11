import Foundation
import os

// Renders the main content coordinator interface for the main workspace.

// MARK: - ProxyDisplayState

enum ProxyDisplayState: Equatable {
    case starting
    case stopping
    case running
    case paused
    case stopped

    // MARK: Internal

    var title: String {
        switch self {
        case .starting:
            String(localized: "Starting", bundle: RockxyLocalization.bundle)
        case .stopping:
            String(localized: "Stopping", bundle: RockxyLocalization.bundle)
        case .running:
            String(localized: "Running", bundle: RockxyLocalization.bundle)
        case .paused:
            String(localized: "Paused", bundle: RockxyLocalization.bundle)
        case .stopped:
            String(localized: "Stopped", bundle: RockxyLocalization.bundle)
        }
    }

    var captureTitle: String {
        switch self {
        case .starting:
            String(localized: "Starting Capture", bundle: RockxyLocalization.bundle)
        case .stopping:
            String(localized: "Stopping Capture", bundle: RockxyLocalization.bundle)
        case .running:
            String(localized: "Capturing Traffic", bundle: RockxyLocalization.bundle)
        case .paused:
            String(localized: "Capture Paused", bundle: RockxyLocalization.bundle)
        case .stopped:
            String(localized: "Capture Stopped", bundle: RockxyLocalization.bundle)
        }
    }

    var captureDescription: String {
        switch self {
        case .starting:
            String(localized: "Preparing the listener and system routing.", bundle: RockxyLocalization.bundle)
        case .stopping:
            String(localized: "Closing active connections and restoring system routing.", bundle: RockxyLocalization.bundle)
        case .running:
            String(localized: "New traffic is being added to the active workspace.", bundle: RockxyLocalization.bundle)
        case .paused:
            String(
                localized: "The listener stays available, but new traffic is not being added.",
                bundle: RockxyLocalization.bundle
            )
        case .stopped:
            String(localized: "No new traffic is being captured.", bundle: RockxyLocalization.bundle)
        }
    }

    var captureSystemImage: String {
        switch self {
        case .starting:
            "circle.dotted"
        case .stopping:
            "stop.circle"
        case .running:
            "record.circle.fill"
        case .paused:
            "pause.circle.fill"
        case .stopped:
            "stop.circle"
        }
    }

    var captureActionTitle: String {
        switch self {
        case .starting:
            String(localized: "Starting…", bundle: RockxyLocalization.bundle)
        case .stopping:
            String(localized: "Stopping…", bundle: RockxyLocalization.bundle)
        case .running,
             .paused:
            String(localized: "Stop Capture", bundle: RockxyLocalization.bundle)
        case .stopped:
            String(localized: "Start Capture", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ProxyListenerSnapshot

/// Immutable record of how the proxy listener was actually configured for the
/// currently running server. Captured from the exact `AppSettings` snapshot used
/// to start the proxy, so the UI can report truthful live state instead of
/// re-deriving it from settings that may have changed since launch.
struct ProxyListenerSnapshot: Equatable {
    /// The preferred port requested at startup (`AppSettings.proxyPort`).
    let requestedPort: Int
    /// The port the server actually bound — equals `requestedPort` unless a
    /// fallback was chosen because the preferred port was occupied.
    let resolvedPort: Int
    /// The address the server listens on (`127.0.0.1` or `0.0.0.0`).
    let listenAddress: String
    /// Whether auto-select-on-launch was enabled for this run.
    let autoSelectPort: Bool

    /// True when the server fell back to a different port than requested.
    var isUsingFallbackPort: Bool {
        resolvedPort != requestedPort
    }

    /// Whether the saved (preferred) listener configuration matches the
    /// parameters this running server started with. A fallback resolved port is
    /// intentionally excluded — only the *requested* startup parameters count, so
    /// an occupied-port fallback never implies the saved settings changed.
    func matchesRequestedListener(
        preferredPort: Int?,
        autoSelectPort: Bool,
        listenAddress: String
    )
        -> Bool
    {
        preferredPort == requestedPort
            && autoSelectPort == self.autoSelectPort
            && listenAddress == self.listenAddress
    }
}

// MARK: - MainContentCoordinator

/// Central coordinator for all Rockxy UI state, bridging the proxy engine, log engine,
/// analytics engine, and rule engine to SwiftUI views. Uses @Observable (not ObservableObject)
/// for fine-grained property-level observation without manual `objectWillChange` calls.
/// Domain-specific logic is split across extension files in `Views/Main/Extensions/` to keep
/// each file focused and within SwiftLint size limits.
@MainActor @Observable
final class MainContentCoordinator {
    // MARK: Lifecycle

    init(
        policy: any AppPolicy = DefaultAppPolicy(),
        workspaceLayoutPreferences: WorkspaceLayoutPreferences = WorkspaceLayoutPreferences(),
        assistantRuntime: any AssistantProviderRuntimeProtocol = AssistantProviderRuntime.shared,
        assistantSettingsProvider: @escaping @MainActor () -> AppSettings = {
            AppSettingsManager.shared.settings
        },
        projectCatalogRepository: ProjectCatalogPersisting? = nil,
        projectTabAutosaveDebounce: Duration = .milliseconds(500)
    ) {
        self.policy = policy
        self.assistantRuntime = assistantRuntime
        self.assistantSettingsProvider = assistantSettingsProvider
        self.workspaceStore = WorkspaceStore(
            maxWorkspaces: policy.maxWorkspaceTabs,
            layoutPreferences: workspaceLayoutPreferences
        )
        // A `nil` repository keeps the Project store fully in-memory (and immediately
        // ready) so tests and previews do no Application Support I/O; the app injects
        // the concrete repository later. The store shares this coordinator's policy.
        self.projectStore = ProjectStore(policy: policy, repository: projectCatalogRepository)
        self.projectTabAutosaveDebounce = projectTabAutosaveDebounce
        self.liveHistoryLimit = policy.maxLiveHistoryEntries
        refreshCaptureContextSnapshot()
    }

    deinit {
        for handle in debugAssistantTasks.values {
            handle.task.cancel()
        }
        projectTabAutosaveTask?.cancel()
        projectHydrationTask?.cancel()
        captureHealthTask?.cancel()
        proxyConfigurationRefreshTask?.cancel()
        httpsInterceptionRetryTask?.cancel()
        let probeServer = captureProbeServer
        let probeTracker = captureProbeTracker
        Task {
            await probeServer.stop()
            probeTracker.cancel()
        }
        if let rulesObserver {
            NotificationCenter.default.removeObserver(rulesObserver)
        }
        if let sslProxyingObserver {
            NotificationCenter.default.removeObserver(sslProxyingObserver)
        }
        if let evictionObserver {
            NotificationCenter.default.removeObserver(evictionObserver)
        }
    }

    // MARK: Internal

    struct DeferredBatch {
        let transactions: [HTTPTransaction]
        let generation: UInt
    }

    struct SidebarFavoritesCacheKey: Equatable {
        let transactionCount: Int
        let persistedFavoriteCount: Int
        let sessionGeneration: UInt
    }

    struct SidebarFavoritesCache {
        let key: SidebarFavoritesCacheKey
        let pinned: [HTTPTransaction]
        let saved: [HTTPTransaction]
        let notes: [HTTPTransaction]
    }

    struct DebugAssistantTaskHandle {
        let id: UUID
        let task: Task<Void, Never>
    }

    struct DebugAssistantRelatedCacheKey: Equatable {
        let primaryTransactionID: UUID
        let trafficIndexGeneration: UInt
    }

    static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "MainContentCoordinator")

    let policy: any AppPolicy
    let assistantRuntime: any AssistantProviderRuntimeProtocol
    @ObservationIgnored let assistantSettingsProvider: @MainActor () -> AppSettings

    // MARK: - Engine References

    var proxyServer = ProxyServer()
    let certificateManager = CertificateManager.shared
    let sessionManager = TrafficSessionManager()
    let logEngine = LogCaptureEngine()
    let captureProbeServer = DeveloperSetupProbeServer()
    let captureProbeTracker = CaptureProbeTracker()

    // MARK: - Rules

    var rules: [ProxyRule] = []
    var rulesLoaded = false

    // MARK: - Persistence

    var cachedSessionStore: SessionStore?

    // MARK: - Sequence Numbering (request-list ordering metadata)

    var nextSequenceNumber: Int = 0

    // MARK: - UI State — Traffic

    var transactions: [HTTPTransaction] = []
    var persistedFavorites: [HTTPTransaction] = []
    var isProxyRunning = false
    var isProxyStarting = false
    var isProxyStopping = false
    var isRetryingHTTPSInterception = false
    var activeProxyPort = AppSettingsManager.shared.settings.proxyPort
    var isRecording = true
    var sessionGeneration: UInt = 0
    var liveHistoryLimit: Int
    var isClearingSession = false
    var clearingProjectID: UUID?
    var clearingTargetGeneration: UInt?
    var deferredSessionBatches: [DeferredBatch] = []
    var proxyError: String?
    var isSystemProxyConfigured = false
    @ObservationIgnored var captureHealthTask: Task<Void, Never>?
    @ObservationIgnored var proxyConfigurationRefreshTask: Task<Void, Never>?
    @ObservationIgnored var httpsInterceptionRetryTask: Task<Void, Never>?
    @ObservationIgnored var httpsInterceptionRetryGeneration: UInt = 0

    /// The listener configuration the running proxy actually started with.
    /// Non-nil only while the proxy is running; captured from the same settings
    /// snapshot used to configure the server and cleared on stop.
    var runtimeListenerSnapshot: ProxyListenerSnapshot?

    let readiness = ReadinessCoordinator.shared

    @ObservationIgnored var debugAssistantTasks: [UUID: DebugAssistantTaskHandle] = [:]
    @ObservationIgnored var debugAssistantTransactionsByHost: [String: [HTTPTransaction]] = [:]
    @ObservationIgnored var debugAssistantIndexedTransactionIDs: Set<UUID> = []
    @ObservationIgnored var debugAssistantIndexedLiveCount = 0
    @ObservationIgnored var debugAssistantIndexedFavoriteCount = 0
    @ObservationIgnored var debugAssistantTrafficIndexGeneration: UInt = 0
    @ObservationIgnored var debugAssistantRelatedCache:
        (key: DebugAssistantRelatedCacheKey, transactions: [HTTPTransaction])?

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
    nonisolated(unsafe) var evictionObserver: NSObjectProtocol?

    // MARK: - UI State — Engine Status

    var proxyStartedAt: Date?
    var errorCount: Int = 0

    // MARK: - Breakpoint

    var breakpointManager = BreakpointManager.shared

    // MARK: - UI State — Navigation

    var favorites: [SidebarItem] = []
    var showProxyStatusPopover = false

    // MARK: - Workspace Tabs

    var workspaceStore: WorkspaceStore
    var previewTabStore = PreviewTabStore()
    var headerColumnStore = HeaderColumnStore()
    var filterPresetStore = FilterPresetStore()

    // MARK: - Projects

    /// Durable owner of the Project → traffic-tab configuration. Non-visual
    /// orchestration lives in `MainContentCoordinator+Projects`; user messaging and
    /// sheets are owned by the app layer.
    let projectStore: ProjectStore

    /// Thread-safe request-start routing snapshot consumed by SwiftNIO handlers.
    let captureContextStore = TrafficCaptureContextStore()

    /// In-memory capture histories are isolated per Project while `transactions`
    /// remains the active Project's observable UI projection.
    @ObservationIgnored var transactionsByProjectID: [UUID: [HTTPTransaction]] = [:]
    @ObservationIgnored var logEntriesByProjectID: [UUID: [LogEntry]] = [:]
    @ObservationIgnored var sessionProvenanceByProjectID: [UUID: SessionProvenance] = [:]
    @ObservationIgnored var captureGenerationByProjectID: [UUID: UInt64] = [:]
    @ObservationIgnored var nextSequenceNumberByProjectID: [UUID: Int] = [:]

    /// The last non-fatal Project operation error, exposed for the app layer to
    /// surface. Reset on the next successful operation. Not a presentation state.
    var lastProjectOperationError: ProjectMutationError?

    var projectNameEditorContext: ProjectNameEditorContext?
    var projectDeletionRequest: ProjectDeletionRequest?
    var isProjectManagerPresented = false
    var isProjectRecoveryPresented = false

    /// Debounce window that coalesces rapid traffic-tab edits into a single durable
    /// autosave. Injectable so tests can shorten it.
    @ObservationIgnored let projectTabAutosaveDebounce: Duration
    /// The single in-flight debounced autosave, replaced/cancelled on each change so
    /// the coordinator never accumulates unbounded persistence tasks.
    @ObservationIgnored var projectTabAutosaveTask: Task<Void, Never>?
    /// Coalesces concurrent startup hydration attempts so the catalog loads once.
    @ObservationIgnored var projectHydrationTask: Task<Void, Never>?
    /// True once the active Project's tabs have been applied to the workspace store.
    @ObservationIgnored var hasHydratedProjects = false
    /// True while Observation-driven autosave is armed (only after a ready load).
    @ObservationIgnored var isObservingProjectTabs = false
    /// Suppresses autosave scheduling while a Project snapshot is being applied to
    /// the workspace store, so hydration/switches never write back through the same
    /// observation seam mid-application.
    @ObservationIgnored var isApplyingProjectSnapshot = false

    // MARK: - UI State — Import/Export

    var importPreview: ImportPreview?
    var exportScopeContext: ExportScopeContext?
    var gistPublishContext: GistPublishContext?
    var sessionProvenance: SessionProvenance?
    var activeToast: ToastMessage?
    var sslProxyingRefreshToken: Int = 0
    var observedDomainsByApp: [String: Set<String>] = [:]

    private(set) var ruleLoadTask: Task<Void, Never>?
    var ruleMutationTask: Task<Void, Never>?

    @ObservationIgnored var observedDomainCountsByApp: [String: [String: Int]] = [:]

    nonisolated(unsafe) var sslProxyingObserver: NSObjectProtocol?

    /// Pending debounced note-persistence tasks, keyed by transaction id. Inline note
    /// editors update the model immediately but coalesce SQLite writes through these so a
    /// large transaction row is not rewritten on every keystroke. See `+Notes`.
    @ObservationIgnored var noteFlushTasks: [UUID: Task<Void, Never>] = [:]

    var systemProxyWarning: SystemProxyWarning? {
        guard let warning = readiness.activeWarning else {
            return nil
        }
        let action: SystemProxyWarning.Action? = switch warning.action {
        case .retry: .retry
        case .retryStop: .retryStop
        case .retryDisableSystemRouting: .retryDisableSystemRouting
        case .retryCaptureCheck: .retryCaptureCheck
        case .restoreSystemRouting: .restoreSystemRouting
        case .openHTTPSDecryption: .openHTTPSDecryption
        case .retryHTTPSInterception: .retryHTTPSInterception
        case .openGeneralSettings: .openGeneralSettings
        case .openAdvancedProxySettings: .openAdvancedProxySettings
        case .reinstallAndTrust: .reinstallAndTrust
        case nil: nil
        }
        return SystemProxyWarning(
            message: warning.message,
            action: action,
            isDismissible: warning.isDismissible,
            isActionInProgress: action == .retryHTTPSInterception && isRetryingHTTPSInterception
        )
    }

    var proxyDisplayState: ProxyDisplayState {
        if isProxyStopping {
            return .stopping
        }
        if isProxyStarting {
            return .starting
        }
        if isProxyRunning {
            return isRecording ? .running : .paused
        }
        return .stopped
    }

    var canStartProxy: Bool {
        !isProxyRunning && !isProxyStarting && !isProxyStopping
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
        set {
            let previousID = activeWorkspace.selectedTransaction?.id
            activeWorkspace.selectedTransaction = newValue
            if previousID != newValue?.id {
                resetDebugAssistantForSelectionChange()
            }
            if newValue != nil {
                revealInspectorForSelectionIfNeeded()
            }
        }
    }

    var selectedTransactionIDs: Set<UUID> {
        get { activeWorkspace.selectedTransactionIDs }
        set {
            let previousIDs = activeWorkspace.selectedTransactionIDs
            activeWorkspace.selectedTransactionIDs = newValue
            if previousIDs != newValue {
                resetDebugAssistantForSelectionChange()
            }
        }
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

    var isContextDockVisible: Bool {
        get { activeWorkspace.isContextDockVisible }
        set { activeWorkspace.isContextDockVisible = newValue }
    }

    var focusNavigatorMode: FocusNavigatorMode {
        get { activeWorkspace.focusNavigatorMode }
        set { activeWorkspace.focusNavigatorMode = newValue }
    }

    /// Opt-in live-tail mode for the active workspace. Forwards to the active `WorkspaceState`
    /// so existing UI/menu callers keep reading a single flag while the state is owned per-workspace.
    var isFollowingLiveTraffic: Bool {
        get { activeWorkspace.isFollowingLiveTraffic }
        set { activeWorkspace.isFollowingLiveTraffic = newValue }
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
        sidebarFavoriteTransactions().pinned
    }

    var allSavedTransactions: [HTTPTransaction] {
        sidebarFavoriteTransactions().saved
    }

    var allNotesTransactions: [HTTPTransaction] {
        sidebarFavoriteTransactions().notes
    }

    var totalDomainCount: Int {
        activeWorkspace.totalDomainCount
    }

    func invalidateSidebarFavoriteCache() {
        sidebarFavoritesCache = nil
    }

    func dismissToast(id: UUID) {
        guard activeToast?.id == id else {
            return
        }
        activeToast = nil
    }

    /// Configure shared policy gates. Called once from the app's main
    /// ContentView after the first coordinator is created. Separated from
    /// init so test-created coordinators do not overwrite shared gate state.
    func configureSharedGates() {
        RulePolicyGate.shared = RulePolicyGate(policy: policy)
        ScriptPolicyGate.shared = ScriptPolicyGate(policy: policy)
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
            forName: .rulesDidChange, object: nil, queue: nil
        ) { [weak self] notification in
            if let allRules = notification.object as? [ProxyRule] {
                Task { @MainActor in
                    self?.rules = allRules
                }
            }
        }
    }

    func loadInitialRules() {
        guard ruleLoadTask == nil, !rulesLoaded else {
            return
        }
        ruleLoadTask = Task { [weak self] in
            // Route through the shared idempotent loader so this and any rule tool
            // window (e.g. Map Local) share a single disk load and load-state.
            let outcome = await RuleSyncService.ensureLoaded()
            guard let self else {
                return
            }
            if outcome.isLoaded {
                self.rulesLoaded = true
            }
            self.ruleLoadTask = nil
        }
    }

    func ensureRulesLoaded() async {
        if rulesLoaded {
            return
        }
        if let existing = ruleLoadTask {
            await existing.value
            return
        }
        let task = Task { [weak self] in
            let outcome = await RuleSyncService.ensureLoaded()
            guard let self else {
                return
            }
            if outcome.isLoaded {
                self.rulesLoaded = true
            }
            self.ruleLoadTask = nil
        }
        ruleLoadTask = task
        await task.value
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
                    self.invalidateSidebarFavoriteCache()
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

    @discardableResult
    func startProxyOnLaunchIfNeeded(
        settings: AppSettings = AppSettingsStorage.load(),
        startHandler: (() -> Void)? = nil
    )
        -> Bool
    {
        guard settings.recordOnLaunch, canStartProxy else {
            return false
        }

        if let startHandler {
            startHandler()
        } else {
            startProxy()
        }
        return true
    }

    // MARK: Private

    @ObservationIgnored private var sidebarFavoritesCache: SidebarFavoritesCache?

    nonisolated(unsafe) private var rulesObserver: NSObjectProtocol?

    private func sidebarFavoriteTransactions() -> SidebarFavoritesCache {
        let key = SidebarFavoritesCacheKey(
            transactionCount: transactions.count,
            persistedFavoriteCount: persistedFavorites.count,
            sessionGeneration: sessionGeneration
        )
        if let cache = sidebarFavoritesCache,
           cache.key == key
        {
            return cache
        }

        let livePinned = transactions.filter(\.isPinned)
        let persistedPinned = persistedFavorites.filter(\.isPinned)
        let livePinnedIds = Set(livePinned.map(\.id))
        let liveSaved = transactions.filter(\.isSaved)
        let persistedSaved = persistedFavorites.filter(\.isSaved)
        let liveSavedIds = Set(liveSaved.map(\.id))
        let liveNotes = transactions.filter(\.hasNote)
        let persistedNotes = persistedFavorites.filter(\.hasNote)
        let liveNoteIds = Set(liveNotes.map(\.id))
        let cache = SidebarFavoritesCache(
            key: key,
            pinned: livePinned + persistedPinned.filter { !livePinnedIds.contains($0.id) },
            saved: liveSaved + persistedSaved.filter { !liveSavedIds.contains($0.id) },
            notes: liveNotes + persistedNotes.filter { !liveNoteIds.contains($0.id) }
        )
        sidebarFavoritesCache = cache
        return cache
    }
}

// MARK: - SystemProxyWarning

struct SystemProxyWarning {
    enum Action: Equatable {
        case retry
        case retryStop
        case retryDisableSystemRouting
        case restoreSystemRouting
        case retryCaptureCheck
        case openHTTPSDecryption
        case retryHTTPSInterception
        case openGeneralSettings
        case openAdvancedProxySettings
        case reinstallAndTrust

        // MARK: Internal

        var title: String {
            switch self {
            case .retry:
                String(localized: "Retry", bundle: RockxyLocalization.bundle)
            case .retryStop:
                String(localized: "Stop Capture", bundle: RockxyLocalization.bundle)
            case .retryDisableSystemRouting:
                String(localized: "Switch Off", bundle: RockxyLocalization.bundle)
            case .restoreSystemRouting:
                String(localized: "Restore System Routing", bundle: RockxyLocalization.bundle)
            case .retryCaptureCheck:
                String(localized: "Run Capture Check", bundle: RockxyLocalization.bundle)
            case .openHTTPSDecryption:
                String(localized: "Open HTTPS Decryption", bundle: RockxyLocalization.bundle)
            case .retryHTTPSInterception:
                String(localized: "Retry", bundle: RockxyLocalization.bundle)
            case .openGeneralSettings:
                String(localized: "Open Certificate Settings", bundle: RockxyLocalization.bundle)
            case .openAdvancedProxySettings:
                String(localized: "Open Advanced Proxy Settings", bundle: RockxyLocalization.bundle)
            case .reinstallAndTrust:
                String(localized: "Install & Trust Certificate", bundle: RockxyLocalization.bundle)
            }
        }
    }

    let message: String
    let action: Action?
    let isDismissible: Bool
    let isActionInProgress: Bool
}

// MARK: - AppInfo

/// Groups captured transactions by originating application for the sidebar "Apps" tree.
struct AppInfo: Identifiable {
    let name: String
    var domains: [String]
    var requestCount: Int
    var identity: ClientApplicationIdentity?

    init(
        name: String,
        domains: [String],
        requestCount: Int,
        identity: ClientApplicationIdentity? = nil
    ) {
        self.name = name
        self.domains = domains
        self.requestCount = requestCount
        self.identity = identity
    }

    var id: String {
        identity?.identifier ?? name
    }
}
