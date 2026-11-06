import Foundation
@testable import Rockxy
import Testing

@MainActor
struct CaptureRestartSequencerTests {
    @Test("Restart awaits asynchronous Stop completion before checking and starting")
    func waitsForStop() async {
        var events: [String] = []
        await CaptureRestartSequencer.restart(
            after: {
                events.append("stop:began")
                await Task.yield()
                events.append("stop:finished")
            },
            canStart: { events.append("recheck")
                return true
            },
            start: { events.append("start") }
        )
        #expect(events == ["stop:began", "stop:finished", "recheck", "start"])
    }

    @Test("A failed Stop or intervening Start prevents another listener from starting")
    func checksStateAfterStop() async {
        var canStart = true
        var starts = 0
        await CaptureRestartSequencer.restart(
            after: { await Task.yield()
                canStart = false
            },
            canStart: { canStart },
            start: { starts += 1 }
        )
        #expect(starts == 0)
    }
}
