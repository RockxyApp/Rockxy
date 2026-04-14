import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct CoordinatorStartupTests {
    @Test("ensureRulesLoaded sets rulesLoaded to true")
    func ensureRulesLoadedSetsFlag() async {
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()
        #expect(!coordinator.rulesLoaded)

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)

        await RuleEngine.shared.replaceAll(engineSnapshot)
    }

    @Test("ruleLoadTask persists after ensureRulesLoaded completes")
    func ruleLoadTaskPersistsAfterCompletion() async {
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()
        #expect(coordinator.ruleLoadTask == nil)

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.ruleLoadTask != nil)

        await RuleEngine.shared.replaceAll(engineSnapshot)
    }

    @Test("Calling ensureRulesLoaded twice completes without crash")
    func ensureRulesLoadedIdempotent() async {
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)

        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)
        #expect(coordinator.ruleLoadTask != nil)

        await RuleEngine.shared.replaceAll(engineSnapshot)
    }

    @Test("loadInitialRules stores ruleLoadTask without blocking")
    func loadInitialRulesStoresTask() async {
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()
        coordinator.loadInitialRules()

        #expect(coordinator.ruleLoadTask != nil)
        #expect(!coordinator.rulesLoaded)

        // Await completion so the background Task doesn't contend with later tests
        await coordinator.ruleLoadTask?.value
        await RuleEngine.shared.replaceAll(engineSnapshot)
    }

    @Test("loadInitialRules is a no-op when ruleLoadTask already exists")
    func loadInitialRulesNoOpWhenTaskExists() async {
        let engineSnapshot = await RuleEngine.shared.allRules
        let coordinator = MainContentCoordinator()
        await coordinator.ensureRulesLoaded()
        #expect(coordinator.rulesLoaded)

        coordinator.loadInitialRules()
        #expect(coordinator.ruleLoadTask != nil)
        #expect(coordinator.rulesLoaded)

        await RuleEngine.shared.replaceAll(engineSnapshot)
    }
}
