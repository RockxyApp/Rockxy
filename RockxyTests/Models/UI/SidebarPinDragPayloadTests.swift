import Foundation
@testable import Rockxy
import Testing

struct SidebarPinDragPayloadTests {
    @Test("Domains and apps survive a drag payload round trip")
    func roundTrips() throws {
        let items: [SidebarItem] = [
            .domainNode(domain: "api.example.com"),
            .domainPath(domain: "api.example.com", pathPrefix: "/v1"),
            .app(name: "curl", bundleId: nil),
        ]
        for item in items {
            let payload = try #require(SidebarPinDragPayload.encode(item))
            #expect(SidebarPinDragPayload.decode(payload) == item)
        }
    }

    @Test("Other sidebar items cannot be pinned by dragging, and foreign text is ignored")
    func rejectsOthers() {
        #expect(SidebarPinDragPayload.encode(.allApps) == nil)
        #expect(SidebarPinDragPayload.encode(.insights) == nil)
        #expect(SidebarPinDragPayload.decode("hello") == nil)
        #expect(SidebarPinDragPayload.decode("rockxy-sidebar-pin:not-base64!") == nil)
    }
}
