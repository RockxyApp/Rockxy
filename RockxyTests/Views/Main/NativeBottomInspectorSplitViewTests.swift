import AppKit
@testable import Rockxy
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct NativeBottomInspectorSplitViewTests {
    // MARK: Internal

    @Test("Bottom inspector minimum heights scale with the app font")
    func fontAwareLayoutMetrics() {
        let defaultMetrics = BottomInspectorLayoutMetrics()
        var largeSettings = AppUISettings.default
        largeSettings.fontSize = 28
        let largeMetrics = BottomInspectorLayoutMetrics(
            appMetrics: AppUIDisplayMetrics(settings: largeSettings)
        )

        #expect(defaultMetrics.requestListMinimumHeight == 88)
        #expect(defaultMetrics.inspectorMinimumHeight == 232)
        #expect(largeMetrics.requestListMinimumHeight > defaultMetrics.requestListMinimumHeight)
        #expect(largeMetrics.inspectorMinimumHeight > defaultMetrics.inspectorMinimumHeight)
    }

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
        #expect(controller.splitViewItems[0].minimumThickness == 88)
        #expect(controller.splitViewItems[1].minimumThickness == 232)
    }

    @Test("Bottom inspector sizing policy permits nearly all available height")
    func bottomInspectorSupportsTallResize() {
        let controller = makeController(isInspectorPresented: true)
        let availableInspectorHeight = 900
            - controller.splitView.dividerThickness
            - controller.splitViewItems[0].minimumThickness

        #expect(availableInspectorHeight > 700)
        #expect(controller.splitViewItems[1].minimumThickness == 232)
    }

    @Test("Fresh bottom split gives the payload inspector most of the available height")
    func freshLayoutFavorsPayloadInspector() {
        let autosaveName = uniqueAutosaveName()
        removeSplitViewAutosaveDefaults(autosaveName)
        let controller = makeConfiguredController(
            isInspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))

        let divider = controller.splitView.dividerThickness
        let expectedPrimaryHeight = (700 - divider)
            * NativeBottomInspectorSplitSizing.defaultRequestListRatio
        let primaryHeight = NativeBottomInspectorSplitSizing.idealPrimaryHeight(
            totalHeight: 700,
            dividerThickness: divider,
            requestListRatio: NativeBottomInspectorSplitSizing.defaultRequestListRatio,
            primaryMinimumHeight: 88,
            inspectorMinimumHeight: 232
        )

        #expect(primaryHeight == expectedPrimaryHeight)
        #expect(abs(controller.splitViewItems[0].preferredThicknessFraction - 0.28) < 0.0001)
        #expect(abs(controller.splitViewItems[1].preferredThicknessFraction - 0.72) < 0.0001)
        #expect(controller.splitViewItems[1].viewController.view.frame.height > 500)
        #expect(controller.defaultDividerApplicationCount == 1)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Bottom inspector keeps a low holding priority so its divider remains draggable")
    func bottomInspectorUsesResizableHoldingPriority() {
        let controller = makeController(isInspectorPresented: true)

        #expect(controller.splitViewItems[0].holdingPriority == .defaultLow)
        #expect(controller.splitViewItems[1].holdingPriority == .defaultLow)
    }

    @Test("Horizontal divider has a forgiving vertical drag target")
    func horizontalDividerHitTarget() {
        let controller = makeController(isInspectorPresented: true)
        let drawnRect = NSRect(x: 0, y: 300, width: 1_200, height: 1)
        let effectiveRect = controller.splitView(
            controller.splitView,
            effectiveRect: drawnRect,
            forDrawnRect: drawnRect,
            ofDividerAt: 0
        )

        #expect(effectiveRect.height >= NativeSplitDividerInteraction.minimumHitThickness)
        #expect(effectiveRect.minY < drawnRect.minY)
        #expect(effectiveRect.maxY > drawnRect.maxY)
    }

    @Test("Horizontal divider moves through a useful height range after layout")
    func horizontalDividerMovesAfterLayout() {
        let controller = makeController(isInspectorPresented: true)

        controller.splitView.setPosition(180, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        let tallInspectorHeight = controller.splitViewItems[1].viewController.view.frame.height

        controller.splitView.setPosition(450, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        let compactInspectorHeight = controller.splitViewItems[1].viewController.view.frame.height

        #expect(tallInspectorHeight > compactInspectorHeight)
        #expect(tallInspectorHeight > 450)
        #expect(compactInspectorHeight >= 232)
    }

    @Test("Autosaved split frames take precedence over the default ratio")
    func autosavedFramesSkipDefaultRatio() {
        let autosaveName = uniqueAutosaveName()
        setSplitViewAutosaveFrames(autosaveName)
        let controller = makeConfiguredController(
            isInspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))

        #expect(controller.hasAutosavedFrames)
        #expect(controller.defaultDividerApplicationCount == 0)
        #expect(controller.splitViewItems[1].viewController.view.frame.height >= 232)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Window resizing never reapplies the default divider ratio")
    func resizeDoesNotReapplyDefaultRatio() {
        let autosaveName = uniqueAutosaveName()
        removeSplitViewAutosaveDefaults(autosaveName)
        let controller = makeConfiguredController(
            isInspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))
        controller.splitView.setPosition(300, ofDividerAt: 0)
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 800))

        #expect(controller.defaultDividerApplicationCount == 1)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("First selection expands a fresh payload inspector at its default height")
    func firstExpansionAppliesDefaultRatio() {
        let autosaveName = uniqueAutosaveName()
        removeSplitViewAutosaveDefaults(autosaveName)
        let controller = makeConfiguredController(
            isInspectorPresented: false,
            autosaveName: autosaveName
        )
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))

        #expect(!controller.isInspectorPresented)
        #expect(controller.defaultDividerApplicationCount == 0)

        controller.setInspectorPresented(true, animated: false)
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))

        #expect(controller.isInspectorPresented)
        #expect(controller.splitViewItems[1].viewController.view.frame.height > 500)
        #expect(controller.defaultDividerApplicationCount == 1)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Font-driven minimum updates preserve the applied divider")
    func minimumUpdatesPreserveDivider() {
        let autosaveName = uniqueAutosaveName()
        removeSplitViewAutosaveDefaults(autosaveName)
        let controller = makeConfiguredController(
            isInspectorPresented: true,
            autosaveName: autosaveName
        )
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 800))

        controller.updateMinimumHeights(primary: 312, inspector: 397)

        #expect(controller.splitViewItems[0].minimumThickness == 312)
        #expect(controller.splitViewItems[1].minimumThickness == 397)
        #expect(controller.defaultDividerApplicationCount == 1)
        removeSplitViewAutosaveDefaults(autosaveName)
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

    @Test("Repeated SwiftUI updates do not enqueue duplicate collapse animations")
    func repeatedPresentationUpdatesAreCoalesced() {
        let coordinator = NativeBottomInspectorSplitView<Color, Color>.Coordinator()

        coordinator.recordInitialPresentation(true)
        #expect(!coordinator.shouldApplyPresentation(true))
        #expect(coordinator.shouldApplyPresentation(false))
        #expect(!coordinator.shouldApplyPresentation(false))
        #expect(coordinator.shouldApplyPresentation(true))
    }

    // MARK: - Startup geometry readiness

    @Test("Bottom inspector layout readiness rejects zero and non-finite bounds")
    func layoutReadinessRejectsInvalidBounds() {
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(.zero))
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 1_200, height: 0)
        ))
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 0, height: 700)
        ))
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 1_200, height: CGFloat.infinity)
        ))
        #expect(!NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 1_200, height: -700)
        ))
        #expect(NativeBottomInspectorSplitSizing.isLayoutReady(
            CGRect(x: 0, y: 0, width: 1_200, height: 700)
        ))
    }

    @Test("Bottom split readiness includes both pane minima and the divider")
    func minimumReadinessIncludesDivider() {
        #expect(!NativeBottomInspectorSplitSizing.canSeatRequestedMinima(
            totalHeight: 320,
            dividerThickness: 1,
            inspectorPresented: true,
            primaryMinimumHeight: 88,
            inspectorMinimumHeight: 232
        ))
        #expect(NativeBottomInspectorSplitSizing.canSeatRequestedMinima(
            totalHeight: 321,
            dividerThickness: 1,
            inspectorPresented: true,
            primaryMinimumHeight: 88,
            inspectorMinimumHeight: 232
        ))
        #expect(NativeBottomInspectorSplitSizing.canSeatRequestedMinima(
            totalHeight: 88,
            dividerThickness: 1,
            inspectorPresented: false,
            primaryMinimumHeight: 88,
            inspectorMinimumHeight: 232
        ))
    }

    @Test("Configuring the bottom inspector at zero bounds never produces negative geometry")
    func zeroBoundsProducesNonNegativeGeometry() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            isInspectorPresented: true,
            autosaveName: autosaveName
        )

        layout(controller, at: .zero)

        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Deferred initial collapse applies once bounds become sufficient")
    func deferredCollapseAppliesAtSufficientBounds() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            isInspectorPresented: false,
            autosaveName: autosaveName
        )

        layout(controller, at: .zero)
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))

        #expect(!controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    @Test("Insufficient height preserves inspector visibility without negative geometry")
    func insufficientHeightPreservesVisibility() {
        let autosaveName = uniqueAutosaveName()
        let controller = makeConfiguredController(
            isInspectorPresented: true,
            autosaveName: autosaveName
        )

        // Positive but below the combined primary + inspector minimum height.
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 150))

        #expect(controller.isInspectorPresented)
        expectNonNegativeArrangedGeometry(controller)
        removeSplitViewAutosaveDefaults(autosaveName)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeController(isInspectorPresented: Bool) -> NativeBottomInspectorSplitViewController {
        let controller = makeConfiguredController(
            isInspectorPresented: isInspectorPresented,
            autosaveName: uniqueAutosaveName()
        )
        layout(controller, at: CGRect(x: 0, y: 0, width: 1_200, height: 700))
        return controller
    }

    private func layout(_ controller: NativeBottomInspectorSplitViewController, at frame: CGRect) {
        controller.view.frame = frame
        controller.view.needsLayout = true
        controller.view.layoutSubtreeIfNeeded()
    }

    private func makeConfiguredController(
        isInspectorPresented: Bool,
        autosaveName: String
    )
        -> NativeBottomInspectorSplitViewController
    {
        let controller = NativeBottomInspectorSplitViewController()
        controller.configure(
            primaryController: NSHostingController(rootView: Color.clear),
            inspectorController: NSHostingController(rootView: Color.clear),
            isInspectorPresented: isInspectorPresented,
            autosaveName: autosaveName,
            primaryMinimumHeight: 88,
            inspectorMinimumHeight: 232
        )
        return controller
    }

    private func uniqueAutosaveName() -> String {
        AppKitAutosaveTestKeys.uniqueSplitViewAutosaveName(for: .bottomInspectorSplitView)
    }

    private func expectNonNegativeArrangedGeometry(
        _ controller: NativeBottomInspectorSplitViewController
    ) {
        for item in controller.splitViewItems {
            let frame = item.viewController.view.frame
            #expect(frame.width.isFinite)
            #expect(frame.height.isFinite)
            #expect(frame.width >= 0)
            #expect(frame.height >= 0)
        }
    }

    private func removeSplitViewAutosaveDefaults(_ autosaveName: String) {
        UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(autosaveName)")
    }

    private func setSplitViewAutosaveFrames(_ autosaveName: String) {
        UserDefaults.standard.set(
            [
                "0.000000, 0.000000, 1200.000000, 593.000000, NO, NO",
                "0.000000, 594.000000, 1200.000000, 106.000000, NO, NO",
            ],
            forKey: "NSSplitView Subview Frames \(autosaveName)"
        )
    }
}
