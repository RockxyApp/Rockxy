import AppKit
@testable import Rockxy
import Testing

@MainActor
@Suite("Workspace window placement")
struct WorkspaceWindowPlacementTests {
    @Test("Main window opens at a useful traffic-debugging size")
    func mainWindowLayoutMetrics() {
        #expect(MainWindowLayoutMetrics.defaultWidth == 1_200)
        #expect(MainWindowLayoutMetrics.defaultHeight == 760)
        #expect(MainWindowLayoutMetrics.minimumWidth == 960)
        #expect(MainWindowLayoutMetrics.minimumHeight == 620)
        #expect(MainWindowLayoutMetrics.defaultWidth >= MainWindowLayoutMetrics.minimumWidth)
        #expect(MainWindowLayoutMetrics.defaultHeight >= MainWindowLayoutMetrics.minimumHeight)
    }

    @Test("Workspace tabs distribute available width before shrinking")
    func workspaceTabsDistributeAvailableWidth() {
        #expect(RockxyWorkspaceWindowManager.workspaceTabWidth(availableWidth: 1_200, tabCount: 2) == 600)
        #expect(RockxyWorkspaceWindowManager.workspaceTabWidth(availableWidth: 1_200, tabCount: 4) == 300)
        #expect(RockxyWorkspaceWindowManager.workspaceTabWidth(availableWidth: 640, tabCount: 8) == 80)
    }

    @Test("Workspace tab width handles empty and narrow inputs")
    func workspaceTabWidthHandlesEdgeInputs() {
        #expect(RockxyWorkspaceWindowManager.workspaceTabWidth(availableWidth: 1_200, tabCount: 0) == 0)
        #expect(RockxyWorkspaceWindowManager.workspaceTabWidth(availableWidth: 320, tabCount: 8) == 56)
    }

    @Test("Auxiliary windows are centered over the primary workspace window")
    func auxiliaryWindowsAreCenteredOverPrimaryWorkspaceWindow() {
        let windowFrame = NSRect(x: 0, y: 0, width: 760, height: 500)
        let parentFrame = NSRect(x: 120, y: 160, width: 1_180, height: 760)

        let centered = RockxyWorkspaceWindowManager.centeredFrame(
            windowFrame: windowFrame,
            parentFrame: parentFrame,
            visibleFrame: nil
        )

        #expect(centered.origin.x == 330)
        #expect(centered.origin.y == 290)
        #expect(centered.size == windowFrame.size)
    }

    @Test("Auxiliary window placement stays inside the visible screen frame")
    func auxiliaryWindowPlacementStaysInsideVisibleScreenFrame() {
        let windowFrame = NSRect(x: 0, y: 0, width: 780, height: 540)
        let parentFrame = NSRect(x: 1_400, y: 900, width: 600, height: 400)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)

        let centered = RockxyWorkspaceWindowManager.centeredFrame(
            windowFrame: windowFrame,
            parentFrame: parentFrame,
            visibleFrame: visibleFrame
        )

        #expect(centered.maxX <= visibleFrame.maxX)
        #expect(centered.maxY <= visibleFrame.maxY)
        #expect(centered.minX >= visibleFrame.minX)
        #expect(centered.minY >= visibleFrame.minY)
    }
}
