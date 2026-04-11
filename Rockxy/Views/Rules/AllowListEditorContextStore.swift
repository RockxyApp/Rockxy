import Foundation

// MARK: - AllowListEditorContextStore

/// Cross-window state handoff for allow list rule creation.
/// The coordinator sets a pending context; the Allow List window consumes it on appear.
@MainActor @Observable
final class AllowListEditorContextStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = AllowListEditorContextStore()

    private(set) var pendingContext: AllowListEditorContext?
    var contextVersion: UInt64 = 0

    func setPending(_ context: AllowListEditorContext) {
        pendingContext = context
        contextVersion &+= 1
    }

    func consumePending() -> AllowListEditorContext? {
        guard let context = pendingContext else {
            return nil
        }
        pendingContext = nil
        return context
    }
}
