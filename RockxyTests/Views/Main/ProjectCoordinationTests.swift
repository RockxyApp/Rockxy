import AppKit
import Foundation
@testable import Rockxy
import Testing

// Non-visual orchestration tests for `MainContentCoordinator+Projects`: startup
// hydration, Project switching/creation/deletion, Observation-driven debounced
// autosave, and snapshot exclusion. All persistence goes through an in-memory
// fake repository; no Application Support I/O and no sleeps beyond a few hundred ms.

// MARK: - ProjectCoordinationTests

@MainActor
@Suite("ProjectCoordination")
struct ProjectCoordinationTests {
    // MARK: Internal

    // MARK: Startup hydration

    @Test("successful hydration applies the active project's tabs and traffic")
    func successfulInitialHydration() async {
        let defaultTab = ProjectTabSnapshot.makeDefaultAllTraffic()
        let apiTab = ProjectTabSnapshot(
            title: "APIs",
            isClosable: true,
            filter: FilterCriteriaSnapshot(domains: ["api.example.com"])
        )
        let project = Project(
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: defaultTab.id,
            tabs: [defaultTab, apiTab]
        )
        let repo = FakeProjectRepo(loadResult: .success(
            ProjectCatalog(activeProjectID: project.id, projects: [project])
        ))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        let api = TestFixtures.makeTransaction(url: "https://api.example.com/x")
        let other = TestFixtures.makeTransaction(url: "https://other.example.com/y")
        coordinator.transactions = [api, other]

        await coordinator.hydrateProjectsOnLaunch()

        #expect(coordinator.hasHydratedProjects)
        #expect(coordinator.isObservingProjectTabs)
        #expect(coordinator.workspaceStore.workspaces.count == 2)
        let allTraffic = coordinator.workspaceStore.activeWorkspace
        #expect(allTraffic.filteredTransactions.count == 2)
        let apiWorkspace = coordinator.workspaceStore.workspaces.first { $0.title == "APIs" }
        #expect(apiWorkspace?.filteredTransactions.map(\.id) == [api.id])
        #expect(allTraffic.sidebarSelection == .allApps)
    }

    @Test("launch starts at Apps even when Insights was saved as the active view")
    func startupUsesAppsAfterSavedInsights() async {
        let savedTab = ProjectTabSnapshot(
            title: "All Traffic",
            isClosable: false,
            mainTabRawValue: MainTab.insights.rawValue
        )
        let project = Project(
            name: "Alpha",
            createdAt: Self.fixedDate,
            updatedAt: Self.fixedDate,
            activeTabID: savedTab.id,
            tabs: [savedTab]
        )
        let repository = FakeProjectRepo(loadResult: .success(
            ProjectCatalog(activeProjectID: project.id, projects: [project])
        ))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repository)

        await coordinator.hydrateProjectsOnLaunch()

        #expect(coordinator.activeMainTab == .traffic)
        #expect(coordinator.sidebarSelection == .allApps)
    }

    @Test("a failed load leaves current workspaces unchanged and blocks autosave")
    func failedLoadLeavesWorkspacesUnchanged() async {
        let repo = FakeProjectRepo(loadResult: .failure(FakeError.boom))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        let beforeIDs = coordinator.workspaceStore.workspaces.map(\.id)

        await coordinator.hydrateProjectsOnLaunch()

        #expect(!coordinator.hasHydratedProjects)
        #expect(!coordinator.isObservingProjectTabs)
        #expect(coordinator.projectStore.loadState == .failed(String(describing: FakeError.boom)))
        #expect(coordinator.workspaceStore.workspaces.map(\.id) == beforeIDs)
        // The store is not mutable, so an explicit flush must refuse and write nothing.
        #expect(!coordinator.flushProjectTabSnapshot())
        coordinator.scheduleProjectTabAutosave()
        try? await Task.sleep(for: .milliseconds(120))
        #expect(await repo.saveCount == 0)
    }

    @Test("Babylon intake hydrates before assigning Project ownership")
    func babylonIntakeHydratesBeforeOwnership() async {
        let (catalog, alpha, _) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        let provisionalProjectID = coordinator.projectStore.activeProjectID
        let transaction = TestFixtures.makeTransaction(url: "https://babylon.example.com/pre-hydration")

        await coordinator.receiveBabylonTransaction(transaction)

        #expect(provisionalProjectID != alpha.id)
        #expect(coordinator.hasHydratedProjects)
        #expect(transaction.captureContext?.projectID == alpha.id)
        #expect(await coordinator.sessionManager.flushPendingUpdates().map(\.id) == [transaction.id])
    }

    @Test("Babylon workspace registration hydrates before replacing tabs")
    func babylonWorkspaceHydratesBeforeRegistration() async {
        let (catalog, alpha, _) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        let identity = BabylonCaptureIdentity(
            clientID: UUID().uuidString,
            sessionID: UUID().uuidString,
            projectName: "Checkout",
            bundleIdentifier: "com.example.checkout",
            deviceName: "Test iPhone",
            deviceModel: "iPhone"
        )

        await coordinator.registerBabylonCapture(identity: identity)

        #expect(coordinator.hasHydratedProjects)
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == alpha.tabs[0].title })
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == identity.displayName })
    }

    @Test("external intake fails closed when the Project catalog cannot load")
    func externalIntakeFailsClosedOnCatalogFailure() async {
        let repo = FakeProjectRepo(loadResult: .failure(FakeError.boom))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        let transaction = TestFixtures.makeTransaction(url: "https://babylon.example.com/rejected")

        await coordinator.receiveBabylonTransaction(transaction)
        await coordinator.receiveBabylonTransaction(
            TestFixtures.makeTransaction(url: "https://babylon.example.com/still-rejected")
        )

        #expect(transaction.captureContext == nil)
        #expect(await coordinator.sessionManager.flushPendingUpdates().isEmpty)
        #expect(!coordinator.hasHydratedProjects)
        #expect(await repo.loadCount == 1)
    }

    // MARK: Switching

    @Test("switching persists outgoing tabs and restores each project's traffic")
    func projectSwitchPersistsOutgoingHydratesIncoming() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let repo = FakeProjectRepo(loadResult: .success(catalog))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        let t1 = TestFixtures.makeTransaction(url: "https://api.example.com/x")
        let t2 = TestFixtures.makeTransaction(url: "https://other.example.com/y")
        coordinator.transactions = [t1, t2]
        await coordinator.hydrateProjectsOnLaunch()

        // An outgoing edit that must be captured before the switch.
        coordinator.workspaceStore.createWorkspace(title: "Scratch")

        #expect(coordinator.switchToProject(id: beta.id))

        #expect(coordinator.projectStore.activeProjectID == beta.id)
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == "BetaTab" })
        // Outgoing Alpha durably captured the scratch tab.
        let persistedAlpha = coordinator.projectStore.projects.first { $0.id == alpha.id }
        #expect(persistedAlpha?.tabs.contains { $0.title == "Scratch" } == true)
        // Beta starts with independent traffic history.
        #expect(coordinator.transactions.isEmpty)
        #expect(coordinator.workspaceStore.activeWorkspace.filteredTransactions.isEmpty)

        let betaTraffic = TestFixtures.makeTransaction(url: "https://beta.example.com/new")
        coordinator.processActiveProjectTestBatch([betaTraffic])
        #expect(coordinator.transactions.map(\.id) == [betaTraffic.id])

        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.transactions.map(\.id) == [t1.id, t2.id])
        #expect(coordinator.workspaceStore.activeWorkspace.filteredTransactions.count == 2)
    }

    @Test("a request completing after a switch stays with its request-start project")
    func lateCompletionRoutesToOriginalProject() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let alphaRoute = coordinator.activeCaptureContext
        let lateAlpha = TestFixtures.makeTransaction(url: "https://alpha.example.com/late")
        lateAlpha.assignCaptureContextIfMissing(alphaRoute)

        #expect(coordinator.switchToProject(id: beta.id))
        coordinator.processBatch([lateAlpha], generation: coordinator.sessionGeneration)

        #expect(coordinator.transactions.isEmpty)
        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.transactions.map(\.id) == [lateAlpha.id])
    }

    @Test("clearing one project preserves another project and its late completions")
    func clearIsScopedToActiveProject() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let alphaRoute = coordinator.activeCaptureContext
        let alphaTraffic = TestFixtures.makeTransaction(url: "https://alpha.example.com/first")
        coordinator.processActiveProjectTestBatch([alphaTraffic])

        #expect(coordinator.switchToProject(id: beta.id))
        let betaTraffic = TestFixtures.makeTransaction(url: "https://beta.example.com/first")
        coordinator.processActiveProjectTestBatch([betaTraffic])
        await coordinator.clearSession()
        #expect(coordinator.transactions.isEmpty)

        let lateAlpha = TestFixtures.makeTransaction(url: "https://alpha.example.com/late")
        lateAlpha.assignCaptureContextIfMissing(alphaRoute)
        coordinator.processBatch([lateAlpha], generation: coordinator.sessionGeneration)

        #expect(coordinator.transactions.isEmpty)
        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.transactions.map(\.id) == [alphaTraffic.id, lateAlpha.id])
    }

    @Test("clearing another Project preserves a live stream's terminal snapshot")
    func clearPreservesInactiveLiveStream() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        await coordinator.configureSessionDeliveryCallbacks()
        #expect(coordinator.switchToProject(id: beta.id))
        let row = TestFixtures.makeTransaction(state: .active)
        row.assignCaptureContextIfMissing(coordinator.activeCaptureContext)
        await coordinator.sessionManager.addTransaction(row)
        let opening = await coordinator.sessionManager.flushPendingUpdates()
        coordinator.processBatch(opening, generation: coordinator.sessionGeneration)
        #expect(coordinator.filteredRows.first?.state == .active)
        #expect(coordinator.switchToProject(id: alpha.id))
        await coordinator.clearSession()
        #expect(coordinator.switchToProject(id: beta.id))
        row.state = .failed
        await coordinator.sessionManager.addTransaction(row, acceptsNewRows: false)
        _ = await coordinator.sessionManager.flushPendingUpdates()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while coordinator.filteredRows.first?.state != .failed, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(coordinator.transactions.map(\.id) == [row.id])
        #expect(coordinator.filteredRows.first?.state == .failed)
    }

    @Test("clearing one project preserves completed traffic pending for another project")
    func clearPreservesInactivePendingBatch() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let alphaRoute = coordinator.activeCaptureContext
        #expect(coordinator.switchToProject(id: beta.id))

        let pendingAlpha = TestFixtures.makeTransaction(url: "https://alpha.example.com/pending")
        pendingAlpha.assignCaptureContextIfMissing(alphaRoute)
        await coordinator.sessionManager.addTransaction(pendingAlpha)

        await coordinator.clearSession()

        #expect(coordinator.transactions.isEmpty)
        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.transactions.map(\.id) == [pendingAlpha.id])
    }

    @Test("project transitions are serialized while a capture clear crosses actors")
    func clearBlocksProjectTransitionDuringSuspension() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let alphaTraffic = TestFixtures.makeTransaction(url: "https://alpha.example.com/keep")
        coordinator.processActiveProjectTestBatch([alphaTraffic])
        #expect(coordinator.switchToProject(id: beta.id))
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://beta.example.com/clear"),
        ])

        await coordinator.sessionManager.setOnBeginNewSession { _ in
            await MainActor.run {
                _ = coordinator.switchToProject(id: alpha.id)
            }
        }
        await coordinator.clearSession()

        #expect(coordinator.projectStore.activeProjectID == beta.id)
        #expect(coordinator.transactions.isEmpty)
        #expect(coordinator.lastProjectOperationError == .captureClearInProgress)
        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.transactions.map(\.id) == [alphaTraffic.id])
    }

    @Test("clear retains an already-flushed old-generation batch for an inactive project")
    func clearPreservesAlreadyFlushedInactiveBatch() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let alphaRoute = coordinator.activeCaptureContext
        #expect(coordinator.switchToProject(id: beta.id))
        let flushedAlpha = TestFixtures.makeTransaction(url: "https://alpha.example.com/flushed")
        flushedAlpha.assignCaptureContextIfMissing(alphaRoute)

        await coordinator.sessionManager.setOnBeginNewSession { generation in
            await MainActor.run {
                coordinator.processBatch([flushedAlpha], generation: generation &- 1)
            }
        }
        await coordinator.clearSession()

        #expect(coordinator.transactions.isEmpty)
        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.transactions.map(\.id) == [flushedAlpha.id])
    }

    @Test("Babylon intake stamps project ownership before shared batching")
    func babylonIntakeUsesArrivalProject() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let babylon = TestFixtures.makeTransaction(url: "https://babylon.example.com/intake")

        await coordinator.receiveBabylonTransaction(babylon)
        #expect(babylon.captureContext?.projectID == alpha.id)
        let pending = await coordinator.sessionManager.flushPendingUpdates()
        #expect(coordinator.switchToProject(id: beta.id))
        coordinator.processBatch(pending, generation: coordinator.sessionGeneration)

        #expect(coordinator.transactions.isEmpty)
        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.transactions.map(\.id) == [babylon.id])
    }

    @Test("batch routing fails closed when ownership is missing")
    func unownedBatchIsDropped() async {
        let coordinator = MainContentCoordinator(projectCatalogRepository: FakeProjectRepo())
        await coordinator.hydrateProjectsOnLaunch()
        let unowned = TestFixtures.makeTransaction(url: "https://unowned.example.com")

        coordinator.processBatch([unowned], generation: coordinator.sessionGeneration)

        #expect(coordinator.transactions.isEmpty)
    }

    @Test("batch routing fails closed when session identity does not match its Project")
    func mismatchedSessionIdentityIsDropped() async {
        let coordinator = MainContentCoordinator(projectCatalogRepository: FakeProjectRepo())
        await coordinator.hydrateProjectsOnLaunch()
        let transaction = TestFixtures.makeTransaction(url: "https://mismatch.example.com")
        transaction.assignCaptureContextIfMissing(TrafficCaptureContext(
            projectID: coordinator.projectStore.activeProjectID,
            sessionID: UUID(),
            generation: 0
        ))

        coordinator.processBatch([transaction], generation: coordinator.sessionGeneration)

        #expect(coordinator.transactions.isEmpty)
    }

    @Test("logs retain delivery-time Project ownership across a switch")
    func logsRouteToDeliveryProject() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let alphaTransaction = TestFixtures.makeTransaction(url: "https://alpha.example.com/log")
        coordinator.processActiveProjectTestBatch([alphaTransaction])
        let alphaContext = coordinator.activeCaptureContext
        let log = TestFixtures.makeLogEntry(message: "Alpha request finished")

        #expect(coordinator.switchToProject(id: beta.id))
        coordinator.addLogEntry(log, captureContext: alphaContext)

        #expect(coordinator.logEntries.isEmpty)
        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.logEntries.map(\.id) == [log.id])
        #expect(coordinator.logEntries.first?.correlatedTransactionId == alphaTransaction.id)
    }

    @Test("project switching advances live sequence numbers beyond persisted favorites")
    func projectSwitchAccountsForFavoriteSequences() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let favorite = TestFixtures.makeTransaction(url: "https://favorite.example.com")
        favorite.sequenceNumber = 100
        coordinator.persistedFavorites = [favorite]

        #expect(coordinator.switchToProject(id: beta.id))
        #expect(coordinator.switchToProject(id: alpha.id))
        let fresh = TestFixtures.makeTransaction(url: "https://alpha.example.com/fresh")
        coordinator.processActiveProjectTestBatch([fresh])

        #expect(fresh.sequenceNumber == 101)
    }

    @Test("live traffic history is capped independently for every bounded Project")
    func perProjectHistoryIsBounded() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            policy: TinyProjectHistoryPolicy(),
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()

        let alphaTraffic = (0 ..< 4).map {
            TestFixtures.makeTransaction(url: "https://alpha.example.com/\($0)")
        }
        coordinator.processActiveProjectTestBatch(alphaTraffic)
        #expect(coordinator.transactions.map(\.id) == Array(alphaTraffic.suffix(2)).map(\.id))

        #expect(coordinator.switchToProject(id: beta.id))
        let betaTraffic = (0 ..< 4).map {
            TestFixtures.makeTransaction(url: "https://beta.example.com/\($0)")
        }
        coordinator.processActiveProjectTestBatch(betaTraffic)
        #expect(coordinator.transactions.map(\.id) == Array(betaTraffic.suffix(2)).map(\.id))

        #expect(coordinator.switchToProject(id: alpha.id))
        #expect(coordinator.transactions.map(\.id) == Array(alphaTraffic.suffix(2)).map(\.id))
    }

    @Test("multiple tabs are views over one project traffic history")
    func tabsShareProjectTraffic() async {
        let coordinator = MainContentCoordinator(projectCatalogRepository: FakeProjectRepo())
        await coordinator.hydrateProjectsOnLaunch()
        coordinator.workspaceStore.createWorkspace(title: "Errors")
        let traffic = TestFixtures.makeTransaction(url: "https://api.example.com/one")

        coordinator.processActiveProjectTestBatch([traffic])

        #expect(coordinator.workspaceStore.workspaces.count == 2)
        #expect(coordinator.workspaceStore.workspaces.allSatisfy {
            $0.filteredTransactions.map(\.id) == [traffic.id]
        })
    }

    @Test("switching to an unknown project leaves state unchanged")
    func invalidTargetLeavesStateUnchanged() async {
        let (catalog, _, _) = Self.twoProjectCatalog()
        let repo = FakeProjectRepo(loadResult: .success(catalog))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        await coordinator.hydrateProjectsOnLaunch()
        let activeBefore = coordinator.projectStore.activeProjectID
        let tabsBefore = coordinator.workspaceStore.workspaces.map(\.id)
        let savesBefore = await repo.saveCount

        #expect(!coordinator.switchToProject(id: UUID()))

        #expect(coordinator.lastProjectOperationError == .projectNotFound)
        #expect(coordinator.projectStore.activeProjectID == activeBefore)
        #expect(coordinator.workspaceStore.workspaces.map(\.id) == tabsBefore)
        #expect(await repo.saveCount == savesBefore)
    }

    // MARK: Create / delete

    @Test("creating a project persists the outgoing snapshot and applies the new default tabs")
    func createActiveTransition() async {
        let (catalog, alpha, _) = Self.twoProjectCatalog()
        let repo = FakeProjectRepo(loadResult: .success(catalog))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        await coordinator.hydrateProjectsOnLaunch()
        coordinator.workspaceStore.createWorkspace(title: "Scratch")

        let created = coordinator.createProject(named: "Gamma")

        #expect(created != nil)
        #expect(coordinator.projectStore.activeProjectID == created?.id)
        // The new project shows only its single default tab.
        #expect(coordinator.workspaceStore.workspaces.count == 1)
        #expect(coordinator.workspaceStore.workspaces[0].isClosable == false)
        // Outgoing Alpha kept the scratch tab.
        let persistedAlpha = coordinator.projectStore.projects.first { $0.id == alpha.id }
        #expect(persistedAlpha?.tabs.contains { $0.title == "Scratch" } == true)
    }

    @Test("deleting the active project applies the adjacent project")
    func deleteActiveTransition() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let repo = FakeProjectRepo(loadResult: .success(catalog))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        await coordinator.hydrateProjectsOnLaunch()

        #expect(coordinator.deleteProject(id: alpha.id))

        #expect(coordinator.projectStore.activeProjectID == beta.id)
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == "BetaTab" })
    }

    @Test("deleting an inactive project does not disturb the current tabs")
    func inactiveDeleteStability() async {
        let (catalog, _, beta) = Self.twoProjectCatalog()
        let repo = FakeProjectRepo(loadResult: .success(catalog))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        await coordinator.hydrateProjectsOnLaunch()
        coordinator.workspaceStore.createWorkspace(title: "Scratch")
        let activeWorkspaceBefore = coordinator.workspaceStore.activeWorkspaceID
        let tabIDsBefore = coordinator.workspaceStore.workspaces.map(\.id)

        #expect(coordinator.deleteProject(id: beta.id))

        #expect(coordinator.workspaceStore.activeWorkspaceID == activeWorkspaceBefore)
        #expect(coordinator.workspaceStore.workspaces.map(\.id) == tabIDsBefore)
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == "Scratch" })
    }

    // MARK: Reconciliation

    @Test("reconciliation rejects a stale candidate after an unsaved tab flush and preserves local state")
    func reconcileStaleAfterFlushRejected() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let staleRevision = coordinator.projectStore.catalog.revision
        // A live, unsaved tab edit. The pre-apply flush persists it, advancing the
        // revision so the candidate built against `staleRevision` is now stale.
        coordinator.workspaceStore.createWorkspace(title: "Unsaved")
        let workspaceIDsBefore = coordinator.workspaceStore.workspaces.map(\.id)

        let candidate = [alpha, beta, Self.makeProject(name: "Reconciled")]
        #expect(!coordinator.reconcileProjects(candidate, expectedRevision: staleRevision))

        guard case .staleRevision = coordinator.lastProjectOperationError else {
            Issue.record("expected staleRevision, got \(String(describing: coordinator.lastProjectOperationError))")
            return
        }
        // Candidate was not applied.
        #expect(coordinator.projectStore.projects.count == 2)
        // The flushed edit is retained and the live workspace is untouched.
        #expect(coordinator.workspaceStore.workspaces.map(\.id) == workspaceIDsBefore)
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == "Unsaved" })
        #expect(coordinator.projectStore.activeProject.tabs.contains { $0.title == "Unsaved" })
    }

    @Test("removing the active project selects the first and refreshes capture context and workspace")
    func reconcileActiveRemovalRefreshes() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://alpha.example.com/x"),
        ])
        #expect(coordinator.projectStore.activeProjectID == alpha.id)

        let revision = coordinator.projectStore.catalog.revision
        #expect(coordinator.reconcileProjects([beta], expectedRevision: revision))

        #expect(coordinator.projectStore.activeProjectID == beta.id)
        #expect(coordinator.activeCaptureContext.projectID == beta.id)
        #expect(coordinator.captureContextStore.snapshot()?.projectID == beta.id)
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == "BetaTab" })
        // Beta starts from its own (empty) runtime projection.
        #expect(coordinator.transactions.isEmpty)
    }

    @Test("updating the active project's tabs refreshes the workspace but retains runtime capture")
    func reconcileActiveTabUpdateRetainsCapture() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        let alphaTraffic = TestFixtures.makeTransaction(url: "https://alpha.example.com/x")
        coordinator.processActiveProjectTestBatch([alphaTraffic])

        let revision = coordinator.projectStore.catalog.revision
        var updatedAlpha = alpha
        updatedAlpha.tabs = alpha.tabs + [ProjectTabSnapshot(title: "Reconciled Tab", isClosable: true)]

        #expect(coordinator.reconcileProjects([updatedAlpha, beta], expectedRevision: revision))

        #expect(coordinator.projectStore.activeProjectID == alpha.id)
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == "Reconciled Tab" })
        // The surviving active project keeps its live capture history.
        #expect(coordinator.transactions.map(\.id) == [alphaTraffic.id])
    }

    @Test("an inactive-only reconciliation does not reset the current live workspace")
    func reconcileInactiveOnlyPreservesWorkspace() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        coordinator.workspaceStore.createWorkspace(title: "Live Scratch")
        _ = coordinator.flushProjectTabSnapshot()
        let flushedAlpha = coordinator.projectStore.activeProject
        let revision = coordinator.projectStore.catalog.revision
        let workspaceIDsBefore = coordinator.workspaceStore.workspaces.map(\.id)
        let activeWorkspaceBefore = coordinator.workspaceStore.activeWorkspaceID

        var renamedBeta = beta
        renamedBeta.name = "Beta Renamed"
        #expect(coordinator.reconcileProjects([flushedAlpha, renamedBeta], expectedRevision: revision))

        #expect(coordinator.projectStore.projects.contains { $0.name == "Beta Renamed" })
        // Active identity and tab configuration are unchanged, so the live workspace
        // (and its scratch tab) is not reset.
        #expect(coordinator.workspaceStore.workspaces.map(\.id) == workspaceIDsBefore)
        #expect(coordinator.workspaceStore.activeWorkspaceID == activeWorkspaceBefore)
        #expect(coordinator.workspaceStore.workspaces.contains { $0.title == "Live Scratch" })
    }

    @Test("reconciliation clears runtime buckets only for removed project IDs")
    func reconcileClearsRemovedProjectBuckets() async {
        let (catalog, alpha, beta) = Self.twoProjectCatalog()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: FakeProjectRepo(loadResult: .success(catalog))
        )
        await coordinator.hydrateProjectsOnLaunch()
        #expect(coordinator.switchToProject(id: beta.id))
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://beta.example.com/x"),
        ])
        #expect(coordinator.switchToProject(id: alpha.id))
        coordinator.processActiveProjectTestBatch([
            TestFixtures.makeTransaction(url: "https://alpha.example.com/x"),
        ])
        #expect(coordinator.transactionsByProjectID[beta.id] != nil)
        #expect(coordinator.transactionsByProjectID[alpha.id] != nil)

        let revision = coordinator.projectStore.catalog.revision
        #expect(coordinator.reconcileProjects([alpha], expectedRevision: revision))

        #expect(coordinator.transactionsByProjectID[beta.id] == nil)
        #expect(coordinator.logEntriesByProjectID[beta.id] == nil)
        #expect(coordinator.sessionProvenanceByProjectID[beta.id] == nil)
        // The surviving active project keeps its bucket.
        #expect(coordinator.transactionsByProjectID[alpha.id] != nil)
        #expect(coordinator.projectStore.activeProjectID == alpha.id)
    }

    // MARK: Capacity refresh

    @Test("capacity refresh updates both creation gates and retains over-limit projects and tabs")
    func capacityRefreshUpdatesGatesRetainingState() async {
        let coordinator = MainContentCoordinator(
            policy: FlexibleProjectPolicy(maxWorkspaceTabs: 8, maxProjects: 6),
            projectCatalogRepository: FakeProjectRepo()
        )
        await coordinator.hydrateProjectsOnLaunch()
        _ = coordinator.createProject(named: "Second")
        _ = coordinator.createProject(named: "Third")
        coordinator.workspaceStore.createWorkspace(title: "Tab A")
        coordinator.workspaceStore.createWorkspace(title: "Tab B")
        #expect(coordinator.projectStore.projects.count == 3)
        #expect(coordinator.workspaceStore.workspaces.count == 3)

        coordinator.refreshProjectCreationCapacity(
            with: FlexibleProjectPolicy(maxWorkspaceTabs: 2, maxProjects: 2)
        )

        #expect(coordinator.projectStore.maxProjects == 2)
        #expect(coordinator.workspaceStore.maxWorkspaces == 2)
        // No retained state is deleted or truncated by the lower limits.
        #expect(coordinator.projectStore.projects.count == 3)
        #expect(coordinator.workspaceStore.workspaces.count == 3)
        #expect(!coordinator.projectStore.canCreateProject)
        #expect(!coordinator.workspaceStore.canCreateWorkspace)
    }

    // MARK: Autosave debounce & exclusion

    @Test("rapid edits coalesce into a single durable autosave")
    func debounceCoalescing() async {
        let repo = FakeProjectRepo()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: repo,
            projectTabAutosaveDebounce: .milliseconds(50)
        )
        await coordinator.hydrateProjectsOnLaunch()

        coordinator.workspaceStore.activeWorkspace.title = "One"
        coordinator.scheduleProjectTabAutosave()
        coordinator.workspaceStore.activeWorkspace.title = "Two"
        coordinator.scheduleProjectTabAutosave()
        coordinator.workspaceStore.activeWorkspace.title = "Three"
        coordinator.scheduleProjectTabAutosave()

        await repo.waitForFirstSave()

        #expect(await repo.saveCount == 1)
        #expect(coordinator.projectStore.activeProject.tabs.contains { $0.title == "Three" })
    }

    @Test("non-durable changes do not trigger a durable autosave")
    func snapshotExclusionForNonDurableState() async throws {
        let repo = FakeProjectRepo()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: repo,
            projectTabAutosaveDebounce: .milliseconds(50)
        )
        await coordinator.hydrateProjectsOnLaunch()
        let revisionBefore = coordinator.projectStore.catalog.revision

        // Traffic, filtered rows, sidebar indexes, and selection are excluded from
        // the durable snapshot seams, so recomputing them must not autosave.
        coordinator.transactions = [
            TestFixtures.makeTransaction(url: "https://a.example.com/x"),
            TestFixtures.makeTransaction(url: "https://b.example.com/y"),
        ]
        coordinator.recomputeAllWorkspaces()
        coordinator.selectedTransactionIDs = [coordinator.transactions[0].id]

        try await Task.sleep(for: .milliseconds(200))

        #expect(await repo.saveCount == 0)
        #expect(coordinator.projectStore.catalog.revision == revisionBefore)
    }

    @Test("termination flush persists pending durable tab edits immediately")
    func terminationFlushPersistsPendingEdits() async {
        let repo = FakeProjectRepo()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: repo,
            projectTabAutosaveDebounce: .seconds(30)
        )
        await coordinator.hydrateProjectsOnLaunch()
        coordinator.workspaceStore.activeWorkspace.title = "Before Quit"

        await coordinator.flushProjectStateForTermination()

        #expect(await repo.saveCount == 1)
        #expect(await repo.lastSavedCatalog?.activeProject?.tabs[0].title == "Before Quit")
    }

    @Test("termination flush remains reachable after the primary window closes")
    func terminationFlushSurvivesWindowClosure() async {
        let repo = FakeProjectRepo()
        let coordinator = MainContentCoordinator(
            projectCatalogRepository: repo,
            projectTabAutosaveDebounce: .seconds(30)
        )
        await coordinator.hydrateProjectsOnLaunch()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let manager = RockxyWorkspaceWindowManager.shared
        manager.registerPrimaryWindow(window, coordinator: coordinator)
        coordinator.workspaceStore.activeWorkspace.title = "Closed Before Quit"

        manager.handleWindowWillClose(window)
        #expect(!manager.canCreateWorkspaceTab)
        await manager.flushProjectStateForTermination()

        #expect(await repo.lastSavedCatalog?.activeProject?.tabs[0].title == "Closed Before Quit")
    }

    // MARK: Store failure surfacing

    @Test("store-not-ready is surfaced to operations after a failed load")
    func storeNotReadySurfaced() async {
        let repo = FakeProjectRepo(loadResult: .failure(FakeError.boom))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        await coordinator.hydrateProjectsOnLaunch()

        #expect(!coordinator.switchToProject(id: UUID()))
        #expect(coordinator.lastProjectOperationError == .storeNotReady)
        #expect(coordinator.createProject(named: "Nope") == nil)
        #expect(coordinator.lastProjectOperationError == .storeNotReady)
        #expect(coordinator.projectPersistenceWarningMessage != nil)
    }

    @Test("revision exhaustion is surfaced without a successful create")
    func revisionExhaustionSurfaced() async {
        var catalog = ProjectCatalog.makeDefault(now: Self.fixedDate)
        catalog.revision = UInt64.max
        let repo = FakeProjectRepo(loadResult: .success(catalog))
        let coordinator = MainContentCoordinator(projectCatalogRepository: repo)
        await coordinator.hydrateProjectsOnLaunch()

        #expect(coordinator.createProject(named: "Gamma") == nil)
        #expect(coordinator.lastProjectOperationError == .revisionExhausted)
    }

    // MARK: Private

    // MARK: Helpers

    private static let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    private static func makeProject(name: String) -> Project {
        Project.makeDefault(name: name, createdAt: fixedDate, updatedAt: fixedDate)
    }

    /// A two-project catalog: Alpha (active, single default tab) and Beta
    /// (default tab plus a distinctive closable "BetaTab").
    private static func twoProjectCatalog() -> (catalog: ProjectCatalog, alpha: Project, beta: Project) {
        let alpha = Project.makeDefault(name: "Alpha", createdAt: fixedDate, updatedAt: fixedDate)
        let betaDefault = ProjectTabSnapshot.makeDefaultAllTraffic()
        let betaTab = ProjectTabSnapshot(title: "BetaTab", isClosable: true)
        let beta = Project(
            name: "Beta",
            createdAt: fixedDate,
            updatedAt: fixedDate,
            activeTabID: betaDefault.id,
            tabs: [betaDefault, betaTab]
        )
        let catalog = ProjectCatalog(activeProjectID: alpha.id, projects: [alpha, beta])
        return (catalog, alpha, beta)
    }
}

// MARK: - FakeProjectRepo

/// Actor-isolated persistence double mirroring the real repository's isolation so
/// the store's `Sendable` seam is exercised faithfully.
private actor FakeProjectRepo: ProjectCatalogPersisting {
    // MARK: Lifecycle

    init(
        loadResult: Result<ProjectCatalog, Error> = .success(
            ProjectCatalog.makeDefault(now: Date(timeIntervalSince1970: 1_000_000))
        )
    ) {
        self.loadResult = loadResult
    }

    // MARK: Internal

    private(set) var savedCatalogs: [ProjectCatalog] = []
    private(set) var loadCount = 0

    var saveCount: Int {
        savedCatalogs.count
    }

    var lastSavedCatalog: ProjectCatalog? {
        savedCatalogs.last
    }

    func load() async throws -> ProjectCatalog {
        loadCount += 1
        return try loadResult.get()
    }

    func save(_ catalog: ProjectCatalog) async throws {
        savedCatalogs.append(catalog)
        let waiters = firstSaveWaiters
        firstSaveWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func reset() async throws -> ProjectCatalog {
        let fresh = ProjectCatalog.makeDefault(now: Date(timeIntervalSince1970: 1_000_000))
        savedCatalogs.append(fresh)
        return fresh
    }

    func waitForFirstSave() async {
        guard savedCatalogs.isEmpty else {
            return
        }
        await withCheckedContinuation { continuation in
            firstSaveWaiters.append(continuation)
        }
    }

    // MARK: Private

    private let loadResult: Result<ProjectCatalog, Error>
    private var firstSaveWaiters: [CheckedContinuation<Void, Never>] = []
}

// MARK: - FakeError

private enum FakeError: Error, Equatable {
    case boom
}

// MARK: - TinyProjectHistoryPolicy

private struct TinyProjectHistoryPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 2
}

// MARK: - FlexibleProjectPolicy

private struct FlexibleProjectPolicy: AppPolicy {
    var maxWorkspaceTabs: Int
    var maxProjects: Int
    var maxDomainFavorites = 5
    var maxActiveRulesPerTool = 10
    var maxEnabledScripts = 10
    var maxLiveHistoryEntries = 1_000
}
