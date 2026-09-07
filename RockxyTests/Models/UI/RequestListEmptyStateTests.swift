@testable import Rockxy
import Testing

// Unit tests for the pure request-list empty-state presentation model.

// MARK: - RequestListEmptyStateTests

struct RequestListEmptyStateTests {
    // MARK: - Nil When Visible

    @Test("Visible rows resolve to nil regardless of every other input")
    func visibleRowsResolveToNil() {
        for scope in [SidebarScope.allTraffic, .saved, .pinned, .notes] {
            for proxyState in [ProxyDisplayState.starting, .running, .paused, .stopped] {
                let state = RequestListEmptyState.resolve(
                    hasVisibleRows: true,
                    availableCount: 0,
                    hasActiveFilters: true,
                    scope: scope,
                    proxyState: proxyState
                )
                #expect(state == nil)
            }
        }
    }

    // MARK: - Filtered Empty

    @Test("Candidates plus active filters with no visible rows resolves to filtered")
    func filteredEmptyResolves() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 12,
            hasActiveFilters: true,
            scope: .allTraffic,
            proxyState: .running
        )

        #expect(state == .filtered(availableCount: 12))
    }

    @Test("Filtered state offers the Clear Filters action")
    func filteredActionIsClearFilters() {
        let copy = RequestListEmptyStateCopy(.filtered(availableCount: 3))
        #expect(copy.action == .clearFilters)
        #expect(copy.actionTitle != nil)
    }

    @Test("Filtered copy pluralizes the available count")
    func filteredCopyPluralizes() {
        let single = RequestListEmptyStateCopy(.filtered(availableCount: 1))
        #expect(single.description.contains("1 request is available"))

        let plural = RequestListEmptyStateCopy(.filtered(availableCount: 7))
        #expect(plural.description.contains("7 requests are available"))
    }

    @Test("No candidates never reports no-matches even with active filters")
    func noCandidatesNeverFiltered() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: true,
            scope: .allTraffic,
            proxyState: .running
        )

        #expect(state == .waitingForTraffic)
    }

    @Test("Candidates present but no active filters falls through to proxy state")
    func candidatesWithoutFiltersFallThrough() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 5,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .stopped
        )

        #expect(state == .proxyStopped)
    }

    // MARK: - Empty Library Collection

    @Test("Empty Saved / Pinned / Notes collections resolve to emptyCollection")
    func emptyCollectionResolves() {
        for scope in [SidebarScope.saved, .pinned, .notes] {
            let state = RequestListEmptyState.resolve(
                hasVisibleRows: false,
                availableCount: 0,
                hasActiveFilters: true,
                scope: scope,
                proxyState: .running
            )
            #expect(state == .emptyCollection(scope))
        }
    }

    @Test("Empty collection takes precedence over every proxy state")
    func emptyCollectionBeatsProxyState() {
        for proxyState in [ProxyDisplayState.starting, .running, .paused, .stopped] {
            let state = RequestListEmptyState.resolve(
                hasVisibleRows: false,
                availableCount: 0,
                hasActiveFilters: false,
                scope: .saved,
                proxyState: proxyState
            )
            #expect(state == .emptyCollection(.saved))
        }
    }

    @Test("Library collection with hidden candidates reports filtered, not empty")
    func collectionWithCandidatesIsFiltered() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 4,
            hasActiveFilters: true,
            scope: .pinned,
            proxyState: .running
        )

        #expect(state == .filtered(availableCount: 4))
    }

    @Test("Empty collection offers the Show All Traffic action with collection-specific copy")
    func emptyCollectionActionAndCopy() {
        let saved = RequestListEmptyStateCopy(.emptyCollection(.saved))
        #expect(saved.action == .showAllTraffic)
        #expect(saved.title == "No Saved Requests")

        let pinned = RequestListEmptyStateCopy(.emptyCollection(.pinned))
        #expect(pinned.title == "No Pinned Requests")

        let notes = RequestListEmptyStateCopy(.emptyCollection(.notes))
        #expect(notes.title == "No Requests with Notes")
    }

    // MARK: - Proxy States

    @Test("Proxy starting resolves with no action")
    func proxyStartingHasNoAction() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .starting
        )
        #expect(state == .proxyStarting)
        #expect(RequestListEmptyStateCopy(.proxyStarting).action == nil)
    }

    @Test("Proxy stopped resolves to Start Proxy action")
    func proxyStoppedAction() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .stopped
        )
        #expect(state == .proxyStopped)
        #expect(RequestListEmptyStateCopy(.proxyStopped).action == .startProxy)
    }

    @Test("Recording paused resolves to Resume Recording action")
    func recordingPausedAction() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .paused
        )
        #expect(state == .recordingPaused)
        #expect(RequestListEmptyStateCopy(.recordingPaused).action == .resumeRecording)
    }

    @Test("Running proxy with no traffic waits without an action")
    func runningWaitsForTraffic() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .running
        )
        #expect(state == .waitingForTraffic)
        #expect(RequestListEmptyStateCopy(.waitingForTraffic).action == nil)
    }

    @Test("Running proxy reports missing system routing before claiming capture")
    func runningWithoutRouting() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .running,
            isSystemProxyConfigured: false,
            captureHealth: .verified
        )

        #expect(state == .systemRoutingUnavailable)
        #expect(RequestListEmptyStateCopy(.systemRoutingUnavailable).action == .retrySystemProxy)
    }

    @Test("Deliberate manual routing can wait for app traffic without a false error")
    func deliberateManualRoutingWaitsForTraffic() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .running,
            isSystemProxyConfigured: false,
            isSystemRoutingExpected: false,
            captureHealth: .verified
        )

        #expect(state == .waitingForTraffic)
    }

    @Test("Capture check failure outranks a generic waiting state")
    func captureCheckFailure() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .running,
            isSystemProxyConfigured: true,
            captureHealth: .failed
        )

        #expect(state == .captureUnverified)
        #expect(RequestListEmptyStateCopy(.captureUnverified).action == .retryCaptureCheck)
    }

    @Test("Active empty Allow List explains intentional record filtering")
    func allowListCapturesNothing() {
        let state = RequestListEmptyState.resolve(
            hasVisibleRows: false,
            availableCount: 0,
            hasActiveFilters: false,
            scope: .allTraffic,
            proxyState: .running,
            isSystemProxyConfigured: true,
            captureHealth: .verified,
            allowListCapturesNothing: true
        )

        #expect(state == .allowListCapturesNothing)
        #expect(RequestListEmptyStateCopy(.allowListCapturesNothing).action == .openAllowList)
    }
}
