import Foundation
@testable import Rockxy
import Testing

@MainActor
@Suite("Babylon capture coordinator")
struct BabylonCaptureCoordinatorTests {
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
