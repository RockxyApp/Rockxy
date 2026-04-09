import Foundation

/// Singleton cross-window store for Block rule editor context handoff.
@MainActor @Observable
final class BlockRuleEditorContextStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = BlockRuleEditorContextStore()

    private(set) var pendingContext: BlockRuleEditorContext?
    var contextVersion: UInt64 = 0

    func setPending(_ context: BlockRuleEditorContext) {
        pendingContext = context
        contextVersion &+= 1
    }

    func consumePending() -> BlockRuleEditorContext? {
        guard let context = pendingContext else {
            return nil
        }
        pendingContext = nil
        return context
    }
}
