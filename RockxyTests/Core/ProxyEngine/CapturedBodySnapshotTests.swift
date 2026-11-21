import Foundation
import NIOCore
@testable import Rockxy
import Testing

struct CapturedBodySnapshotTests {
    @Test("Capture snapshots own only readable bytes after the buffer changes or is released")
    func ownsReadableBytes() throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 32)
        buffer.writeString("prefix-body-tail")
        buffer.moveReaderIndex(forwardBy: 7)
        buffer.moveWriterIndex(to: 11)
        let data = try #require(ProxyHandlerShared.capturedBodyData(buffer))
        #expect(data == Data("body".utf8))
        #expect(buffer.readerIndex == 7)
        #expect(buffer.readableBytes == 4)
        buffer.clear()
        buffer.writeString("replacement")
        #expect(data == Data("body".utf8))
    }

    @Test("Missing and empty capture buffers preserve absent-body semantics")
    func emptyBuffers() {
        #expect(ProxyHandlerShared.capturedBodyData(nil) == nil)
        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("consumed")
        buffer.moveReaderIndex(to: buffer.writerIndex)
        #expect(ProxyHandlerShared.capturedBodyData(buffer) == nil)
    }

    @Test("Large binary captures retain exact bytes")
    func largeBinaryCapture() throws {
        let expected = Data((0 ..< 1_048_577).map { UInt8(truncatingIfNeeded: $0) })
        var buffer = ByteBufferAllocator().buffer(capacity: expected.count)
        buffer.writeBytes(expected)
        let data = try #require(ProxyHandlerShared.capturedBodyData(buffer))
        #expect(data == expected)
    }
}
