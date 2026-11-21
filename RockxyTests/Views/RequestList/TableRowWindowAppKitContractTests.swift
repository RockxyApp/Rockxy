import AppKit
@testable import Rockxy
import Testing

// MARK: - TableRowWindowAppKitContractTests

/// The measured AppKit boundary for removing rows from the head of a table and inserting at
/// its tail in one batch, kept as evidence after the row-window fast path that used it was
/// removed (see the reload branch in `RequestTableView.updateNSView`).
///
/// With `removeRows` and `insertRows` inside one `beginUpdates`/`endUpdates` while the data
/// source already reports the final row count, AppKit accepts a batch that nets the same size
/// or larger and aborts the process on one that nets smaller. Measured on a real
/// `NSTableView`: removing 140 and appending 100 exits 133, and so does removing 6 and
/// appending 5; 100/100 and 100/140 are accepted. The refused side is not driven here because
/// it takes the test host down instead of failing an expectation.
///
/// Open experiment: staging the data source's row count across two update transactions might
/// make a net-shrinking batch legal. Try it in `Harness` before touching the table.
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
        // Only the accepted side of the boundary is driven; see the suite documentation.
        for (removedHead, appended) in [(100, 100), (100, 140), (0, 1), (0, 10)] {
            let harness = Harness(startingRows: 500)
            harness.applyWindow(removedHead: removedHead, appended: appended)

            #expect(harness.tableView.numberOfRows == harness.rows.count)
            harness.expectEveryRowResolvesToItsModel()
        }
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
        /// that makes the count already final when AppKit sees the insert and remove.
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
