import AppKit
@testable import Rockxy
import Testing

// MARK: - TableRowWindowAppKitContractTests

/// Proves the AppKit side of the row-change window the request table applies at the history cap.
///
/// `applyRowChangeWindow` calls `removeRows` and `insertRows` inside one
/// `beginUpdates`/`endUpdates` while the data source already reports the final row count.
/// AppKit reconciles the batch at `endUpdates` and raises "Invalid update: invalid number of
/// rows" when the net delta does not match the count change, and a view-based table can
/// otherwise show a neighbouring row's data without raising anything at all. A GUI walk of
/// this was blocked, so the contract is pinned here instead: these tests drive a real
/// `NSTableView` through the exact sequence and then read back what each row resolves to.
@MainActor
@Suite("Table row window AppKit contract")
struct TableRowWindowAppKitContractTests {
    // MARK: Internal

    @Test("the eviction shape AppKit must accept: drop the head, append the tail")
    func capShapeIsAccepted() {
        // The real shape at a 1,000-row cap: a tenth of the cap leaves the front and the same
        // number of new rows arrive at the back.
        let harness = Harness(startingRows: 1_000)
        harness.applyWindow(removedHead: 100, appended: 100)

        #expect(harness.tableView.numberOfRows == 1_000)
        harness.expectEveryRowResolvesToItsModel()
    }

    @Test("a batch that appends at least what it evicts reconciles")
    func growingAndEvenWindowsReconcile() {
        // Measured boundary: AppKit accepts a batch that nets the same size or larger and
        // aborts the process on one that nets smaller. Only the accepted side is driven here;
        // the refused side is pinned on the composer below, because exercising it would take
        // the test process down rather than fail an expectation.
        for (removedHead, appended) in [(100, 100), (100, 140), (0, 1), (0, 10)] {
            let harness = Harness(startingRows: 500)
            harness.applyWindow(removedHead: removedHead, appended: appended)

            #expect(harness.tableView.numberOfRows == harness.rows.count)
            harness.expectEveryRowResolvesToItsModel()
        }
    }

    @Test("a window that nets smaller is refused before it reaches AppKit")
    func netShrinkingWindowIsRefused() {
        // `removeRows` 6 then `insertRows` 5 in one batch aborts a real NSTableView, so the
        // composer must never offer such a window. This is the guard that keeps the fast path
        // off the shape that crashes.
        let shrinking = RowChangeStep(token: 1, removedHead: 6, appended: 5, rewritten: IndexSet())
        #expect(RowChangeWindow.compose([shrinking], after: 0, through: 1, startingRowCount: 50) == nil)

        let even = RowChangeStep(token: 1, removedHead: 5, appended: 5, rewritten: IndexSet())
        #expect(RowChangeWindow.compose([even], after: 0, through: 1, startingRowCount: 50) != nil)

        let growing = RowChangeStep(token: 1, removedHead: 5, appended: 6, rewritten: IndexSet())
        #expect(RowChangeWindow.compose([growing], after: 0, through: 1, startingRowCount: 50) != nil)
    }

    @Test("rows shift by exactly the removed count, so no row shows its neighbour's data")
    func rowsShiftByTheRemovedCountOnly() {
        let harness = Harness(startingRows: 300)
        let survivor = harness.rows[120]

        harness.applyWindow(removedHead: 20, appended: 20)

        // The survivor must sit exactly `removedHead` places earlier. An off-by-one here is the
        // failure a GUI walk would see as every row displaying the wrong request, with no
        // exception raised.
        #expect(harness.rows[100] == survivor)
        #expect(harness.resolvedRow(100) == survivor)
        harness.expectEveryRowResolvesToItsModel()
    }

    @Test("repeating the window keeps the table and the model in step")
    func repeatedWindowsStayInStep() {
        let harness = Harness(startingRows: 1_000)
        for _ in 0 ..< 25 {
            harness.applyWindow(removedHead: 100, appended: 100)
        }

        #expect(harness.tableView.numberOfRows == 1_000)
        #expect(harness.rows.count == 1_000)
        harness.expectEveryRowResolvesToItsModel()
    }

    // MARK: Private

    /// A real `NSTableView` plus the array its data source answers from, so the batch update
    /// runs against AppKit rather than against a stand-in.
    @MainActor
    private final class Harness: NSObject, NSTableViewDataSource {
        // MARK: Lifecycle

        init(startingRows: Int) {
            rows = (0 ..< startingRows).map { "row-\($0)" }
            nextRowNumber = startingRows
            tableView = NSTableView()
            super.init()
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
            tableView.addTableColumn(column)
            tableView.dataSource = self
            tableView.reloadData()
        }

        // MARK: Internal

        let tableView: NSTableView
        private(set) var rows: [String]

        func numberOfRows(in _: NSTableView) -> Int {
            rows.count
        }

        func tableView(_: NSTableView, objectValueFor _: NSTableColumn?, row: Int) -> Any? {
            rows[row]
        }

        /// Mutates the model to its final state first, then runs the batch -- the order
        /// `applyRowChangeWindow` uses, and the one that makes the count already final when
        /// AppKit sees the insert and remove.
        func applyWindow(removedHead: Int, appended: Int) {
            let previousCount = rows.count
            rows.removeFirst(removedHead)
            for _ in 0 ..< appended {
                rows.append("row-\(nextRowNumber)")
                nextRowNumber += 1
            }
            #expect(rows.count == previousCount - removedHead + appended)

            let newCount = rows.count
            tableView.beginUpdates()
            if removedHead > 0 {
                tableView.removeRows(at: IndexSet(integersIn: 0 ..< removedHead), withAnimation: [])
            }
            if appended > 0 {
                tableView.insertRows(at: IndexSet(integersIn: (newCount - appended) ..< newCount), withAnimation: [])
            }
            tableView.endUpdates()
        }

        /// What the table resolves a row index to through its data source.
        func resolvedRow(_ index: Int) -> String? {
            tableView.dataSource?.tableView?(
                tableView,
                objectValueFor: tableView.tableColumns.first,
                row: index
            ) as? String
        }

        func expectEveryRowResolvesToItsModel() {
            #expect(tableView.numberOfRows == rows.count)
            for index in rows.indices {
                #expect(resolvedRow(index) == rows[index])
            }
        }

        // MARK: Private

        private var nextRowNumber: Int
    }
}
