import Foundation
@testable import Rockxy
import Testing

// MARK: - WebSocketFrameListTests

struct WebSocketFrameListTests {
    // MARK: Internal

    @Test("Frames arriving on a live connection keep the selection and the filtered order")
    func liveAppendsKeepPlace() {
        let connection = WebSocketConnection(upgradeRequest: TestFixtures.makeRequest(url: "wss://ws.example.com/live"))
        for index in 0 ..< 20 {
            connection.addFrame(frame(index, direction: index.isMultiple(of: 2) ? .sent : .received))
        }
        let firstPass = WebSocketFrameList.visibleFrames(connection.frames, direction: .received, query: "")
        let selected = firstPass[3].id

        for index in 20 ..< 5_000 {
            connection.addFrame(frame(index, direction: index.isMultiple(of: 2) ? .sent : .received))
        }
        let secondPass = WebSocketFrameList.visibleFrames(connection.frames, direction: .received, query: "")

        #expect(Array(secondPass.prefix(firstPass.count)).map(\.id) == firstPass.map(\.id))
        #expect(secondPass.allSatisfy { $0.direction == .received })
        #expect(WebSocketFrameList.reconciledSelection(selected, visible: secondPass) == selected)
    }

    @Test("A selection hidden by a new filter is cleared instead of showing a frame the list hides")
    func filteredOutSelectionClears() {
        let frames = (0 ..< 6).map { frame($0, direction: $0.isMultiple(of: 2) ? .sent : .received) }
        let sentSelection = frames[0].id

        let receivedOnly = WebSocketFrameList.visibleFrames(frames, direction: .received, query: "")
        #expect(WebSocketFrameList.reconciledSelection(sentSelection, visible: receivedOnly) == nil)

        let searched = WebSocketFrameList.visibleFrames(frames, direction: nil, query: "frame 4")
        #expect(searched.map(\.id) == [frames[4].id])
        #expect(WebSocketFrameList.reconciledSelection(frames[4].id, visible: searched) == frames[4].id)
        #expect(WebSocketFrameList.reconciledSelection(nil, visible: searched) == nil)
    }

    @Test("Large frames stay searchable within the scan window and keep their full payload")
    func largeFramesStayInspectable() {
        var payload = Data("needle-at-start ".utf8)
        payload.append(Data(repeating: UInt8(ascii: "x"), count: 8 * 1_024 * 1_024))
        payload.append(Data(" needle-at-end".utf8))
        let large = WebSocketFrameData(direction: .received, opcode: .text, payload: payload)

        #expect(WebSocketFrameList.visibleFrames([large], direction: nil, query: "needle-at-start").count == 1)
        // Only the first window is scanned so a huge frame never stalls the list.
        #expect(WebSocketFrameList.visibleFrames([large], direction: nil, query: "needle-at-end").isEmpty)
        #expect(large.payload.count == payload.count)
    }

    // MARK: Private

    private func frame(_ index: Int, direction: FrameDirection) -> WebSocketFrameData {
        WebSocketFrameData(direction: direction, opcode: .text, payload: Data("frame \(index)".utf8))
    }
}
