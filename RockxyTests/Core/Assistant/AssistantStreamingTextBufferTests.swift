@testable import Rockxy
import Testing

struct AssistantStreamingTextBufferTests {
    @Test("Streaming text coalesces rapid deltas before observable UI publication")
    func coalescesRapidDeltas() throws {
        var buffer = AssistantStreamingTextBuffer(startedAt: 0)
        var publicationCount = 0

        for index in 1 ... 1_000 {
            if try buffer.append("x", at: Double(index) / 1_000) {
                publicationCount += 1
            }
        }

        #expect(buffer.text.count == 1_000)
        #expect(buffer.byteCount == 1_000)
        #expect(publicationCount <= 10)
    }

    @Test("Streaming text rejects output beyond the bounded response size")
    func rejectsOversizedOutput() {
        var buffer = AssistantStreamingTextBuffer(startedAt: 0)
        let oversized = String(
            repeating: "x",
            count: AssistantExecutionLimits.maxOutputBytes + 1
        )

        #expect(throws: AssistantProviderError.self) {
            try buffer.append(oversized, at: 1)
        }
    }
}
