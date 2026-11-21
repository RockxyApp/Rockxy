import Foundation

/// Bounds inspector invalidations while every frame is still captured and relayed immediately.
final class WebSocketFrameRefreshCoalescer: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        publish: @escaping Publication,
        scheduler: @escaping Scheduler = { publication in
            WebSocketFrameRefreshCoalescer.scheduleOnMainQueue(publication)
        }
    ) {
        self.publish = publish
        self.scheduler = scheduler
    }

    // MARK: Internal

    typealias Publication = @MainActor @Sendable () -> Void
    typealias Scheduler = @Sendable (@escaping Publication) -> Void

    static func scheduleOnMainQueue(_ publication: @escaping Publication) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            MainActor.assumeIsolated { publication() }
        }
    }

    func requestRefresh() {
        let shouldSchedule = lock.withLock {
            guard !isPending else {
                return false
            }
            isPending = true
            return true
        }
        guard shouldSchedule else {
            return
        }
        scheduler { [weak self] in
            guard let self else {
                return
            }
            self.lock.withLock { self.isPending = false }
            self.publish()
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var isPending = false
    private let publish: Publication
    private let scheduler: Scheduler
}
