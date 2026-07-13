import CryptoKit
import Foundation
@testable import Rockxy
import Testing

@Suite("Nearby transfer protocol")
struct RockxyNearbyTransferProtocolTests {
    @Test
    func fragmentedFramesRoundTrip() throws {
        let first = Data("first".utf8)
        let second = Data(repeating: 0x2A, count: 1_024)
        let combined = try RockxyNearbyFrameAccumulator.frame(first)
            + RockxyNearbyFrameAccumulator.frame(second)

        var accumulator = RockxyNearbyFrameAccumulator()
        var frames: [Data] = []
        for byte in combined {
            frames += try accumulator.append(Data([byte]))
        }

        #expect(frames == [first, second])
    }

    @Test
    func pairingKeysMatchAndPayloadIsAuthenticated() throws {
        let sender = P256.KeyAgreement.PrivateKey()
        let receiver = P256.KeyAgreement.PrivateKey()
        let transferID = UUID().uuidString

        let senderKeys = try RockxyNearbyPairingCrypto.deriveKeys(
            privateKey: sender,
            peerPublicKeyData: receiver.publicKey.x963Representation,
            transferID: transferID
        )
        let receiverKeys = try RockxyNearbyPairingCrypto.deriveKeys(
            privateKey: receiver,
            peerPublicKeyData: sender.publicKey.x963Representation,
            transferID: transferID
        )

        #expect(senderKeys.verificationCode == receiverKeys.verificationCode)
        let payload = Data("sensitive local session".utf8)
        let sealed = try RockxyNearbyPairingCrypto.seal(payload, using: senderKeys.encryptionKey)
        #expect(try RockxyNearbyPairingCrypto.open(sealed, using: receiverKeys.encryptionKey) == payload)

        var tampered = sealed
        tampered[tampered.startIndex] ^= 0x01
        #expect(throws: RockxyNearbyTransferError.self) {
            try RockxyNearbyPairingCrypto.open(tampered, using: receiverKeys.encryptionKey)
        }
    }

    @Test
    func oversizedFrameIsRejected() {
        let payload = Data(repeating: 0, count: RockxyNearbyTransferProtocol.maximumFrameSize + 1)
        #expect(throws: RockxyNearbyTransferError.self) {
            try RockxyNearbyFrameAccumulator.frame(payload)
        }
    }
}
