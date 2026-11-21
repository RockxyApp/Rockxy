import Foundation

/// Thread-safe container for a WebSocket connection's upgrade request and captured frames.
/// Marked `@unchecked Sendable` because frame access is serialized through an `NSLock`.
final class WebSocketConnection: @unchecked Sendable {
    // MARK: Lifecycle

    init(upgradeRequest: HTTPRequestData, frames: [WebSocketFrameData] = []) {
        self.upgradeRequest = upgradeRequest
        self._frames = frames
        self._totalPayloadSize = frames.reduce(0) { $0 + $1.payload.count }
        self._sentPayloadSize = frames.reduce(0) { $0 + ($1.direction == .sent ? $1.payload.count : 0) }
        self._receivedPayloadSize = frames.reduce(0) { $0 + ($1.direction == .received ? $1.payload.count : 0) }
        self._sentFrameCount = frames.reduce(0) { $0 + ($1.direction == .sent ? 1 : 0) }
        self._receivedFrameCount = frames.reduce(0) { $0 + ($1.direction == .received ? 1 : 0) }
    }

    // MARK: Internal

    let upgradeRequest: HTTPRequestData

    var totalPayloadSize: Int {
        lock.withLock { _totalPayloadSize }
    }

    /// Payload bytes by direction, kept as running totals so per-connection byte accounting
    /// never has to walk the frame array.
    var sentPayloadSize: Int {
        lock.withLock { _sentPayloadSize }
    }

    var receivedPayloadSize: Int {
        lock.withLock { _receivedPayloadSize }
    }

    var frames: [WebSocketFrameData] {
        lock.withLock { _frames }
    }

    var frameCount: Int {
        lock.withLock { _frames.count }
    }

    /// Frame counts by direction, running totals for the same reason the byte totals are:
    /// `sentFrames`/`receivedFrames` copy the whole frame array under the lock and then filter
    /// it, and the inspector body re-evaluates on every `webSocketFrameVersion` bump, so a
    /// header that only wanted a number walked every captured frame.
    var sentFrameCount: Int {
        lock.withLock { _sentFrameCount }
    }

    var receivedFrameCount: Int {
        lock.withLock { _receivedFrameCount }
    }

    var isCaptureLimitReached: Bool {
        lock.withLock { _isCaptureLimitReached }
    }

    var sentFrames: [WebSocketFrameData] {
        lock.withLock { _frames.filter { $0.direction == .sent } }
    }

    var receivedFrames: [WebSocketFrameData] {
        lock.withLock { _frames.filter { $0.direction == .received } }
    }

    func addFrame(_ frame: WebSocketFrameData) {
        lock.withLock {
            appendLocked(frame)
        }
    }

    /// The only bounded capture entry point. The overload that defaulted `maximumFrameCount`
    /// to `.max` is gone on purpose: the Babylon receiver was its only caller, so a device
    /// streaming small frames reached roughly 5 million of them -- hundreds of MB of per-frame
    /// struct overhead -- before the aggregate byte cap could fire. Every caller now states
    /// both bounds.
    @discardableResult
    func addFrame(
        _ frame: WebSocketFrameData,
        maximumTotalPayloadSize: Int,
        maximumFrameCount: Int
    )
        -> Bool
    {
        lock.withLock {
            guard !_isCaptureLimitReached else {
                return false
            }
            guard _frames.count < maximumFrameCount,
                  frame.payload.count <= maximumTotalPayloadSize,
                  _totalPayloadSize <= maximumTotalPayloadSize - frame.payload.count else
            {
                _isCaptureLimitReached = true
                return false
            }
            appendLocked(frame)
            return true
        }
    }

    func stopCaptureAtLimit() {
        lock.withLock {
            _isCaptureLimitReached = true
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var _frames: [WebSocketFrameData]
    private var _totalPayloadSize: Int
    private var _sentPayloadSize: Int
    private var _receivedPayloadSize: Int
    private var _sentFrameCount: Int
    private var _receivedFrameCount: Int
    private var _isCaptureLimitReached = false

    /// Caller holds `lock`.
    private func appendLocked(_ frame: WebSocketFrameData) {
        _frames.append(frame)
        _totalPayloadSize += frame.payload.count
        // Only accepted frames reach here, so the per-direction totals can never drift from
        // `_frames` on a rejection path.
        switch frame.direction {
        case .sent:
            _sentPayloadSize += frame.payload.count
            _sentFrameCount += 1
        case .received:
            _receivedPayloadSize += frame.payload.count
            _receivedFrameCount += 1
        }
    }
}
