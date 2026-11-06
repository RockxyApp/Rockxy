import Foundation
@testable import Rockxy
import Testing

// Three sheets used to derive their contents by scanning the capture on every render: the Add
// Favorite Apps list once per keystroke and once per captured request, and the Focus Set editor's
// match preview twice per render. Worse than the cost, Add Favorite scanned `transactions`
// directly while the Domains list beside it read the maintained domain tree -- and the app index
// drops rows outside an active sidebar app scope, so the two halves of one sheet were derived
// under different scope rules. These tests hold the maintained-index reads that replaced both.

// MARK: - FocusSheetDerivationTests

@MainActor
struct FocusSheetDerivationTests {
    // MARK: Internal

    @Test("Add Favorite derives its Apps list from the same index the sidebar shows")
    func addFavoriteAppsListMatchesTheSidebar() {
        let coordinator = Self.makeCoordinator()

        // What the sheet now reads, and what the sidebar's Apps section reads.
        #expect(coordinator.appNodes.map(\.name).sorted() == ["Google Chrome", "Safari"])
        #expect(Self.sheetApps(in: coordinator) == ["Google Chrome", "Safari"])
    }

    @Test("Under an active sidebar app scope the sheet shows exactly what the sidebar shows")
    func scopedSheetMatchesTheSidebar() {
        let coordinator = Self.makeCoordinator()
        coordinator.filterCriteria.sidebarApp = "Safari"
        coordinator.rebuildSidebarIndexes(for: coordinator.activeWorkspace)

        // The app index drops rows outside the scope, so the Apps list narrows to the scoped
        // app. Scanning `transactions` here instead still listed Google Chrome, disagreeing
        // with the sidebar's own Apps section.
        #expect(Self.sheetApps(in: coordinator) == ["Safari"])
        #expect(Self.sheetApps(in: coordinator) == coordinator.appNodes.map(\.name).sorted())

        // The domain index is narrowed only by `sidebarDomain`, so on its own it would still offer
        // example.org, a registrable domain Safari never contacted. The sheet applies one rule to
        // both lists -- inside the active sidebar scope -- so that domain is gone. (Candidates are
        // registrable domains, the roots of the domain tree; see `AddFavoriteView.filteredDomains`.)
        // Hosts sit among a registrable-domain root's children, not at the top level.
        #expect(coordinator.domainTree.flatMap(\.children).map(\.domain).contains("telemetry.example.com"))
        #expect(coordinator.domainTree.map(\.domain).contains("example.org"))
        #expect(!Self.sheetDomains(in: coordinator).contains("example.org"))
        #expect(Self.sheetDomains(in: coordinator) == ["example.com"])
    }

    @Test("A domain scope narrows the Apps list to the apps that contacted that domain")
    func domainScopeNarrowsApps() {
        let coordinator = Self.makeCoordinator()
        coordinator.filterCriteria.sidebarDomain = "tracker.example.org"
        coordinator.rebuildSidebarIndexes(for: coordinator.activeWorkspace)

        // The app index is not narrowed by `sidebarDomain` on its own.
        #expect(coordinator.appNodes.map(\.name).sorted() == ["Google Chrome", "Safari"])
        #expect(Self.sheetApps(in: coordinator) == ["Google Chrome"])
        #expect(Self.sheetDomains(in: coordinator) == ["example.org"])
    }

    @Test("With no sidebar scope both lists are complete and no scope is named")
    func unscopedSheetIsComplete() {
        let coordinator = Self.makeCoordinator()
        let scope = Self.scope(in: coordinator)

        #expect(scope.activeScopeLabel == nil)
        #expect(Self.sheetApps(in: coordinator) == ["Google Chrome", "Safari"])
        #expect(Self.sheetDomains(in: coordinator) == ["example.com", "example.org"])
    }

    @Test("Both scope kinds together apply both, and the active scope is named")
    func combinedScopeAppliesBoth() {
        let apps = [
            AppInfo(name: "Safari", domains: ["api.example.com", "cdn.example.com"], requestCount: 2),
            AppInfo(name: "Google Chrome", domains: ["api.example.com"], requestCount: 1)
        ]
        let domains = ["api.example.com", "cdn.example.com", "other.test"].map {
            DomainNode(id: $0, domain: $0, requestCount: 1, children: [])
        }
        let scope = FavoriteCandidateScope(
            apps: apps,
            domains: domains,
            sidebarApp: "Safari",
            sidebarDomain: "cdn.example.com"
        )

        #expect(scope.apps.map(\.name) == ["Safari"])
        #expect(scope.domains.map(\.domain) == ["cdn.example.com"])
        #expect(scope.activeScopeLabel == "Safari, cdn.example.com")
    }

    @Test("A request with no client app is grouped under the same label the sheet shows")
    func unattributedRequestsKeepTheirLabel() {
        let coordinator = Self.makeCoordinator()
        let unattributed = TestFixtures.makeTransaction(url: "https://cdn.example.com/asset.js")
        coordinator.transactions.append(unattributed)
        coordinator.rebuildSidebarIndexes(for: coordinator.activeWorkspace)

        // The sheet used to substitute this label itself while scanning; the index does it now,
        // so a nil `clientApp` must not fall out of the list entirely.
        let unknown = String(localized: "Unknown", bundle: RockxyLocalization.bundle)
        #expect(Self.sheetApps(in: coordinator).contains(unknown))
    }

    @Test("The Focus Set editor's match preview counts what the predicate counts")
    func matchPreviewAgreesWithThePredicate() {
        let coordinator = Self.makeCoordinator()
        let draft = FocusSet(name: "Safari", appName: "Safari")

        // The sheet now settles `matchCount` into state behind a debounce instead of computing
        // it twice per render; it has to settle on exactly this number.
        let settled = coordinator.transactions.count { !$0.isTLSFailure && draft.matches($0) }

        #expect(settled == 2)
        #expect(coordinator.transactions.count { draft.matches($0) } == settled)
    }

    @Test("The match preview is debounced into state rather than computed while rendering")
    func matchPreviewIsDebouncedIntoState() throws {
        let source = try readProjectFile("Rockxy/Views/Sidebar/FocusSetEditorSheet.swift")

        // Two full predicate passes per keystroke was the defect: `matchSummary` read the
        // computed property and the action bar's tint read it again.
        #expect(!source.contains("private var matchCount: Int {"))
        #expect(source.contains("@State private var matchCount = 0"))
        #expect(source.contains("task(id: draft)"))
        #expect(source.contains("Task.sleep(for: Self.matchCountDebounce)"))
    }

    @Test("Both sheets aggregate their suggestions once, not on every re-initialisation")
    func suggestionsAreAggregatedOnce() throws {
        let focus = try readProjectFile("Rockxy/Views/Sidebar/FocusSetEditorSheet.swift")
        let noise = try readProjectFile("Rockxy/Views/Sidebar/NoiseControlManagerSheet.swift")

        // The presenting closure reads the live transaction list, so each sheet is
        // re-initialised on every captured request while it is open. Three scans and a sort in
        // `init` meant paying for all of them again each time.
        for source in [focus, noise] {
            // The aggregation moved out of stored-in-init into view state filled by `.task`.
            #expect(source.contains("@State private var suggestions = FocusSetEditorSuggestions()"))
            #expect(!source.contains("private let suggestions: FocusSetEditorSuggestions"))
            #expect(source.contains(".task {"))
        }
        #expect(focus.contains("suggestions = FocusSetEditorSuggestions(transactions: transactions)"))
        #expect(noise.contains("suggestions = FocusSetEditorSuggestions(transactions: coordinator.transactions)"))
    }

    @Test("Add Favorite no longer scans the capture to build its Apps list")
    func addFavoriteReadsTheMaintainedIndex() throws {
        let source = try readProjectFile("Rockxy/Views/Sidebar/AddFavoriteView.swift")

        #expect(source.contains("scope.apps.map { AppCandidate(name: $0.name) }"))
        #expect(source.contains("apps: coordinator.appNodes"))
        #expect(source.contains("domains: coordinator.domainTree"))
        #expect(!source.contains("for transaction in coordinator.transactions"))
    }

    @Test("The bypass and HTTPS decryption lists surface a failed save inline, with a retry")
    func persistenceFailureIsShownInline() throws {
        let bypass = try readProjectFile("Rockxy/Views/Settings/BypassProxyListView.swift")
        let ssl = try readProjectFile("Rockxy/Views/Settings/SSLProxyingListView.swift")
        let banner = try readProjectFile("Rockxy/Views/Common/PersistenceFailureBanner.swift")

        #expect(bypass.contains("manager.persistenceFailure"))
        #expect(bypass.contains("retry: { manager.save() }"))
        #expect(ssl.contains("viewModel.manager.persistenceFailure"))
        #expect(ssl.contains("retry: { viewModel.manager.save() }"))
        #expect(banner.contains("AccessibilityNotification.Announcement"))
        // Compared whitespace-stripped: the formatter rewraps call sites. What this guarantees is
        // that the banner's one button runs the caller's retry under `actionTitle`, and that the
        // default title is localized through Rockxy's own bundle, not a bare literal.
        let flatBanner = banner.filter { !$0.isWhitespace }
        #expect(flatBanner.contains("Button(actionTitle,action:retry)"))
        #expect(flatBanner.contains(
            "actionTitle??String(localized:\"TrySavingAgain\",bundle:RockxyLocalization.bundle)"
        ))
        #expect(!banner.contains(".alert("))
    }

    // MARK: Private

    /// Two apps, one of which reaches a domain the other does not, so a scope that drops rows
    /// shows up as a difference rather than as the same list twice.
    private static func makeCoordinator() -> MainContentCoordinator {
        let coordinator = MainContentCoordinator()
        let safariAPI = TestFixtures.makeTransaction(url: "https://api.example.com/orders")
        safariAPI.clientApp = "Safari"
        let safariAuth = TestFixtures.makeTransaction(url: "https://api.example.com/login")
        safariAuth.clientApp = "Safari"
        let chrome = TestFixtures.makeTransaction(url: "https://telemetry.example.com/events")
        chrome.clientApp = "Google Chrome"
        let chromeTracker = TestFixtures.makeTransaction(url: "https://tracker.example.org/beacon")
        chromeTracker.clientApp = "Google Chrome"
        coordinator.transactions = [safariAPI, safariAuth, chrome, chromeTracker]
        coordinator.rebuildSidebarIndexes(for: coordinator.activeWorkspace)
        return coordinator
    }

    /// The same inputs `AddFavoriteView.scope` passes in.
    private static func scope(in coordinator: MainContentCoordinator) -> FavoriteCandidateScope {
        FavoriteCandidateScope(
            apps: coordinator.appNodes,
            domains: coordinator.domainTree,
            sidebarApp: coordinator.filterCriteria.sidebarApp,
            sidebarDomain: coordinator.filterCriteria.sidebarDomain
        )
    }

    /// Mirrors `AddFavoriteView.filteredApps` with no search text.
    private static func sheetApps(in coordinator: MainContentCoordinator) -> [String] {
        scope(in: coordinator).apps.map(\.name).sorted()
    }

    /// Mirrors `AddFavoriteView.filteredDomains` with no search text.
    private static func sheetDomains(in coordinator: MainContentCoordinator) -> [String] {
        scope(in: coordinator).domains.map(\.domain).sorted()
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
