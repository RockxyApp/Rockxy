import Foundation
@testable import Rockxy
import Testing

@Suite("Babylon capture protocol")
struct BabylonCaptureProtocolTests {
    @Test("Protocol limits preserve 50 MiB body encoding headroom")
    func protocolLimits() {
        #expect(BabylonCaptureProtocol.maximumFrameSize == 75_497_472)
        #expect(BabylonCaptureProtocol.maximumDecompressedSize == 100_663_296)
        #expect(BabylonCaptureProtocol.maximumCapturedBodySize == 52_428_800)
    }

    @Test("Fragmented and coalesced 64-bit frames round trip")
    func fragmentedAndCoalescedFrames() throws {
        let first = Data("first".utf8)
        let second = Data(repeating: 0x2A, count: 1_024)
        let firstFrame = try BabylonFrameAccumulator.frame(first)
        let secondFrame = try BabylonFrameAccumulator.frame(second)
        let combined = firstFrame + secondFrame
        var accumulator = BabylonFrameAccumulator()
        var decoded: [Data] = []

        for byte in combined {
            decoded += try accumulator.append(Data([byte]))
        }

        #expect(decoded == [first, second])
    }

    @Test("Oversized declared frame is rejected before payload allocation")
    func oversizedDeclaredFrame() {
        var declaredLength = UInt64(BabylonCaptureProtocol.maximumFrameSize + 1).bigEndian
        let header = Data(bytes: &declaredLength, count: MemoryLayout<UInt64>.size)
        var accumulator = BabylonFrameAccumulator()

        #expect(throws: BabylonCaptureProtocolError.frameTooLarge) {
            try accumulator.append(header)
        }
    }

    @Test("Fixed secure frame fixture authenticates and decodes")
    func secureFrameGoldenFixture() throws {
        let content = try BabylonCaptureProtocol.encoder.encode(BabylonAcknowledgement(messageID: "accepted-message"))
        let payload = BabylonPayloadEnvelope(messageType: .ack, sentAt: 1_721_234_567, content: content)
        let encoded = try BabylonSecureFrameCodec.encodeFrame(
            payload: payload,
            messageID: "fixture-message",
            sessionID: "fixture-session",
            clientID: "fixture-client",
            sequence: 7,
            pairingToken: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            nonceData: Data(0 ..< 12)
        )

        let (frame, decoded) = try BabylonSecureFrameCodec.decodeFrame(
            encoded,
            pairingToken: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        )

        #expect(frame.messageID == "fixture-message")
        #expect(frame.sequence == 7)
        #expect(decoded.messageType == .ack)
        #expect(decoded.sentAt == 1_721_234_567)
        let repeatedEncoding = try BabylonSecureFrameCodec.encodeFrame(
            payload: payload,
            messageID: "fixture-message",
            sessionID: "fixture-session",
            clientID: "fixture-client",
            sequence: 7,
            pairingToken: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            nonceData: Data(0 ..< 12)
        )
        #expect(encoded == repeatedEncoding)
    }

    @Test("Golden fixture matches the Babylon client codec")
    func clientCompatibilityFixture() throws {
        let expectedFixture =
            "eyJjaXBoZXJ0ZXh0Ijoic3ZEZXJ0XC9IMTQxbm9SeDJNajV5engyNTViU25qN08rYW9WbnRjdXd1T0pYXC9keTFKNEp1clJmSkMz" +
            "V1diMWE3NEFFMythSkhHdW5jUmswMkxjVG1LV0dBY3g0ckJQemJwMktvdEZhNlFSVThwUDl4bUtDNDhcL0IyajNHT2ZBV0JDdz09" +
            "IiwiY2xpZW50SUQiOiJjb20uZXhhbXBsZS5wcm90b2NvbC10ZXN0cy1kZXZpY2UiLCJjb21wcmVzc2lvbiI6Imd6aXAiLCJtZXNz" +
            "YWdlSUQiOiJkZXRlcm1pbmlzdGljLW1lc3NhZ2UiLCJub25jZSI6IkFBRUNBd1FGQmdjSUNRb0wiLCJwcm90b2NvbFZlcnNpb24i" +
            "OjEsInNlcXVlbmNlIjo3LCJzZXNzaW9uSUQiOiIxMTExMTExMS0yMjIyLTMzMzMtNDQ0NC01NTU1NTU1NTU1NTUiLCJ0YWciOiJ5" +
            "b3FQN01HOTB1ZTRWUDFkYTBLVzd3PT0ifQ=="

        let encoded = try #require(Data(base64Encoded: expectedFixture))
        let (frame, payload) = try BabylonSecureFrameCodec.decodeFrame(
            encoded,
            pairingToken: String(repeating: "a", count: 64)
        )

        #expect(frame.messageID == "deterministic-message")
        #expect(frame.sessionID == "11111111-2222-3333-4444-555555555555")
        #expect(frame.clientID == "com.example.protocol-tests-device")
        #expect(frame.sequence == 7)
        #expect(payload.messageType == .traffic)
        #expect(payload.sentAt == 1_725_000_000)
        #expect(payload.content == Data("deterministic-content".utf8))
    }

    @Test("Ambiguous or oversized frame identifiers are rejected")
    func invalidIdentifiers() {
        let payload = BabylonPayloadEnvelope(messageType: .heartbeat, sentAt: 1, content: Data("{}".utf8))

        #expect(throws: BabylonCaptureProtocolError.invalidIdentity) {
            try BabylonSecureFrameCodec.encodeFrame(
                payload: payload,
                sessionID: "session",
                clientID: "ambiguous:client",
                sequence: 1,
                pairingToken: "token"
            )
        }
        #expect(throws: BabylonCaptureProtocolError.invalidIdentity) {
            try BabylonSecureFrameCodec.encodeFrame(
                payload: payload,
                messageID: String(repeating: "m", count: BabylonCaptureProtocol.maximumMessageIDSize + 1),
                sessionID: "session",
                clientID: "client",
                sequence: 1,
                pairingToken: "token"
            )
        }
    }

    @Test("Tampered ciphertext and wrong token are rejected")
    func tamperAndWrongToken() throws {
        let payload = BabylonPayloadEnvelope(messageType: .heartbeat, sentAt: 1, content: Data("{}".utf8))
        let encoded = try BabylonSecureFrameCodec.encodeFrame(
            payload: payload,
            sessionID: "session",
            clientID: "client",
            sequence: 1,
            pairingToken: "correct-token",
            nonceData: Data(repeating: 1, count: 12)
        )
        var frame = try BabylonCaptureProtocol.decoder.decode(BabylonSecureFrame.self, from: encoded)
        var ciphertext = frame.ciphertext
        ciphertext[ciphertext.startIndex] ^= 0x01
        frame = BabylonSecureFrame(
            protocolVersion: frame.protocolVersion,
            messageID: frame.messageID,
            sessionID: frame.sessionID,
            clientID: frame.clientID,
            sequence: frame.sequence,
            compression: frame.compression,
            nonce: frame.nonce,
            ciphertext: ciphertext,
            tag: frame.tag
        )
        let tampered = try BabylonCaptureProtocol.encoder.encode(frame)

        #expect(throws: BabylonCaptureProtocolError.authenticationFailed) {
            try BabylonSecureFrameCodec.decodeFrame(tampered, pairingToken: "correct-token")
        }
        #expect(throws: BabylonCaptureProtocolError.authenticationFailed) {
            try BabylonSecureFrameCodec.decodeFrame(encoded, pairingToken: "wrong-token")
        }
    }

    @Test("Replay guard rejects old sequences and duplicate IDs")
    func replayGuard() throws {
        var guardState = BabylonMessageReplayGuard(maximumRememberedMessageIDs: 2)
        #expect(try guardState.accept(messageID: "one", sequence: 1) == .newMessage)
        #expect(try guardState.accept(messageID: "two", sequence: 2) == .newMessage)
        #expect(try guardState.accept(messageID: "two", sequence: 2) == .duplicate)

        #expect(throws: BabylonCaptureProtocolError.replayedSequence) {
            try guardState.accept(messageID: "three", sequence: 2)
        }
        #expect(throws: BabylonCaptureProtocolError.duplicateMessage) {
            try guardState.accept(messageID: "two", sequence: 3)
        }
    }

    @Test("GZIP decoding enforces output cap")
    func gzipOutputCap() throws {
        let original = Data(repeating: 0x41, count: 4_096)
        let compressed = try #require(BabylonGzipCodec.gzip(original))

        #expect(BabylonGzipCodec.gunzip(compressed, maximumOutputSize: 4_095) == nil)
        #expect(BabylonGzipCodec.gunzip(compressed, maximumOutputSize: 4_096) == original)
    }
}
