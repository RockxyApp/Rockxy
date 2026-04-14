import Foundation
@testable import Rockxy
import Testing

@MainActor
struct CoordinatorStartupTests {
    @Test("ensureRulesLoaded sets rulesLoaded to true")
    func ensureRulesLoadedSetsFlag() async {
        let coordinator = MainContentCoordinator()
        #expect(!coordinator.rulesLoaded)

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)
    }

    @Test("ruleLoadTask persists after ensureRulesLoaded completes")
    func ruleLoadTaskPersistsAfterCompletion() async {
        let coordinator = MainContentCoordinator()
        #expect(coordinator.ruleLoadTask == nil)

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.ruleLoadTask != nil)
    }

    @Test("Calling ensureRulesLoaded twice completes without crash")
    func ensureRulesLoadedIdempotent() async {
        let coordinator = MainContentCoordinator()

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)

        // Second call re-awaits the completed task — instant return
        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)
        #expect(coordinator.ruleLoadTask != nil)
    }

    @Test("loadInitialRules stores ruleLoadTask without blocking")
    func loadInitialRulesStoresTask() {
        let coordinator = MainContentCoordinator()
        coordinator.loadInitialRules()

        #expect(coordinator.ruleLoadTask != nil)
        #expect(!coordinator.rulesLoaded)
    }

    @Test("loadInitialRules is a no-op when ruleLoadTask already exists")
    func loadInitialRulesNoOpWhenTaskExists() async {
        let coordinator = MainContentCoordinator()
        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)

        // ruleLoadTask is non-nil, so loadInitialRules guard returns immediately
        coordinator.loadInitialRules()
        #expect(coordinator.ruleLoadTask != nil)
        #expect(coordinator.rulesLoaded)
    }
}
