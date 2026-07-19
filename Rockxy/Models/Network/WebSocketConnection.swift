import Foundation

/// Thread-safe container for a WebSocket connection's upgrade request and captured frames.
/// Marked `@unchecked Sendable` because frame access is serialized through an `NSLock`.
final class WebSocketConnection: @unchecked Sendable {
    // MARK: Lifecycle

    init(upgradeRequest: HTTPRequestData, frames: [WebSocketFrameData] = []) {
        self.upgradeRequest = upgradeRequest
        self._frames = frames
        self._totalPayloadSize = frames.reduce(0) { $0 + $1.payload.count }
    }

    // MARK: Internal

    let upgradeRequest: HTTPRequestData

    var totalPayloadSize: Int {
        lock.withLock { _totalPayloadSize }
    }

    var frames: [WebSocketFrameData] {
        lock.withLock { _frames }
    }

    var frameCount: Int {
        lock.withLock { _frames.count }
    }

    var sentFrames: [WebSocketFrameData] {
        lock.withLock { _frames.filter { $0.direction == .sent } }
    }

    var receivedFrames: [WebSocketFrameData] {
        lock.withLock { _frames.filter { $0.direction == .received } }
    }

    func addFrame(_ frame: WebSocketFrameData) {
        lock.withLock {
            _frames.append(frame)
            _totalPayloadSize += frame.payload.count
        }
    }

    @discardableResult
    func addFrame(_ frame: WebSocketFrameData, maximumTotalPayloadSize: Int) -> Bool {
        lock.withLock {
            guard frame.payload.count <= maximumTotalPayloadSize,
                  _totalPayloadSize <= maximumTotalPayloadSize - frame.payload.count else
            {
                return false
            }
            _frames.append(frame)
            _totalPayloadSize += frame.payload.count
            return true
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var _frames: [WebSocketFrameData]
    private var _totalPayloadSize: Int
}
