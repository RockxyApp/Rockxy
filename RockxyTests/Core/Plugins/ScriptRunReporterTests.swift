import Foundation
import os
@testable import Rockxy
import Testing

// MARK: - ScriptRunReporterTests

struct ScriptRunReporterTests {
    @Test("Successes and repeated failures are coalesced; a new failure reason publishes at once")
    func coalescesSuccesses() {
        let clock = TestClock()
        let published = ReportCollector()
        let reporter = ScriptRunReporter(successInterval: 1, now: { clock.now }, sink: { published.append($0) })

        reporter.reportSuccess(pluginID: "a", phase: .request)
        reporter.reportSuccess(pluginID: "a", phase: .request)
        reporter.reportSuccess(pluginID: "a", phase: .response)
        reporter.reportSuccess(pluginID: "b", phase: .request)
        #expect(published.reports.count == 3)

        reporter.reportFailure(pluginID: "a", phase: .request, reason: "JS exception: boom")
        reporter.reportFailure(pluginID: "a", phase: .request, reason: "JS exception: boom")
        #expect(published.reports.count == 4)
        reporter.reportFailure(pluginID: "a", phase: .request, reason: "mock script returned null")
        #expect(published.reports.count == 5)
        #expect(published.reports.last?.outcome == .failed("mock script returned null"))

        // A failure lets the next success through even inside the interval.
        reporter.reportSuccess(pluginID: "a", phase: .request)
        #expect(published.reports.last?.outcome == .succeeded)

        clock.advance(by: 1.5)
        reporter.reportSuccess(pluginID: "b", phase: .request)
        #expect(published.reports.count == 7)
        reporter.reportFailure(pluginID: "a", phase: .request, reason: "mock script returned null")
        #expect(published.reports.count == 8)
    }

    @Test("The editor shows only its own script's latest run")
    @MainActor
    func editorTracksOwnScript() async throws {
        let env = TestFixtures.makeIsolatedPluginEnv()
        defer { env.cleanup() }
        let listViewModel = ScriptingListViewModel(
            pluginManager: env.manager,
            folderStore: ScriptFolderStore(defaults: env.defaults),
            pluginsDirectory: env.pluginsDir
        )
        let pluginID = try #require(await listViewModel.createNewScript(from: .logRequests))
        _ = ScriptEditorSession.shared.consumePending()
        let editor = ScriptEditorViewModel(pluginManager: env.manager, pluginsDirectory: env.pluginsDir)
        await editor.load(intent: .edit(pluginID: pluginID))
        #expect(editor.lastRun == nil)

        let start = Date()
        editor.receiveRunReport(ScriptRunReport(
            pluginID: "someone-else",
            phase: .request,
            outcome: .failed("nope"),
            timestamp: start
        ))
        #expect(editor.lastRun == nil)

        let failure = ScriptRunReport(
            pluginID: pluginID,
            phase: .request,
            outcome: .failed("Plugin script execution timed out"),
            timestamp: start
        )
        editor.receiveRunReport(failure)
        #expect(editor.lastRun == failure)

        editor.receiveRunReport(ScriptRunReport(
            pluginID: pluginID,
            phase: .request,
            outcome: .succeeded,
            timestamp: start.addingTimeInterval(-1)
        ))
        #expect(editor.lastRun == failure)
    }
}

// MARK: - TestClock

private final class TestClock: @unchecked Sendable {
    // MARK: Internal

    var now: Date {
        state.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    // MARK: Private

    private let state = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000))
}

// MARK: - ReportCollector

private final class ReportCollector: @unchecked Sendable {
    // MARK: Internal

    var reports: [ScriptRunReport] {
        state.withLock { $0 }
    }

    func append(_ report: ScriptRunReport) {
        state.withLock { $0.append(report) }
    }

    // MARK: Private

    private let state = OSAllocatedUnfairLock<[ScriptRunReport]>(initialState: [])
}
