import Foundation
@testable import Rockxy
import Testing

// MARK: - BabylonCaptureCoordinatorTests

@MainActor
@Suite("Babylon capture coordinator")
struct BabylonCaptureCoordinatorTests {
    @Test("Babylon-only intake refreshes existing rows when their close arrives during Pause")
    func pausedBabylonCloseRefreshesWithoutProxy() async {
        let coordinator = MainContentCoordinator()
        await coordinator.configureBabylonCaptureIntake().value
        await coordinator.sessionManager.stopBatchTimer()
        let row = TestFixtures.makeTransaction(state: .active)
        await coordinator.receiveBabylonTransaction(row)
        let pending = await coordinator.sessionManager.flushPendingUpdates()
        coordinator.processBatch(pending, generation: coordinator.sessionGeneration)
        #expect(coordinator.filteredRows.first?.state == .active)
        coordinator.isRecording = false
        row.state = .failed
        await coordinator.receiveBabylonTransaction(row, isUpdate: true)
        _ = await coordinator.sessionManager.flushPendingUpdates()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while coordinator.filteredRows.first?.state != .failed, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(!coordinator.isProxyRunning)
        #expect(coordinator.transactions.count == 1)
        #expect(coordinator.filteredRows.first?.state == .failed)
        await coordinator.receiveBabylonTransaction(TestFixtures.makeTransaction())
        #expect(await coordinator.sessionManager.flushPendingUpdates().isEmpty)
    }

    @Test("Pausing while Project hydration waits prevents a new Babylon row from leaking in")
    func pauseDuringHydrationRejectsNewRows() async {
        let repository = PausedIntakeProjectRepository()
        let coordinator = MainContentCoordinator(projectCatalogRepository: repository)
        let receive = Task { await coordinator.receiveBabylonTransaction(TestFixtures.makeTransaction()) }
        await repository.waitForLoad()
        coordinator.isRecording = false
        await repository.finishLoad()
        await receive.value
        #expect(await coordinator.sessionManager.flushPendingUpdates().isEmpty)
        #expect(coordinator.transactions.isEmpty)
    }

    @Test("Connection identity creates source-filtered workspace once")
    func createsSourceWorkspaceOnce() async {
        let coordinator = MainContentCoordinator()
        let sessionID = UUID().uuidString
        let identity = BabylonCaptureIdentity(
            clientID: "client",
            sessionID: sessionID,
            projectName: "Checkout",
            bundleIdentifier: "com.example.checkout",
            deviceName: "Test iPhone",
            deviceModel: "iPhone"
        )

        await coordinator.registerBabylonCapture(identity: identity)
        await coordinator.registerBabylonCapture(identity: identity)

        #expect(coordinator.workspaceStore.workspaces.count == 2)
        #expect(coordinator.activeWorkspace.title == "Checkout • Test iPhone")
        #expect(coordinator.activeWorkspace.filterCriteria.sidebarApp == "Checkout • Test iPhone")
    }

    @Test("Relaunching the app reuses its tab instead of opening another")
    func relaunchReusesWorkspace() async {
        let coordinator = MainContentCoordinator()
        func identity(session: String) -> BabylonCaptureIdentity {
            BabylonCaptureIdentity(
                clientID: "client-relaunch",
                sessionID: session,
                projectName: "Relaunch",
                bundleIdentifier: "com.example.relaunch",
                deviceName: "Test iPhone",
                deviceModel: "iPhone"
            )
        }

        await coordinator.registerBabylonCapture(identity: identity(session: UUID().uuidString))
        let babylonTab = coordinator.activeWorkspace.id
        coordinator.workspaceStore.selectWorkspace(id: coordinator.workspaceStore.workspaces[0].id)

        // Each launch of the app is a new Babylon session.
        await coordinator.registerBabylonCapture(identity: identity(session: UUID().uuidString))
        await coordinator.registerBabylonCapture(identity: identity(session: UUID().uuidString))

        let matching = coordinator.workspaceStore.workspaces.filter {
            $0.filterCriteria.sidebarApp == "Relaunch • Test iPhone"
        }
        #expect(matching.map(\.id) == [babylonTab])
        // The tab the developer was looking at keeps focus.
        #expect(coordinator.activeWorkspace.id == coordinator.workspaceStore.workspaces[0].id)
    }
}

// MARK: - PausedIntakeProjectRepository

private actor PausedIntakeProjectRepository: ProjectCatalogPersisting {
    // MARK: Internal

    func load() async throws -> ProjectCatalog {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
        }
    }

    func save(_ catalog: ProjectCatalog) async throws {}
    func reset() async throws -> ProjectCatalog {
        ProjectCatalog.makeDefault(now: Date(timeIntervalSince1970: 1_000_000))
    }

    func waitForLoad() async {
        guard !started else {
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finishLoad() {
        loadContinuation?.resume(returning: ProjectCatalog.makeDefault(now: Date(timeIntervalSince1970: 1_000_000)))
        loadContinuation = nil
    }

    // MARK: Private

    private var loadContinuation: CheckedContinuation<ProjectCatalog, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
}
