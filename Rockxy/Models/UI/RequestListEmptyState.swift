import Foundation

// MARK: - RequestListEmptyState

/// The reason the main request list has no visible rows.
///
/// Kept as a pure decision so the overlay copy stays honest about capture, scope, and
/// filter state without embedding branching logic in the view. Resolves to `nil` whenever
/// visible rows exist — the table renders normally in that case.
enum RequestListEmptyState: Equatable {
    /// Candidate requests exist in the current scope but active filters hide every one.
    /// Carries the available (non-TLS-failure) candidate count for truthful copy.
    case filtered(availableCount: Int)
    /// A Library collection (Saved / Pinned / Notes) is scoped but holds no requests.
    case emptyCollection(SidebarScope)
    /// The proxy is starting up; requests cannot arrive yet.
    case proxyStarting
    /// The proxy is closing channels and restoring routing; capture cannot restart yet.
    case proxyStopping
    /// The proxy is stopped and nothing has been captured.
    case proxyStopped
    /// The proxy is running but recording is paused, so new requests are dropped from view.
    case recordingPaused
    /// The proxy listener is running, but ordinary macOS traffic is routed elsewhere.
    case systemRoutingUnavailable
    /// Rockxy is running its private loopback request through the listener.
    case captureChecking
    /// The private loopback request did not complete as a captured transaction.
    case captureUnverified
    /// The Allow List is on without a valid enabled rule, so recording intentionally drops all traffic.
    case allowListCapturesNothing
    /// The proxy is running and recording, but no traffic has arrived yet.
    case waitingForTraffic

    // MARK: Internal

    /// Resolves the empty-state reason from current coordinator state.
    ///
    /// Precedence, top to bottom:
    /// 1. Visible rows → `nil` (table renders).
    /// 2. Empty Library collection (Saved / Pinned / Notes with zero candidates) — takes
    ///    precedence over proxy state so an empty collection never claims "no matches" or
    ///    "waiting for traffic".
    /// 3. Filtered empty — candidates exist (>0) and active filters hide all of them.
    /// 4. Proxy state (starting / stopped / paused / waiting).
    ///
    /// - Parameters:
    ///   - hasVisibleRows: at least one row survives the active scope + filters.
    ///   - availableCount: candidate (non-TLS-failure) request count for the current scope.
    ///   - hasActiveFilters: any workspace filter, advanced rule, signal, focus set, or mute is active.
    ///   - scope: the active sidebar scope.
    ///   - proxyState: the live proxy display state.
    static func resolve(
        hasVisibleRows: Bool,
        availableCount: Int,
        hasActiveFilters: Bool,
        scope: SidebarScope,
        proxyState: ProxyDisplayState,
        isSystemProxyConfigured: Bool = true,
        isSystemRoutingExpected: Bool = true,
        captureHealth: CaptureHealthState = .verified,
        allowListCapturesNothing: Bool = false
    )
        -> RequestListEmptyState?
    {
        if hasVisibleRows {
            return nil
        }

        // An empty Library collection is more specific than proxy state: never report
        // "no matches" or "waiting" when the collection itself is simply empty.
        if scope != .allTraffic, availableCount == 0 {
            return .emptyCollection(scope)
        }

        // Only claim "no matches" when there are genuine candidates to match against.
        if availableCount > 0, hasActiveFilters {
            return .filtered(availableCount: availableCount)
        }

        switch proxyState {
        case .starting:
            return .proxyStarting
        case .stopping:
            return .proxyStopping
        case .stopped:
            return .proxyStopped
        case .paused:
            return .recordingPaused
        case .running:
            if captureHealth == .checking {
                return .captureChecking
            }
            if captureHealth == .failed {
                return .captureUnverified
            }
            if isSystemRoutingExpected, !isSystemProxyConfigured {
                return .systemRoutingUnavailable
            }
            if allowListCapturesNothing {
                return .allowListCapturesNothing
            }
            return .waitingForTraffic
        }
    }
}

// MARK: - RequestListEmptyStateAction

/// The single safe recovery action offered for an empty state, if any. Every action routes
/// through the coordinator so behavior cannot drift from the filter-summary reset.
enum RequestListEmptyStateAction: Equatable {
    case clearFilters
    case showAllTraffic
    case startProxy
    case resumeRecording
    case retrySystemProxy
    case retryCaptureCheck
    case openAllowList
}

// MARK: - RequestListEmptyStateCopy

/// User-facing copy and recovery action for a `RequestListEmptyState`, rendered through a
/// native `ContentUnavailableView`.
struct RequestListEmptyStateCopy: Equatable {
    // MARK: Lifecycle

    init(_ state: RequestListEmptyState) {
        switch state {
        case let .filtered(availableCount):
            title = String(localized: "No Matching Requests", bundle: RockxyLocalization.bundle)
            systemImage = "line.3.horizontal.decrease.circle"
            description = Self.filteredDescription(availableCount: availableCount)
            action = .clearFilters
            actionTitle = String(localized: "Clear Filters", bundle: RockxyLocalization.bundle)
            actionHelp = String(
                localized: "Clear the active filters to show all captured traffic.",
                bundle: RockxyLocalization.bundle
            )

        case let .emptyCollection(scope):
            let collection = Self.collectionCopy(for: scope)
            title = collection.title
            systemImage = collection.systemImage
            description = collection.description
            action = .showAllTraffic
            actionTitle = String(localized: "Show All Traffic", bundle: RockxyLocalization.bundle)
            actionHelp = String(
                localized: "Leave this collection and show all captured traffic.",
                bundle: RockxyLocalization.bundle
            )

        case .proxyStarting:
            title = String(localized: "Starting Proxy", bundle: RockxyLocalization.bundle)
            systemImage = "hourglass"
            description = String(
                localized: "Rockxy is starting the proxy. Captured requests will appear here.",
                bundle: RockxyLocalization.bundle
            )
            action = nil
            actionTitle = nil
            actionHelp = nil

        case .proxyStopping:
            title = String(localized: "Stopping Proxy", bundle: RockxyLocalization.bundle)
            systemImage = "stop.circle"
            description = String(
                localized: "Rockxy is closing active connections and restoring system routing.",
                bundle: RockxyLocalization.bundle
            )
            action = nil
            actionTitle = nil
            actionHelp = nil

        case .proxyStopped:
            title = String(localized: "No Traffic Captured", bundle: RockxyLocalization.bundle)
            systemImage = "network.slash"
            description = String(
                localized: "The proxy is stopped. Start it to begin capturing requests.",
                bundle: RockxyLocalization.bundle
            )
            action = .startProxy
            actionTitle = String(localized: "Start Proxy", bundle: RockxyLocalization.bundle)
            actionHelp = String(
                localized: "Start the proxy to begin capturing network traffic.",
                bundle: RockxyLocalization.bundle
            )

        case .recordingPaused:
            title = String(localized: "Recording Paused", bundle: RockxyLocalization.bundle)
            systemImage = "pause.circle"
            description = String(
                localized: "New requests are not being recorded. Resume recording to capture traffic.",
                bundle: RockxyLocalization.bundle
            )
            action = .resumeRecording
            actionTitle = String(localized: "Resume Recording", bundle: RockxyLocalization.bundle)
            actionHelp = String(
                localized: "Resume recording so new requests are captured.",
                bundle: RockxyLocalization.bundle
            )

        case .systemRoutingUnavailable:
            title = String(localized: "System Traffic Is Not Routed", bundle: RockxyLocalization.bundle)
            systemImage = "arrow.triangle.branch"
            description = String(
                localized: "Rockxy's listener is running, but macOS browser traffic is routed elsewhere. Manually configured apps can still use the listener.",
                bundle: RockxyLocalization.bundle
            )
            action = .retrySystemProxy
            actionTitle = String(localized: "Restore System Routing", bundle: RockxyLocalization.bundle)
            actionHelp = String(
                localized: "Route macOS HTTP and HTTPS traffic through the running Rockxy listener.",
                bundle: RockxyLocalization.bundle
            )

        case .captureChecking:
            title = String(localized: "Checking Capture", bundle: RockxyLocalization.bundle)
            systemImage = "checkmark.arrow.trianglehead.counterclockwise"
            description = String(
                localized: "Rockxy is sending a private loopback request through the listener to verify the capture path.",
                bundle: RockxyLocalization.bundle
            )
            action = nil
            actionTitle = nil
            actionHelp = nil

        case .captureUnverified:
            title = String(localized: "Capture Is Not Verified", bundle: RockxyLocalization.bundle)
            systemImage = "exclamationmark.triangle"
            description = String(
                localized: "The listener is running, but Rockxy's private loopback request did not complete as a captured transaction.",
                bundle: RockxyLocalization.bundle
            )
            action = .retryCaptureCheck
            actionTitle = String(localized: "Run Capture Check", bundle: RockxyLocalization.bundle)
            actionHelp = String(
                localized: "Send another private loopback request through the running listener.",
                bundle: RockxyLocalization.bundle
            )

        case .allowListCapturesNothing:
            title = String(localized: "Allow List Captures Nothing", bundle: RockxyLocalization.bundle)
            systemImage = "line.3.horizontal.decrease.circle"
            description = String(
                localized: "Allow List is on, but no valid enabled rule can match. Traffic is still proxied, but it is not recorded.",
                bundle: RockxyLocalization.bundle
            )
            action = .openAllowList
            actionTitle = String(localized: "Open Allow List", bundle: RockxyLocalization.bundle)
            actionHelp = String(
                localized: "Open Allow List and enable or create a valid rule.",
                bundle: RockxyLocalization.bundle
            )

        case .waitingForTraffic:
            title = String(localized: "Waiting for Requests", bundle: RockxyLocalization.bundle)
            systemImage = "dot.radiowaves.left.and.right"
            description = String(
                localized: "Rockxy is capturing. Send a request through the proxy and it will appear here.",
                bundle: RockxyLocalization.bundle
            )
            action = nil
            actionTitle = nil
            actionHelp = nil
        }
    }

    // MARK: Internal

    let title: String
    let systemImage: String
    let description: String
    let action: RequestListEmptyStateAction?
    let actionTitle: String?
    let actionHelp: String?

    // MARK: Private

    private struct CollectionCopy {
        let title: String
        let systemImage: String
        let description: String
    }

    private static func filteredDescription(availableCount: Int) -> String {
        if availableCount == 1 {
            return String(
                localized: "No requests match the active filters. 1 request is available before filtering.",
                bundle: RockxyLocalization.bundle
            )
        }
        return String(
            localized: "No requests match the active filters. \(availableCount) requests are available before filtering.",
            bundle: RockxyLocalization.bundle
        )
    }

    private static func collectionCopy(for scope: SidebarScope) -> CollectionCopy {
        switch scope {
        case .saved:
            CollectionCopy(
                title: String(localized: "No Saved Requests", bundle: RockxyLocalization.bundle),
                systemImage: "bookmark",
                description: String(
                    localized: "Requests you save appear here. Save a request from its menu to keep it across sessions.",
                    bundle: RockxyLocalization.bundle
                )
            )
        case .pinned:
            CollectionCopy(
                title: String(localized: "No Pinned Requests", bundle: RockxyLocalization.bundle),
                systemImage: "pin",
                description: String(
                    localized: "Pin a request to keep it at hand. Pinned requests appear here.",
                    bundle: RockxyLocalization.bundle
                )
            )
        case .notes:
            CollectionCopy(
                title: String(localized: "No Requests with Notes", bundle: RockxyLocalization.bundle),
                systemImage: "note.text",
                description: String(
                    localized: "Requests with notes appear here. Add a note to a request to track it.",
                    bundle: RockxyLocalization.bundle
                )
            )
        case .allTraffic:
            // Not reachable — `.emptyCollection` is only resolved for Library scopes.
            CollectionCopy(
                title: String(localized: "No Requests", bundle: RockxyLocalization.bundle),
                systemImage: "tray",
                description: String(localized: "No requests to show.", bundle: RockxyLocalization.bundle)
            )
        }
    }
}
