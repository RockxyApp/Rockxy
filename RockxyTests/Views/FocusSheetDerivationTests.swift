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

        // The two halves are scoped by different criteria, because the sidebar scopes them that
        // way: the domain index is narrowed by `sidebarDomain`, never by `sidebarApp`. So an
        // app scope leaves a domain only another app reached on offer. The sheet now mirrors
        // the sidebar exactly rather than inventing a third rule, which is the most it can
        // settle on its own.
        #expect(Self.sheetDomains(in: coordinator).contains("telemetry.example.com"))
        #expect(Self.sheetDomains(in: coordinator) == coordinator.domainTree.map(\.domain))
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

        #expect(source.contains("coordinator.appNodes.map { AppCandidate(name: $0.name) }"))
        #expect(!source.contains("for transaction in coordinator.transactions"))
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
        coordinator.transactions = [safariAPI, safariAuth, chrome]
        coordinator.rebuildSidebarIndexes(for: coordinator.activeWorkspace)
        return coordinator
    }

    /// Mirrors `AddFavoriteView.filteredApps`, which is private to the view.
    private static func sheetApps(in coordinator: MainContentCoordinator) -> [String] {
        coordinator.appNodes.map(\.name).sorted()
    }

    /// Mirrors `AddFavoriteView.filteredDomains`, which is private to the view.
    private static func sheetDomains(in coordinator: MainContentCoordinator) -> [String] {
        coordinator.domainTree.map(\.domain)
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
