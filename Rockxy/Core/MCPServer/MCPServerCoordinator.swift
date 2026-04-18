import Foundation
import os

// MARK: - MCPServerCoordinator

/// App-level coordinator that manages MCP server lifecycle. Lives above
/// ContentView and survives window close — the MCP server remains available
/// to external clients regardless of UI state.
@MainActor @Observable
final class MCPServerCoordinator {
    // MARK: Lifecycle

    init(sessionStoreFactory: @escaping @MainActor () throws -> SessionStore = { try SessionStore() }) {
        self.sessionStoreFactory = sessionStoreFactory
    }

    // MARK: Internal

    // MARK: - Shared

    static let shared = MCPServerCoordinator()

    private(set) var isRunning = false
    private(set) var activePort: Int?
    private(set) var lastError: String?
    private(set) var isStarting = false

    /// Called when the app's main coordinator is available to wire live data providers.
    func attachProviders(
        flow: any MCPLiveFlowProvider,
        state: any MCPProxyStateProvider
    ) {
        flowProvider = flow
        stateProvider = state
        Self.logger.debug("MCP providers attached")
    }

    /// Clears live providers if the owning coordinator is intentionally torn down.
    func detachProviders() {
        flowProvider = nil
        stateProvider = nil
        Self.logger.debug("MCP providers detached")
    }

    /// Resolve the current live flow provider, if one is currently attached.
    func currentFlowProvider() -> (any MCPLiveFlowProvider)? {
        flowProvider
    }

    /// Resolve the current proxy state provider, if one is currently attached.
    func currentStateProvider() -> (any MCPProxyStateProvider)? {
        stateProvider
    }

    /// Lazily-created session store for persisted transaction fallback.
    func resolveSessionStore() -> SessionStore? {
        if let store = cachedSessionStore {
            return store
        }
        do {
            let store = try sessionStoreFactory()
            cachedSessionStore = store
            return store
        } catch {
            Self.logger.error("Failed to create SessionStore for MCP fallback: \(error.localizedDescription)")
            return nil
        }
    }

    func updateRedactionSetting(_ enabled: Bool) {
        redactionState?.update(isEnabled: enabled)
    }

    func startIfEnabled() async {
        let settings = AppSettingsManager.shared.settings
        guard settings.mcpServerEnabled else {
            Self.logger.debug("MCP server disabled in settings, skipping start")
            return
        }
        guard !isRunning, !isStarting else {
            Self.logger.debug("MCP server start skipped because it is already running or starting")
            return
        }
        isStarting = true
        defer { isStarting = false }

        let config = MCPServerConfiguration(
            port: settings.mcpServerPort
        )
        let state = MCPRedactionState(isEnabled: settings.mcpRedactSensitiveData)
        redactionState = state
        let redactionPolicy = MCPRedactionPolicy(state: state)

        let flowService = MCPFlowQueryService(
            serverCoordinator: self,
            redactionPolicy: redactionPolicy
        )

        let statusService = MCPStatusService(
            serverCoordinator: self
        )

        let ruleService = MCPRuleQueryService(ruleEngine: RuleEngine.shared)

        let registry = MCPToolRegistry(
            flowService: flowService,
            statusService: statusService,
            ruleService: ruleService
        )

        let server = MCPServer(
            configuration: config,
            toolRegistry: registry
        )

        do {
            try await server.start()
            if stopRequested {
                await server.stop()
                mcpServer = nil
                isRunning = false
                activePort = nil
                lastError = nil
                stopRequested = false
                Self.logger.info("MCP server start completed after stop request; server stopped immediately")
                return
            }
            mcpServer = server
            isRunning = true
            activePort = await server.activePort
            lastError = nil
            Self.logger.info("MCP server started on port \(config.port)")
        } catch {
            mcpServer = nil
            isRunning = false
            activePort = nil
            lastError = error.localizedDescription
            stopRequested = false
            Self.logger.error("MCP server failed to start: \(error.localizedDescription)")
        }
    }

    func stop() async {
        stopRequested = true
        guard let server = mcpServer else {
            if !isStarting {
                stopRequested = false
            }
            return
        }
        await server.stop()
        mcpServer = nil
        isRunning = false
        activePort = nil
        lastError = nil
        stopRequested = false
        Self.logger.info("MCP server stopped")
    }

    func restart() async {
        await stop()
        stopRequested = false
        await startIfEnabled()
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "MCPServerCoordinator"
    )

    private let sessionStoreFactory: @MainActor () throws -> SessionStore
    private var mcpServer: MCPServer?
    private var redactionState: MCPRedactionState?
    private var cachedSessionStore: SessionStore?
    private weak var flowProvider: (any MCPLiveFlowProvider)?
    private weak var stateProvider: (any MCPProxyStateProvider)?
    private var stopRequested = false
}
