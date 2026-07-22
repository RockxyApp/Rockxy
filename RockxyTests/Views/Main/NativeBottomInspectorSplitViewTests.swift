import AppKit
@testable import Rockxy
import SwiftUI
import Testing

@MainActor
struct NativeBottomInspectorSplitViewTests {
    @Test("Bottom inspector sizing preserves the proposed workspace size")
    func proposedSizeIsPreserved() throws {
        let resolved = try #require(NativeBottomInspectorSplitSizing.resolve(
            ProposedViewSize(width: 1_514, height: 894),
            naturalHeight: 400
        ))

        #expect(resolved == CGSize(width: 1_514, height: 894))
    }

    @Test("Bottom inspector uses a native horizontal collapsible split item")
    func nativeHorizontalConfiguration() {
        let controller = makeController(isInspectorPresented: true)

        #expect(!controller.splitView.isVertical)
        #expect(controller.splitView.dividerStyle == .thin)
        #expect(controller.splitViewItems.count == 2)
        #expect(!controller.splitViewItems[0].canCollapse)
        #expect(controller.splitViewItems[1].canCollapse)
        #expect(controller.splitViewItems[0].minimumThickness == 200)
        #expect(controller.splitViewItems[1].minimumThickness == 320)
    }

    @Test("Bottom split collapses without recreating either pane")
    func collapsePreservesPaneControllers() {
        let controller = makeController(isInspectorPresented: true)
        let primaryController = controller.splitViewItems[0].viewController
        let inspectorController = controller.splitViewItems[1].viewController

        controller.setInspectorPresented(false, animated: false)
        #expect(!controller.isInspectorPresented)
        controller.setInspectorPresented(true, animated: false)

        #expect(controller.isInspectorPresented)
        #expect(controller.splitViewItems[0].viewController === primaryController)
        #expect(controller.splitViewItems[1].viewController === inspectorController)
    }

    private func makeController(isInspectorPresented: Bool) -> NativeBottomInspectorSplitViewController {
        let controller = NativeBottomInspectorSplitViewController()
        controller.configure(
            primaryController: NSHostingController(rootView: Color.clear),
            inspectorController: NSHostingController(rootView: Color.clear),
            isInspectorPresented: isInspectorPresented,
            autosaveName: "NativeBottomInspectorSplitViewTests-\(UUID().uuidString)",
            primaryMinimumHeight: 200,
            inspectorMinimumHeight: 320
        )
        controller.view.frame = CGRect(x: 0, y: 0, width: 1_200, height: 700)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }
}
