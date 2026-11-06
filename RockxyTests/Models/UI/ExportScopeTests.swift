import Foundation
@testable import Rockxy
import Testing

// MARK: - ExportScopeTests

struct ExportScopeTests {
    @Test("Snapshot freezes ordered membership and derives eligible/skipped counts")
    func snapshotDerivesCounts() {
        let t1 = TestFixtures.makeTransaction(url: "https://api.example.com/a")
        let t2 = TestFixtures.makeTransaction(url: "https://api.example.com/b")
        let ws = TestFixtures.makeWebSocketTransaction()

        let harSnapshot = ExportScopeSnapshot(transactions: [t1, t2, ws], format: .har)
        #expect(harSnapshot.total == 3)
        #expect(harSnapshot.eligibleCount == 3)
        #expect(harSnapshot.skippedCount == 0)
        #expect(harSnapshot.orderedIDs == [t1.id, t2.id, ws.id])

        let openSnapshot = ExportScopeSnapshot(transactions: [t1, t2, ws], format: .openAPIYAML)
        #expect(openSnapshot.total == 3)
        #expect(openSnapshot.eligibleCount == 2)
        #expect(openSnapshot.skippedCount == 1)
        #expect(openSnapshot.eligibleOrderedIDs == [t1.id, t2.id])
    }

    @Test("OpenAPI context disables scopes with no eligible requests")
    func disablesIneligibleOpenAPIScopes() {
        let eligible = TestFixtures.makeTransaction(url: "https://api.example.com/a")
        let context = ExportScopeContext(
            format: .openAPIYAML,
            originWorkspaceID: UUID(),
            originWorkspaceTitle: "Capture",
            allTransactions: [eligible, TestFixtures.makeWebSocketTransaction()],
            filteredTransactions: [TestFixtures.makeWebSocketTransaction()],
            selectedTransactions: [TestFixtures.makeWebSocketTransaction()],
            hasActiveFilter: true
        )

        #expect(context.isEnabled(.all))
        #expect(!context.isEnabled(.filtered))
        #expect(!context.isEnabled(.selected))
        #expect(context.label(for: .all) == "All Captured Requests")
        #expect(context.countSummary(for: .all) == "1 included · 1 skipped")
        #expect(context.skippedNote(for: .all) != nil)
    }

    @Test("HAR context reports transaction counts and honest enablement")
    func harContextLabels() {
        let transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/a"),
            TestFixtures.makeTransaction(url: "https://api.example.com/b"),
            TestFixtures.makeTransaction(url: "https://api.example.com/c"),
        ]
        let context = ExportScopeContext(
            format: .har,
            originWorkspaceID: UUID(),
            originWorkspaceTitle: "Capture",
            allTransactions: transactions,
            filteredTransactions: transactions,
            selectedTransactions: [],
            hasActiveFilter: false
        )

        #expect(context.label(for: .all) == "All Transactions")
        #expect(context.countSummary(for: .all) == "3 transactions")
        #expect(context.skippedNote(for: .all) == nil)
        #expect(context.isEnabled(.all))
        #expect(!context.isEnabled(.filtered))
        #expect(context.reason(for: .filtered) == "No active filter")
        #expect(!context.isEnabled(.selected))
        #expect(context.reason(for: .selected) == "No requests selected")
        #expect(context.initialScope == .all)
    }

    @Test("An active filter that matches every request still enables the filtered scope")
    func activeFilterMatchingEverythingEnablesFiltered() {
        let transactions = [
            TestFixtures.makeTransaction(url: "https://api.example.com/a"),
            TestFixtures.makeTransaction(url: "https://api.example.com/b"),
        ]
        let context = ExportScopeContext(
            format: .har,
            originWorkspaceID: UUID(),
            originWorkspaceTitle: "Capture",
            allTransactions: transactions,
            filteredTransactions: transactions,
            selectedTransactions: [],
            hasActiveFilter: true
        )

        #expect(context.isEnabled(.filtered))
        #expect(context.reason(for: .filtered) == nil)
        #expect(context.initialScope == .filtered)
    }

    @Test("A selection-locked context offers only the selected scope")
    func selectionRestrictedContext() {
        let selected = TestFixtures.makeTransaction(url: "https://api.example.com/a")
        let context = ExportScopeContext(
            format: .har,
            originWorkspaceID: UUID(),
            originWorkspaceTitle: "Capture",
            allTransactions: [selected, TestFixtures.makeTransaction(url: "https://api.example.com/b")],
            filteredTransactions: [selected],
            selectedTransactions: [selected],
            hasActiveFilter: true,
            restrictsToSelection: true
        )

        #expect(!context.isEnabled(.all))
        #expect(!context.isEnabled(.filtered))
        #expect(context.isEnabled(.selected))
        #expect(context.availableScopes == [.selected])
        #expect(context.unavailableScopes.isEmpty)
        #expect(context.initialScope == .selected)
    }

    @Test("Export format copy describes scope and privacy without fidelity guarantees")
    func exportFormatCopy() {
        #expect(TrafficExportFormat.har.subtitle.contains("HAR archive"))
        #expect(TrafficExportFormat.har.limitationNote?.contains("WebSocket frames") == true)
        #expect(TrafficExportFormat.csv.limitationNote?.contains("Headers, bodies") == true)
        #expect(TrafficExportFormat.rockxySession.limitationNote == nil)
        #expect(TrafficExportFormat.har.privacyNote.contains("can include"))
        #expect(!TrafficExportFormat.har.privacyNote.contains("exactly"))
        #expect(TrafficExportFormat.openAPIYAML.subtitle.contains("eligible HTTP requests"))
        #expect(TrafficExportFormat.openAPIHTML.privacyNote.contains("sensitive header"))
    }

    @Test("Export scope sheet keeps the native scalable review contract")
    func sheetKeepsNativeContract() throws {
        let source = try readProjectFile("Rockxy/Views/Export/ExportScopeSheet.swift")

        #expect(source.contains(".pickerStyle(.radioGroup)"))
        #expect(source.contains(".rockxyGlassButtonStyle()"))
        #expect(source.contains(".rockxyGlassButtonStyle(prominent: true)"))
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
        #expect(source.contains(".keyboardShortcut(.defaultAction)"))
        #expect(source.contains("ToolWindowDisplayMetrics"))
        #expect(source.contains("sheetWidth"))
        #expect(source.contains("toolMetrics.formControlHeight"))
        #expect(source.contains("lock.fill"))
        #expect(source.contains("Other traffic will not be included."))

        for identifier in [
            "exportScope.sheet",
            "exportScope.header",
            "exportScope.picker",
            "exportScope.restriction",
            "exportScope.privacy",
            "exportScope.cancelButton",
            "exportScope.exportButton",
        ] {
            #expect(source.contains(identifier), "missing accessibility identifier \(identifier)")
        }
        #expect(source.contains(#"exportScope.option.\(scope.rawValue)"#))

        #expect(!source.contains("Circle()"))
        #expect(!source.contains(".buttonStyle(.plain)"))
        #expect(!source.contains("Color(red:"))
        #expect(!source.contains(".textCase(.uppercase)"))
    }

    // MARK: Private

    private func readProjectFile(_ relativePath: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.path != "/" {
            url.deleteLastPathComponent()
        }
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
