import CryptoKit
import Foundation
import Network
import Observation
import os

// MARK: - RockxyIncomingTransferInvitation

struct RockxyIncomingTransferInvitation: Identifiable, Equatable {
    let id: String
    let deviceName: String
    let sessionTitle: String
    let transactionCount: Int
    let verificationCode: String
}

// MARK: - RockxyNearbyTransferReceiver

@Observable
final class RockxyNearbyTransferReceiver: @unchecked Sendable {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = RockxyNearbyTransferReceiver()

    private(set) var pendingInvitation: RockxyIncomingTransferInvitation?
    private(set) var listenerError: String?

    func start(coordinator: MainContentCoordinator) {
        self.coordinator = coordinator
        guard listener == nil else {
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Rockxy Mac",
                type: RockxyNearbyTransferProtocol.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                if case let .failed(error) = state {
                    Task { @MainActor [weak self] in
                        self?.listenerError = error.localizedDescription
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            listenerError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        pendingInvitation = nil
        queue.async { [weak self] in
            self?.contexts.values.forEach { $0.connection.cancel() }
            self?.contexts = [:]
        }
    }

    func approve(_ invitation: RockxyIncomingTransferInvitation) {
        pendingInvitation = nil
        queue.async { [weak self] in
            guard let self, let context = contexts[invitation.id], let keys = context.keys else {
                return
            }
            context.isApproved = true
            do {
                let sealed = try RockxyNearbyPairingCrypto.seal(Data("ready".utf8), using: keys.encryptionKey)
                send(
                    RockxyNearbyTransferMessage(
                        type: .ready,
                        protocolVersion: RockxyNearbyTransferProtocol.version,
                        transferID: context.transferID,
                        sealedPayload: sealed
                    ),
                    context: context
                )
            } catch {
                fail(error.localizedDescription, context: context)
            }
        }
    }

    func decline(_ invitation: RockxyIncomingTransferInvitation) {
        pendingInvitation = nil
        queue.async { [weak self] in
            guard let self, let context = contexts[invitation.id] else {
                return
            }
            send(
                RockxyNearbyTransferMessage(
                    type: .decline,
                    protocolVersion: RockxyNearbyTransferProtocol.version,
                    transferID: context.transferID,
                    message: "Rockxy Mac declined the transfer."
                ),
                context: context
            )
            context.connection.cancel()
            contexts[invitation.id] = nil
        }
    }

    // MARK: Private

    private final class ConnectionContext: @unchecked Sendable {
        // MARK: Lifecycle

        init(connection: NWConnection) {
            self.connection = connection
        }

        // MARK: Internal

        let connection: NWConnection
        let connectionID = UUID().uuidString
        var frameAccumulator = RockxyNearbyFrameAccumulator()
        var transferID = ""
        var deviceName = "iPhone"
        var sessionTitle = "Rockxy iOS Session"
        var transactionCount = 0
        var privateKey: P256.KeyAgreement.PrivateKey?
        var keys: RockxyNearbyPairingCrypto.SessionKeys?
        var isApproved = false
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "NearbyTransfer"
    )

    private let queue = DispatchQueue(label: "com.rockxy.macos.nearby-transfer", qos: .userInitiated)
    private weak var coordinator: MainContentCoordinator?
    private var listener: NWListener?
    private var contexts: [String: ConnectionContext] = [:]

    private func accept(_ connection: NWConnection) {
        let context = ConnectionContext(connection: connection)
        contexts[context.connectionID] = context
        connection.stateUpdateHandler = { [weak self, weak context] state in
            guard let self, let context else {
                return
            }
            switch state {
            case .ready:
                self.receiveNext(context)
            case .cancelled:
                self.remove(context)
            case let .failed(error):
                self.fail(error.localizedDescription, context: context)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext(_ context: ConnectionContext) {
        context.connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1_024
        ) { [weak self, weak context] data, _, isComplete, error in
            guard let self, let context else {
                return
            }
            if let error {
                self.fail(error.localizedDescription, context: context)
                return
            }
            if let data, !data.isEmpty {
                do {
                    for frame in try context.frameAccumulator.append(data) {
                        try self.handle(frame, context: context)
                    }
                } catch {
                    self.fail(error.localizedDescription, context: context)
                    return
                }
            }
            if isComplete {
                self.remove(context)
            } else {
                self.receiveNext(context)
            }
        }
    }

    private func handle(_ frame: Data, context: ConnectionContext) throws {
        let message = try RockxyNearbyTransferProtocol.decoder.decode(RockxyNearbyTransferMessage.self, from: frame)
        guard message.protocolVersion == RockxyNearbyTransferProtocol.version else {
            throw RockxyNearbyTransferError.unsupportedVersion
        }

        switch message.type {
        case .hello:
            try handleHello(message, context: context)
        case .payload:
            try handlePayload(message, context: context)
        default:
            throw RockxyNearbyTransferError.invalidMessage
        }
    }

    private func handleHello(
        _ message: RockxyNearbyTransferMessage,
        context: ConnectionContext
    )
        throws
    {
        guard !message.transferID.isEmpty,
              let publicKey = message.publicKey,
              let count = message.transactionCount,
              count > 0,
              count <= RockxyNearbyTransferProtocol.maximumTransactionCount else
        {
            throw RockxyNearbyTransferError.invalidMessage
        }

        let privateKey = P256.KeyAgreement.PrivateKey()
        let keys = try RockxyNearbyPairingCrypto.deriveKeys(
            privateKey: privateKey,
            peerPublicKeyData: publicKey,
            transferID: message.transferID
        )
        context.transferID = message.transferID
        context.deviceName = String((message.deviceName ?? "iPhone").prefix(80))
        context.sessionTitle = String((message.sessionTitle ?? "Rockxy iOS Session").prefix(160))
        context.transactionCount = count
        context.privateKey = privateKey
        context.keys = keys
        contexts[context.connectionID] = nil
        contexts[message.transferID] = context

        send(
            RockxyNearbyTransferMessage(
                type: .helloAcknowledgement,
                protocolVersion: RockxyNearbyTransferProtocol.version,
                transferID: message.transferID,
                deviceName: Host.current().localizedName ?? "Rockxy Mac",
                publicKey: privateKey.publicKey.x963Representation
            ),
            context: context
        )

        let invitation = RockxyIncomingTransferInvitation(
            id: message.transferID,
            deviceName: context.deviceName,
            sessionTitle: context.sessionTitle,
            transactionCount: count,
            verificationCode: keys.verificationCode
        )
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if let existing = pendingInvitation {
                decline(existing)
            }
            pendingInvitation = invitation
            if ProcessInfo.processInfo.arguments.contains("rockxy.nearby-transfer-auto-accept") {
                approve(invitation)
            }
        }
    }

    private func handlePayload(
        _ message: RockxyNearbyTransferMessage,
        context: ConnectionContext
    )
        throws
    {
        guard message.transferID == context.transferID,
              context.isApproved,
              let sealedPayload = message.sealedPayload,
              let keys = context.keys else
        {
            throw RockxyNearbyTransferError.invalidMessage
        }
        let payload = try RockxyNearbyPairingCrypto.open(sealedPayload, using: keys.encryptionKey)
        guard payload.count <= RockxyNearbyTransferProtocol.maximumFrameSize else {
            throw RockxyNearbyTransferError.transferTooLarge
        }
        let session = try RockxyNearbyTransferProtocol.decoder.decode(RockxyNearbyTransferSession.self, from: payload)
        guard session.version == "1",
              !session.transactions.isEmpty,
              session.transactions.count == context.transactionCount,
              session.transactions.count <= RockxyNearbyTransferProtocol.maximumTransactionCount else
        {
            throw RockxyNearbyTransferError.invalidMessage
        }

        Task { @MainActor [weak self, weak context] in
            guard let self, let context, let coordinator else {
                return
            }
            do {
                try await coordinator.importNearbyTransfer(session, deviceName: context.deviceName)
                queue.async { [weak self, weak context] in
                    guard let self, let context, let keys = context.keys else {
                        return
                    }
                    do {
                        let acknowledgement = try RockxyNearbyPairingCrypto.seal(
                            Data("received:\(session.transactions.count)".utf8),
                            using: keys.encryptionKey
                        )
                        send(
                            RockxyNearbyTransferMessage(
                                type: .acknowledgement,
                                protocolVersion: RockxyNearbyTransferProtocol.version,
                                transferID: context.transferID,
                                sealedPayload: acknowledgement
                            ),
                            context: context
                        )
                        Self.logger.info("Imported nearby iOS session with \(session.transactions.count) transactions")
                    } catch {
                        fail(error.localizedDescription, context: context)
                    }
                }
            } catch {
                queue.async { [weak self, weak context] in
                    guard let self, let context else {
                        return
                    }
                    fail(error.localizedDescription, context: context)
                }
            }
        }
    }

    private func send(
        _ message: RockxyNearbyTransferMessage,
        context: ConnectionContext
    ) {
        do {
            let payload = try RockxyNearbyTransferProtocol.encoder.encode(message)
            let frame = try RockxyNearbyFrameAccumulator.frame(payload)
            context.connection.send(content: frame, completion: .contentProcessed { [weak self, weak context] error in
                if let error, let self, let context {
                    self.fail(error.localizedDescription, context: context)
                }
            })
        } catch {
            fail(error.localizedDescription, context: context)
        }
    }

    private func fail(_ message: String, context: ConnectionContext) {
        Self.logger.error("Nearby transfer failed: \(message, privacy: .public)")
        sendErrorIfPossible(message, context: context)
        context.connection.cancel()
        remove(context)
    }

    private func sendErrorIfPossible(_ message: String, context: ConnectionContext) {
        guard !context.transferID.isEmpty else {
            return
        }
        let errorMessage = RockxyNearbyTransferMessage(
            type: .error,
            protocolVersion: RockxyNearbyTransferProtocol.version,
            transferID: context.transferID,
            message: String(message.prefix(300))
        )
        if let data = try? RockxyNearbyTransferProtocol.encoder.encode(errorMessage),
           let frame = try? RockxyNearbyFrameAccumulator.frame(data)
        {
            context.connection.send(content: frame, completion: .idempotent)
        }
    }

    private func remove(_ context: ConnectionContext) {
        guard !context.transferID.isEmpty else {
            return
        }
        queue.async { [weak self] in
            self?.contexts[context.connectionID] = nil
            self?.contexts[context.transferID] = nil
        }
        Task { @MainActor [weak self] in
            guard self?.pendingInvitation?.id == context.transferID else {
                return
            }
            self?.pendingInvitation = nil
        }
    }
}
