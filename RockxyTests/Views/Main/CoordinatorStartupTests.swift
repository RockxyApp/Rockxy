import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct CoordinatorStartupTests {
    @Test("Proxy menu actions remain disabled until start and stop complete")
    func commandActionsRespectLifecycle() {
        let coordinator = MainContentCoordinator()
        let actions = MainContentCommandActions(coordinator: coordinator)
        #expect(actions.canStartProxy)
        #expect(!actions.canStopProxy)
        coordinator.isProxyStarting = true
        #expect(!actions.canStartProxy)
        #expect(!actions.canStopProxy)
        coordinator.isProxyStarting = false
        coordinator.isProxyRunning = true
        #expect(!actions.canStartProxy)
        #expect(actions.canStopProxy)
        coordinator.isProxyStopping = true
        #expect(!actions.canStopProxy)
        coordinator.isProxyRunning = false
        #expect(!actions.canStartProxy)
        coordinator.isProxyStopping = false
        #expect(actions.canStartProxy)
    }

    @Test("ensureRulesLoaded sets rulesLoaded to true")
    func ensureRulesLoadedSetsFlag() async {
        await RuleTestLock.shared.acquire()
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()
        #expect(!coordinator.rulesLoaded)

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)

        await RuleEngine.shared.replaceAll(engineSnapshot)
        await RuleTestLock.shared.release()
    }

    @Test("ruleLoadTask is cleared after ensureRulesLoaded completes")
    func ruleLoadTaskClearedAfterCompletion() async {
        await RuleTestLock.shared.acquire()
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()
        #expect(coordinator.ruleLoadTask == nil)

        await coordinator.ensureRulesLoaded()
        // Completion clears the task handle so the coordinator no longer retains it.
        #expect(coordinator.ruleLoadTask == nil)
        #expect(coordinator.rulesLoaded)

        await RuleEngine.shared.replaceAll(engineSnapshot)
        await RuleTestLock.shared.release()
    }

    @Test("ensureRulesLoaded early-returns when rules are already loaded")
    func ensureRulesLoadedIdempotent() async {
        await RuleTestLock.shared.acquire()
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)
        #expect(coordinator.ruleLoadTask == nil)

        // Second call sees `rulesLoaded == true` and returns without spawning a new task.
        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)
        #expect(coordinator.ruleLoadTask == nil)

        await RuleEngine.shared.replaceAll(engineSnapshot)
        await RuleTestLock.shared.release()
    }

    @Test("loadInitialRules stores ruleLoadTask without blocking")
    func loadInitialRulesStoresTask() async {
        await RuleTestLock.shared.acquire()
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()
        coordinator.loadInitialRules()

        #expect(coordinator.ruleLoadTask != nil)
        #expect(!coordinator.rulesLoaded)

        // Await completion so the background Task doesn't contend with later tests
        await coordinator.ruleLoadTask?.value
        await RuleEngine.shared.replaceAll(engineSnapshot)
        await RuleTestLock.shared.release()
    }

    @Test("loadInitialRules is a no-op when ruleLoadTask already exists")
    func loadInitialRulesNoOpWhenTaskExists() async {
        await RuleTestLock.shared.acquire()
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()
        coordinator.loadInitialRules()
        #expect(coordinator.ruleLoadTask != nil)
        #expect(!coordinator.rulesLoaded)

        // A second call while the first load is still in flight should reuse the existing task path.
        coordinator.loadInitialRules()
        #expect(coordinator.ruleLoadTask != nil)
        #expect(!coordinator.rulesLoaded)

        await coordinator.ruleLoadTask?.value
        #expect(coordinator.ruleLoadTask == nil)
        #expect(coordinator.rulesLoaded)

        await RuleEngine.shared.replaceAll(engineSnapshot)
        await RuleTestLock.shared.release()
    }

    @Test("startProxyOnLaunchIfNeeded starts when recordOnLaunch is enabled")
    func startProxyOnLaunchIfNeededStartsWhenEnabled() {
        let coordinator = MainContentCoordinator()
        var settings = AppSettings()
        settings.recordOnLaunch = true
        settings.automaticallySetSystemProxy = false
        var startCount = 0

        let didStart = coordinator.startProxyOnLaunchIfNeeded(settings: settings) {
            startCount += 1
        }

        #expect(didStart)
        #expect(startCount == 1)
    }

    @Test("startProxyOnLaunchIfNeeded skips when recordOnLaunch is disabled")
    func startProxyOnLaunchIfNeededSkipsWhenDisabled() {
        let coordinator = MainContentCoordinator()
        var settings = AppSettings()
        settings.recordOnLaunch = false
        var startCount = 0

        let didStart = coordinator.startProxyOnLaunchIfNeeded(settings: settings) {
            startCount += 1
        }

        #expect(!didStart)
        #expect(startCount == 0)
    }

    @Test("startProxyOnLaunchIfNeeded skips while proxy is running, starting, or stopping")
    func startProxyOnLaunchIfNeededSkipsWhenProxyActive() {
        var settings = AppSettings()
        settings.recordOnLaunch = true

        let runningCoordinator = MainContentCoordinator()
        runningCoordinator.isProxyRunning = true
        var runningStartCount = 0
        let didStartRunning = runningCoordinator.startProxyOnLaunchIfNeeded(settings: settings) {
            runningStartCount += 1
        }
        #expect(!didStartRunning)
        #expect(runningStartCount == 0)

        let startingCoordinator = MainContentCoordinator()
        startingCoordinator.isProxyStarting = true
        var startingStartCount = 0
        let didStartStarting = startingCoordinator.startProxyOnLaunchIfNeeded(settings: settings) {
            startingStartCount += 1
        }
        #expect(!didStartStarting)
        #expect(startingStartCount == 0)

        let stoppingCoordinator = MainContentCoordinator()
        stoppingCoordinator.isProxyStopping = true
        var stoppingStartCount = 0
        let didStartStopping = stoppingCoordinator.startProxyOnLaunchIfNeeded(settings: settings) {
            stoppingStartCount += 1
        }
        #expect(!didStartStopping)
        #expect(stoppingStartCount == 0)
    }
}
