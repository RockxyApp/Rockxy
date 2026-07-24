import CryptoKit
import Foundation
import Security

// MARK: - BabylonCaptureProtocol

enum BabylonCaptureProtocol {
    static let version = 1
    static let serviceType = "_Rockxy._tcp"
    static let port: UInt16 = 10_909
    static let maximumFrameSize = 72 * 1_024 * 1_024
    static let maximumDecompressedSize = 96 * 1_024 * 1_024
    static let maximumCapturedBodySize = 50 * 1_024 * 1_024
    static let maximumRememberedMessageIDs = 2_048
    static let maximumMessageIDSize = 128
    static let maximumSessionIDSize = 128
    static let maximumClientIDSize = 512
    static let compression = "gzip"
    static let keySalt = Data("rockxy-babylon-v1".utf8)

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()
}

// MARK: - BabylonCaptureMessageType

enum BabylonCaptureMessageType: String, Codable {
    case connection
    case traffic
    case websocket
    case runtime
    case heartbeat
    case ack
    case error
}

// MARK: - BabylonSecureFrame

struct BabylonSecureFrame: Codable {
    let protocolVersion: Int
    let messageID: String
    let sessionID: String
    let clientID: String
    let sequence: UInt64
    let compression: String
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

// MARK: - BabylonPayloadEnvelope

struct BabylonPayloadEnvelope: Codable {
    let messageType: BabylonCaptureMessageType
    let sentAt: TimeInterval
    let content: Data
}

// MARK: - BabylonAcknowledgement

struct BabylonAcknowledgement: Codable {
    let messageID: String
}

// MARK: - BabylonProtocolErrorPayload

struct BabylonProtocolErrorPayload: Codable {
    let code: String
    let message: String
}

// MARK: - BabylonCaptureProtocolError

enum BabylonCaptureProtocolError: LocalizedError, Equatable {
    case emptyFrame
    case frameTooLarge
    case invalidFrame
    case unsupportedVersion
    case invalidIdentity
    case invalidCompression
    case invalidNonce
    case invalidTag
    case authenticationFailed
    case decompressionFailed
    case invalidPayload
    case replayedSequence
    case duplicateMessage

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .emptyFrame: "The Babylon frame is empty."
        case .frameTooLarge: "The Babylon frame exceeds the 72 MiB limit."
        case .invalidFrame: "The Babylon frame is malformed."
        case .unsupportedVersion: "The Babylon protocol version is unsupported."
        case .invalidIdentity: "The Babylon frame identity is invalid."
        case .invalidCompression: "The Babylon frame compression is unsupported."
        case .invalidNonce: "The Babylon frame nonce is invalid."
        case .invalidTag: "The Babylon authentication tag is invalid."
        case .authenticationFailed: "The Babylon frame could not be authenticated."
        case .decompressionFailed: "The Babylon payload could not be decompressed."
        case .invalidPayload: "The Babylon payload is invalid."
        case .replayedSequence: "The Babylon frame sequence was replayed."
        case .duplicateMessage: "The Babylon message was already received."
        }
    }
}

// MARK: - BabylonFrameAccumulator

struct BabylonFrameAccumulator {
    // MARK: Internal

    var bufferedByteCount: Int {
        buffer.count
    }

    static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else {
            throw BabylonCaptureProtocolError.emptyFrame
        }
        guard payload.count <= BabylonCaptureProtocol.maximumFrameSize else {
            throw BabylonCaptureProtocolError.frameTooLarge
        }
        var length = UInt64(payload.count).bigEndian
        var framed = Data(bytes: &length, count: MemoryLayout<UInt64>.size)
        framed.append(payload)
        return framed
    }

    mutating func append(_ data: Data) throws -> [Data] {
        guard !data.isEmpty else {
            return []
        }
        let maximumBufferedSize = BabylonCaptureProtocol.maximumFrameSize + MemoryLayout<UInt64>.size
        guard data.count <= maximumBufferedSize,
              buffer.count <= maximumBufferedSize - data.count else
        {
            throw BabylonCaptureProtocolError.frameTooLarge
        }

        buffer.append(data)
        var frames: [Data] = []

        while buffer.count >= 8 {
            let length = buffer.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard length > 0 else {
                throw BabylonCaptureProtocolError.emptyFrame
            }
            guard length <= UInt64(BabylonCaptureProtocol.maximumFrameSize), length <= UInt64(Int.max) else {
                throw BabylonCaptureProtocolError.frameTooLarge
            }

            let payloadLength = Int(length)
            guard buffer.count >= 8 + payloadLength else {
                break
            }
            frames.append(buffer.subdata(in: 8 ..< 8 + payloadLength))
            buffer.removeSubrange(0 ..< 8 + payloadLength)
        }

        return frames
    }

    // MARK: Private

    private var buffer = Data()
}

// MARK: - BabylonReplayDisposition

enum BabylonReplayDisposition: Equatable {
    case newMessage
    case duplicate
}

// MARK: - BabylonMessageReplayGuard

struct BabylonMessageReplayGuard {
    // MARK: Lifecycle

    init(maximumRememberedMessageIDs: Int = BabylonCaptureProtocol.maximumRememberedMessageIDs) {
        self.maximumRememberedMessageIDs = max(1, maximumRememberedMessageIDs)
    }

    // MARK: Internal

    mutating func accept(messageID: String, sequence: UInt64) throws -> BabylonReplayDisposition {
        if let rememberedSequence = rememberedMessageIDs[messageID] {
            guard rememberedSequence == sequence else {
                throw BabylonCaptureProtocolError.duplicateMessage
            }
            return .duplicate
        }
        if let maximumSequence, sequence <= maximumSequence {
            throw BabylonCaptureProtocolError.replayedSequence
        }
        maximumSequence = sequence
        rememberedMessageIDs[messageID] = sequence
        messageIDOrder.append(messageID)
        while messageIDOrder.count > maximumRememberedMessageIDs {
            rememberedMessageIDs[messageIDOrder.removeFirst()] = nil
        }
        return .newMessage
    }

    // MARK: Private

    private let maximumRememberedMessageIDs: Int
    private var maximumSequence: UInt64?
    private var rememberedMessageIDs: [String: UInt64] = [:]
    private var messageIDOrder: [String] = []
}

// MARK: - BabylonSecureFrameCodec

enum BabylonSecureFrameCodec {
    // MARK: Internal

    static func decodeFrame(_ data: Data, pairingToken: String) throws -> (BabylonSecureFrame, BabylonPayloadEnvelope) {
        let frame: BabylonSecureFrame
        do {
            frame = try BabylonCaptureProtocol.decoder.decode(BabylonSecureFrame.self, from: data)
        } catch {
            throw BabylonCaptureProtocolError.invalidFrame
        }

        try validate(frame)
        let key = deriveKey(pairingToken: pairingToken, clientID: frame.clientID, sessionID: frame.sessionID)
        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: frame.nonce)
        } catch {
            throw BabylonCaptureProtocolError.invalidNonce
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: frame.ciphertext, tag: frame.tag)
        } catch {
            throw BabylonCaptureProtocolError.invalidTag
        }

        let compressed: Data
        do {
            compressed = try AES.GCM.open(
                sealedBox,
                using: key,
                authenticating: additionalAuthenticatedData(for: frame)
            )
        } catch {
            throw BabylonCaptureProtocolError.authenticationFailed
        }
        guard let payloadData = BabylonGzipCodec.gunzip(
            compressed,
            maximumOutputSize: BabylonCaptureProtocol.maximumDecompressedSize
        ) else {
            throw BabylonCaptureProtocolError.decompressionFailed
        }

        do {
            return try (frame, BabylonCaptureProtocol.decoder.decode(BabylonPayloadEnvelope.self, from: payloadData))
        } catch {
            throw BabylonCaptureProtocolError.invalidPayload
        }
    }

    static func encodeFrame(
        payload: BabylonPayloadEnvelope,
        messageID: String = UUID().uuidString,
        sessionID: String,
        clientID: String,
        sequence: UInt64,
        pairingToken: String,
        nonceData: Data? = nil
    )
        throws -> Data
    {
        guard isValidIdentifier(messageID, maximumSize: BabylonCaptureProtocol.maximumMessageIDSize),
              isValidIdentifier(sessionID, maximumSize: BabylonCaptureProtocol.maximumSessionIDSize),
              isValidIdentifier(clientID, maximumSize: BabylonCaptureProtocol.maximumClientIDSize) else
        {
            throw BabylonCaptureProtocolError.invalidIdentity
        }
        let payloadData = try BabylonCaptureProtocol.encoder.encode(payload)
        guard let compressed = BabylonGzipCodec.gzip(payloadData) else {
            throw BabylonCaptureProtocolError.decompressionFailed
        }
        let resolvedNonceData: Data = if let nonceData {
            nonceData
        } else {
            try secureRandomData(count: 12)
        }
        let nonce = try AES.GCM.Nonce(data: resolvedNonceData)
        let key = deriveKey(pairingToken: pairingToken, clientID: clientID, sessionID: sessionID)
        let placeholder = BabylonSecureFrame(
            protocolVersion: BabylonCaptureProtocol.version,
            messageID: messageID,
            sessionID: sessionID,
            clientID: clientID,
            sequence: sequence,
            compression: BabylonCaptureProtocol.compression,
            nonce: resolvedNonceData,
            ciphertext: Data(),
            tag: Data()
        )
        let sealed = try AES.GCM.seal(
            compressed,
            using: key,
            nonce: nonce,
            authenticating: additionalAuthenticatedData(for: placeholder)
        )
        let frame = BabylonSecureFrame(
            protocolVersion: placeholder.protocolVersion,
            messageID: placeholder.messageID,
            sessionID: placeholder.sessionID,
            clientID: placeholder.clientID,
            sequence: placeholder.sequence,
            compression: placeholder.compression,
            nonce: resolvedNonceData,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
        return try BabylonCaptureProtocol.encoder.encode(frame)
    }

    static func additionalAuthenticatedData(for frame: BabylonSecureFrame) -> Data {
        Data(
            "\(frame.protocolVersion):\(frame.clientID):\(frame.sessionID):\(frame.messageID):\(frame.sequence)".utf8
        )
    }

    // MARK: Private

    private static func validate(_ frame: BabylonSecureFrame) throws {
        guard frame.protocolVersion == BabylonCaptureProtocol.version else {
            throw BabylonCaptureProtocolError.unsupportedVersion
        }
        guard isValidIdentifier(frame.messageID, maximumSize: BabylonCaptureProtocol.maximumMessageIDSize),
              isValidIdentifier(frame.sessionID, maximumSize: BabylonCaptureProtocol.maximumSessionIDSize),
              isValidIdentifier(frame.clientID, maximumSize: BabylonCaptureProtocol.maximumClientIDSize) else
        {
            throw BabylonCaptureProtocolError.invalidIdentity
        }
        guard frame.compression == BabylonCaptureProtocol.compression else {
            throw BabylonCaptureProtocolError.invalidCompression
        }
        guard frame.nonce.count == 12 else {
            throw BabylonCaptureProtocolError.invalidNonce
        }
        guard frame.tag.count == 16 else {
            throw BabylonCaptureProtocolError.invalidTag
        }
    }

    private static func deriveKey(pairingToken: String, clientID: String, sessionID: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(pairingToken.utf8)),
            salt: BabylonCaptureProtocol.keySalt,
            info: Data("\(clientID):\(sessionID)".utf8),
            outputByteCount: 32
        )
    }

    private static func isValidIdentifier(_ value: String, maximumSize: Int) -> Bool {
        let bytes = value.utf8
        return !bytes.isEmpty && bytes.count <= maximumSize && bytes.allSatisfy { byte in
            byte >= 0x20 && byte != 0x3A && byte != 0x7F
        }
    }

    private static func secureRandomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw BabylonCaptureProtocolError.invalidNonce
        }
        return data
    }
}
