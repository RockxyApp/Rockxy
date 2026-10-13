import Foundation
import Observation

/// Carries a "show this trace" request from the traffic inspector to the Babylon Runtime window,
/// which may not be open yet. The window applies the focus when it appears or when it changes.
@MainActor @Observable
final class BabylonRuntimeNavigation {
    // MARK: Internal

    struct Focus: Equatable {
        let traceID: String
        let stepID: String?
        /// Distinguishes two requests for the same trace, so asking again re-selects it.
        let token = UUID()
    }

    static let shared = BabylonRuntimeNavigation()

    private(set) var pendingFocus: Focus?

    func focus(traceID: String, stepID: String?) {
        pendingFocus = Focus(traceID: traceID, stepID: stepID)
    }

    func consume() -> Focus? {
        defer { pendingFocus = nil }
        return pendingFocus
    }

    /// The event that best represents a focus: the step's start, any event in that step, the
    /// trace's start, then the trace's earliest event. `nil` when nothing for the trace is
    /// retained, so the window shows an honest empty result instead of an unrelated row.
    nonisolated static func eventID(for focus: Focus, in events: [BabylonRuntimeEvent]) -> BabylonRuntimeEvent.ID? {
        let inTrace = events.filter { $0.traceID == focus.traceID }
        if let stepID = focus.stepID {
            let inStep = inTrace.filter { $0.stepID == stepID }
            if let start = inStep.first(where: { $0.kind == .stepStarted }) ?? inStep.first {
                return start.id
            }
        }
        return (inTrace.first { $0.kind == .traceStarted } ?? inTrace.first)?.id
    }
}
