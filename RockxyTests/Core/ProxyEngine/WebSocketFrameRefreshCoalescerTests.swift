import Foundation
import NIOCore
import NIOEmbedded
import NIOWebSocket
@testable import Rockxy
import Testing

// MARK: - FrameRefreshInbox

private final class FrameRefreshInbox: @unchecked Sendable {
    // MARK: Internal

    var count: Int {
        lock.withLock { publications.count }
    }

    var isEmpty: Bool {
        lock.withLock { publications.isEmpty }
    }

    func enqueue(_ publication: @escaping WebSocketFrameRefreshCoalescer.Publication) {
        lock.withLock { publications.append(publication) }
    }

    @MainActor
    func drain() {
        let batch = lock.withLock {
            let batch = publications
            publications.removeAll()
            return batch
        }
        batch.forEach { $0() }
    }

    // MARK: Private

    private let lock = NSLock()
    private var publications: [WebSocketFrameRefreshCoalescer.Publication] = []
}

// MARK: - WebSocketFrameRefreshCoalescerTests

@MainActor
struct WebSocketFrameRefreshCoalescerTests {
    @Test("Ten thousand concurrent frame signals enqueue one refresh and allow the next window")
    func concurrentBurst() {
        let transaction = TestFixtures.makeTransaction(state: .active)
        let inbox = FrameRefreshInbox()
        let coalescer = WebSocketFrameRefreshCoalescer(
            publish: { transaction.webSocketFrameVersion += 1 },
            scheduler: { inbox.enqueue($0) }
        )
        DispatchQueue.concurrentPerform(iterations: 10_000) { _ in coalescer.requestRefresh() }
        #expect(inbox.count == 1)
        #expect(transaction.webSocketFrameVersion == 0)
        inbox.drain()
        #expect(transaction.webSocketFrameVersion == 1)
        coalescer.requestRefresh()
        #expect(inbox.count == 1)
        inbox.drain()
        #expect(transaction.webSocketFrameVersion == 2)
        withExtendedLifetime(coalescer) {}
    }

    @Test("A pending refresh does not retain a disposed handler's publisher or capture")
    func pendingRefreshDoesNotRetainPublisher() {
        var transaction: HTTPTransaction? = TestFixtures.makeTransaction(state: .active)
        weak var observed = transaction
        let inbox = FrameRefreshInbox()
        var coalescer: WebSocketFrameRefreshCoalescer? = WebSocketFrameRefreshCoalescer(
            publish: { [transaction] in transaction?.webSocketFrameVersion += 1 },
            scheduler: { inbox.enqueue($0) }
        )
        transaction = nil
        #expect(observed != nil)
        coalescer?.requestRefresh()
        coalescer = nil
        #expect(observed == nil)
        inbox.drain()
        #expect(inbox.isEmpty)
    }

    @Test("Frame capture retains every byte while inspector invalidations are coalesced")
    func handlerRetainsAllFrames() throws {
        let request = TestFixtures.makeRequest(url: "ws://fixture.invalid/events")
        let connection = WebSocketConnection(upgradeRequest: request)
        let transaction = HTTPTransaction(request: request, state: .active, webSocketConnection: connection)
        let inbox = FrameRefreshInbox()
        let channel = EmbeddedChannel(handler: WebSocketFrameHandler(
            direction: .received, peerChannel: nil, webSocketConnection: connection,
            parentTransaction: transaction, onTransactionComplete: { _ in },
            frameRefreshScheduler: { inbox.enqueue($0) }
        ))
        defer { _ = try? channel.finish() }
        for index in 0 ..< 1_000 {
            var buffer = ByteBufferAllocator().buffer(capacity: 4)
            buffer.writeInteger(UInt32(index))
            _ = try channel.writeInbound(WebSocketFrame(fin: true, opcode: .binary, data: buffer))
        }
        #expect(connection.frameCount == 1_000)
        #expect(inbox.count == 1)
        #expect(transaction.webSocketFrameVersion == 0)
        inbox.drain()
        #expect(transaction.webSocketFrameVersion == 1)
        for (index, frame) in connection.frames.enumerated() {
            var value = UInt32(index).bigEndian
            let expected = withUnsafeBytes(of: &value) { Data($0) }
            #expect(frame.payload == expected)
        }
    }
}
