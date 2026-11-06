import Foundation

/// Holds block-based `NotificationCenter` observations and removes them when it is released.
///
/// `NotificationCenter` keeps a block observation until it is removed by token; it does not
/// drop one because the object that installed it went away. Left installed, every post is
/// still delivered to each dead observation, which for `.scriptConsoleDidAppend` means one
/// main-queue hop and one `Task` per `console.log` from any running script -- a per-request
/// event -- each finding its `self` already nil. So the cost of forgetting is main-thread
/// dispatch that grows with the number of owners ever constructed, not memory.
///
/// The removal lives in this box rather than in the owner's own `deinit` because owners here
/// are `@MainActor` types, and a `deinit` is nonisolated: it cannot read their main-actor
/// stored properties. Holding the box as a `let` sidesteps that without reaching for
/// `nonisolated(unsafe)` -- when the owner is deallocated the box is released, and this
/// `deinit` runs on a type with no isolation to violate.
///
/// Not `Sendable` by design: `keep(_:)` is only ever called from its owner's own isolation,
/// and by the time `deinit` runs nothing else holds a reference.
final class NotificationObserverTokens {
    // MARK: Lifecycle

    deinit {
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
    }

    // MARK: Internal

    func keep(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    // MARK: Private

    private var tokens: [NSObjectProtocol] = []
}
