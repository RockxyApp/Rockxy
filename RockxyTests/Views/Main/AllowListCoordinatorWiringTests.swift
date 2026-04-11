import Foundation
@testable import Rockxy
import Testing

// MARK: - AllowListCoordinatorWiringTests

/// Regression tests for the real `MainContentCoordinator` Allow List entrypoints:
///
/// - `createAllowListRule(for:)` — request-list right-click quick-create
/// - `createAllowListRuleForDomain(_:)` — sidebar domain quick-create
/// - `filterBatchThroughAllowList(_:using:)` — the exact code path used by
///   `processBatch` to gate which transactions enter the session
///
/// ### How the quick-create coordinator tests are structured
///
/// Both `createAllowListRule(for:)` and `createAllowListRuleForDomain(_:)`:
///   1. build an `AllowListEditorContext` via `AllowListEditorContextBuilder`
///   2. write it to `AllowListEditorContextStore.shared` via `setPending(_:)`
///   3. post `.openAllowListWindow` on `NotificationCenter.default`
///
/// Rockxy's `RockxyTests` target uses `TEST_HOST = Rockxy Community.app`, so
/// tests run inside the live app process. That means the scene-hosted
/// `AllowListWindowView.onReceive(.openAllowListWindow)` handler is already
/// registered and synchronously calls `consumePendingContext()` as part of the
/// notification dispatch inside the coordinator method. After the method
/// returns, `pendingContext` is already `nil` — we cannot snapshot the stored
/// context from outside the method body.
///
/// To test the coordinator methods honestly, we split the assertions three
/// ways:
///
///   A. **Version witness** — `contextVersion` is a monotonic `UInt64` the
///      store increments inside every `setPending(_:)` call and does not
///      reset on `consumePending()`. After the coordinator method returns,
///      we assert `contextVersion` is `+1`, proving the real method
///      dispatched through `setPending` exactly once.
///   B. **Notification observer** — we register a `.openAllowListWindow`
///      observer and assert it fires after the coordinator posts.
///   C. **Transaction/domain-derived content** — lives in
///      `AllowListEditorContextBuilderTests`, which exercises
///      `AllowListEditorContextBuilder.fromTransaction(_:)` and `fromDomain(_:)`
///      directly and asserts host/method/pattern/name. The coordinator
///      methods forward to these builders unchanged, so builder-level
///      verification is equivalent to coordinator-level content verification.
///
/// The suite is marked `.serialized` so tests run one-at-a-time and cannot
/// step on each other's shared-store state.
@Suite(.serialized)
struct AllowListCoordinatorWiringTests {
    // MARK: - Request Quick-Create (real coordinator method)

    @Test
    @MainActor
    func createAllowListRuleDispatchesSetPendingAndPostsNotification() async {
        _ = AllowListEditorContextStore.shared.consumePending()
        let beforeVersion = AllowListEditorContextStore.shared.contextVersion

        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .openAllowListWindow,
            object: nil,
            queue: .main
        ) { _ in
            received = true
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            _ = AllowListEditorContextStore.shared.consumePending()
        }

        let coordinator = MainContentCoordinator()
        let transaction = TestFixtures.makeTransaction(
            method: "POST",
            url: "https://api.github.com/repos/owner/repo/issues"
        )
        coordinator.createAllowListRule(for: transaction)

        // Proves `setPending` was called exactly once through the store.
        let afterVersion = AllowListEditorContextStore.shared.contextVersion
        #expect(afterVersion == (beforeVersion &+ 1))

        // Proves `.openAllowListWindow` was posted.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(received)

        // Content of the built context (host, method, pattern, origin) is
        // covered by `AllowListEditorContextBuilderTests.fromTransactionPopulatesFromGetRequest`.
    }

    // MARK: - Sidebar Domain Quick-Create (real coordinator method)

    @Test
    @MainActor
    func createAllowListRuleForDomainDispatchesSetPendingAndPostsNotification() async {
        _ = AllowListEditorContextStore.shared.consumePending()
        let beforeVersion = AllowListEditorContextStore.shared.contextVersion

        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .openAllowListWindow,
            object: nil,
            queue: .main
        ) { _ in
            received = true
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            _ = AllowListEditorContextStore.shared.consumePending()
        }

        let coordinator = MainContentCoordinator()
        coordinator.createAllowListRuleForDomain("api.stripe.com")

        let afterVersion = AllowListEditorContextStore.shared.contextVersion
        #expect(afterVersion == (beforeVersion &+ 1))

        try? await Task.sleep(for: .milliseconds(100))
        #expect(received)

        // Content (host, pattern, method=nil) is covered by
        // `AllowListEditorContextBuilderTests.fromDomainProducesWildcardPatternWithAny`.
    }

    // MARK: - Allow List Batch Filter (processBatch code path)

    @Test
    @MainActor
    func filterBatchThroughAllowListInactivePassesEverything() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = AllowListManager(storageURL: url)
        // Rules exist but master toggle is off.
        manager.addRule(
            AllowListRule(
                name: "api",
                rawPattern: "*example.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        manager.setActive(false)

        let batch = [
            TestFixtures.makeTransaction(method: "GET", url: "https://example.com/a"),
            TestFixtures.makeTransaction(method: "GET", url: "https://other.com/b"),
            TestFixtures.makeTransaction(method: "POST", url: "https://third.com/c"),
        ]

        let filtered = MainContentCoordinator.filterBatchThroughAllowList(batch, using: manager)
        #expect(filtered.count == 3)
    }

    @Test
    @MainActor
    func filterBatchThroughAllowListActiveKeepsMatchingTransactions() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = AllowListManager(storageURL: url)
        manager.addRule(
            AllowListRule(
                name: "example",
                rawPattern: "*example.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        manager.setActive(true)

        let match = TestFixtures.makeTransaction(method: "GET", url: "https://example.com/a")
        let miss = TestFixtures.makeTransaction(method: "GET", url: "https://other.com/b")
        let batch = [match, miss]

        let filtered = MainContentCoordinator.filterBatchThroughAllowList(batch, using: manager)
        #expect(filtered.count == 1)
        #expect(filtered[0].id == match.id)
    }

    @Test
    @MainActor
    func filterBatchThroughAllowListRespectsMethodFilter() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = AllowListManager(storageURL: url)
        manager.addRule(
            AllowListRule(
                name: "example-post",
                rawPattern: "*example.com*",
                method: "POST",
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        manager.setActive(true)

        let postMatch = TestFixtures.makeTransaction(method: "POST", url: "https://example.com/a")
        let getMiss = TestFixtures.makeTransaction(method: "GET", url: "https://example.com/a")
        let otherMiss = TestFixtures.makeTransaction(method: "POST", url: "https://other.com/a")

        let filtered = MainContentCoordinator.filterBatchThroughAllowList(
            [postMatch, getMiss, otherMiss],
            using: manager
        )
        #expect(filtered.count == 1)
        #expect(filtered[0].id == postMatch.id)
    }

    @Test
    @MainActor
    func filterBatchThroughAllowListMixedMethodsAndURLs() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("allow-list-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = AllowListManager(storageURL: url)
        manager.addRule(
            AllowListRule(
                name: "github-any",
                rawPattern: "*github.com*",
                method: nil,
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        manager.addRule(
            AllowListRule(
                name: "stripe-post",
                rawPattern: "*stripe.com*",
                method: "POST",
                matchType: .wildcard,
                includeSubpaths: true
            )
        )
        manager.setActive(true)

        let githubGet = TestFixtures.makeTransaction(method: "GET", url: "https://api.github.com/user")
        let githubPost = TestFixtures.makeTransaction(method: "POST", url: "https://api.github.com/user")
        let stripePost = TestFixtures.makeTransaction(method: "POST", url: "https://api.stripe.com/charges")
        let stripeGet = TestFixtures.makeTransaction(method: "GET", url: "https://api.stripe.com/charges")
        let otherGet = TestFixtures.makeTransaction(method: "GET", url: "https://unmatched.com/")

        let filtered = MainContentCoordinator.filterBatchThroughAllowList(
            [githubGet, githubPost, stripePost, stripeGet, otherGet],
            using: manager
        )
        let filteredIDs = Set(filtered.map(\.id))
        #expect(filteredIDs == Set([githubGet.id, githubPost.id, stripePost.id]))
    }
}
