import Foundation

// MARK: - BreakpointEditorContextStore

/// Cross-window state handoff for breakpoint rule creation.
/// The coordinator sets a pending context; the Breakpoint Rules window consumes it on appear.
@MainActor @Observable
final class BreakpointEditorContextStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = BreakpointEditorContextStore()

    private(set) var pendingContext: BreakpointEditorContext?
    var contextVersion: UInt64 = 0

    func setPending(_ context: BreakpointEditorContext) {
        pendingContext = context
        contextVersion &+= 1
    }

    func consumePending() -> BreakpointEditorContext? {
        guard let context = pendingContext else {
            return nil
        }
        pendingContext = nil
        return context
    }
}
