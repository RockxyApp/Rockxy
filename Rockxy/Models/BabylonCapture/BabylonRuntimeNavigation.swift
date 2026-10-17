import Foundation
import Observation

/// Carries a "show this trace" request from the traffic inspector to the Babylon Runtime window,
/// which may not be open yet. The window applies the focus when it appears or when it changes.
@MainActor @Observable
final class BabylonRuntimeNavigation {
    struct Focus: Equatable {
        // MARK: Lifecycle

        init(sourceClientID: String? = nil, sessionID: String? = nil, traceID: String, stepID: String?) {
            self.sourceClientID = sourceClientID
            self.sessionID = sessionID
            self.traceID = traceID
            self.stepID = stepID
        }

        // MARK: Internal

        let sourceClientID: String?
        let sessionID: String?
        let traceID: String
        let stepID: String?
        /// Distinguishes two requests for the same trace, so asking again re-selects it.
        let token = UUID()
    }

    static let shared = BabylonRuntimeNavigation()

    private(set) var pendingFocus: Focus?

    /// The event that best represents a focus: the step's start, any event in that step, the
    /// trace's start, then the trace's earliest event. `nil` when nothing for the trace is
    /// retained, so the window shows an honest empty result instead of an unrelated row.
    nonisolated static func eventID(for focus: Focus, in events: [BabylonRuntimeEvent]) -> BabylonRuntimeEvent.ID? {
        let inTrace = events.filter {
            $0.traceID == focus.traceID
                && (focus.sourceClientID == nil || $0.source.clientID == focus.sourceClientID)
                && (focus.sessionID == nil || $0.sessionID == focus.sessionID)
        }
        if let stepID = focus.stepID {
            let inStep = inTrace.filter { $0.stepID == stepID }
            if let start = inStep.first(where: { $0.kind == .stepStarted }) ?? inStep.first {
                return start.id
            }
        }
        return (inTrace.first { $0.kind == .traceStarted } ?? inTrace.first)?.id
    }

    nonisolated static func selectedVisibleEvent(
        for selection: BabylonRuntimeEvent.ID?,
        in visibleEvents: [BabylonRuntimeEvent]
    )
        -> BabylonRuntimeEvent?
    {
        guard let selection else {
            return nil
        }
        return visibleEvents.first { $0.id == selection }
    }

    nonisolated static func reconciledSelection(
        _ selection: BabylonRuntimeEvent.ID?,
        visibleIDs: [BabylonRuntimeEvent.ID]
    )
        -> BabylonRuntimeEvent.ID?
    {
        guard let selection else {
            return nil
        }
        return visibleIDs.contains(selection) ? selection : visibleIDs.first
    }

    func focus(sourceClientID: String? = nil, sessionID: String? = nil, traceID: String, stepID: String?) {
        pendingFocus = Focus(
            sourceClientID: sourceClientID,
            sessionID: sessionID,
            traceID: traceID,
            stepID: stepID
        )
    }

    func clearPendingFocus() {
        pendingFocus = nil
    }
}
