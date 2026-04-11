import Foundation
@testable import Rockxy
import Testing

/// Contract tests proving that `AllowListManager` participates in Swift Observation
/// for `isActive` and `rules`. This is the contract `CenterContentView` depends on
/// after the stable-reference observation fix: holding a `let manager = AllowListManager.shared`
/// and reading `manager.isActive` inside `body` must trigger SwiftUI re-rendering when
/// the property changes.
///
/// These tests do NOT prove that `CenterContentView` re-renders end-to-end (that would
/// require a SwiftUI view host or ViewInspector). They prove the manager observation
/// wiring is intact, which combined with a code review check on `CenterContentView`
/// covers the full fix.
@MainActor
struct AllowListObservationContractTests {
    // MARK: Internal

    @Test
    func managerParticipatesInIsActiveObservation() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }
        manager.setActive(false)

        var changeFired = false
        withObservationTracking {
            _ = manager.isActive
        } onChange: {
            changeFired = true
        }

        manager.setActive(true)
        #expect(changeFired)
    }

    @Test
    func managerParticipatesInRulesObservationOnAdd() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        var changeFired = false
        withObservationTracking {
            _ = manager.rules
        } onChange: {
            changeFired = true
        }

        manager.addRule(
            AllowListRule(
                name: "x",
                rawPattern: "*x.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        #expect(changeFired)
    }

    @Test
    func managerParticipatesInRulesObservationOnRemove() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        manager.addRule(
            AllowListRule(
                name: "x",
                rawPattern: "*x.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        let ruleID = manager.rules[0].id

        var changeFired = false
        withObservationTracking {
            _ = manager.rules
        } onChange: {
            changeFired = true
        }

        manager.removeRule(id: ruleID)
        #expect(changeFired)
    }

    @Test
    func managerParticipatesInRulesObservationOnReplaceAll() {
        let (manager, url) = makeManager()
        defer { cleanup(url) }

        var changeFired = false
        withObservationTracking {
            _ = manager.rules
        } onChange: {
            changeFired = true
        }

        manager.replaceAll([
            AllowListRule(
                name: "a",
                rawPattern: "*a.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            ),
        ])
        #expect(changeFired)
    }

    // MARK: Private

    private func makeManager() -> (AllowListManager, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        return (AllowListManager(storageURL: url), url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
