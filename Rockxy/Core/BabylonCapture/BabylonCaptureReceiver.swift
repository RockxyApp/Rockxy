import Foundation
import Network
import Observation
import os

@Observable
final class BabylonCaptureReceiver: @unchecked Sendable {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = BabylonCaptureReceiver()

    private(set) var listenerError: String?
    private(set) var isListening = false
    private(set) var connectedClientCount = 0

    @MainActor
    func start(
        coordinator: MainContentCoordinator,
        pairingStore: BabylonPairingStore
    ) {
        self.coordinator = coordinator
        self.pairingStore = pairingStore
        queue.async { [weak self] in
            self?.startListenerIfNeeded()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    // MARK: Private

    private final class ConnectionContext: @unchecked Sendable {
        // MARK: Lifecycle

        init(connection: NWConnection) {
            self.connection = connection
        }

        // MARK: Internal

        let id = UUID()
        let connection: NWConnection
        var accumulator = BabylonFrameAccumulator()
        var hasAuthenticatedFrame = false
    }

    private final class SessionState: @unchecked Sendable {
        // MARK: Internal

        var outboundSequence: UInt64 = 0
        var identity: BabylonCaptureIdentity?
        var transactions: [String: HTTPTransaction] = [:]

        func accept(frame: BabylonSecureFrame) throws -> BabylonReplayDisposition {
            try replayGuard.accept(messageID: frame.messageID, sequence: frame.sequence)
        }

        func nextOutboundSequence() -> UInt64 {
            outboundSequence &+= 1
            return outboundSequence
        }

        // MARK: Private

        private var replayGuard = BabylonMessageReplayGuard()
    }

    private static let maximumConnectionCount = 8
    private static let maximumSessionCount = 64
    private static let maximumTrackedTransactions = 10_000
    private static let authenticationTimeout: TimeInterval = 10
    private static let maximumAggregateBufferedBytes = BabylonCaptureProtocol.maximumFrameSize + 64 * 1_024 + 8
    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "BabylonCapture"
    )

    private let queue = DispatchQueue(label: "com.rockxy.macos.babylon-capture", qos: .userInitiated)
    private weak var coordinator: MainContentCoordinator?
    private weak var pairingStore: BabylonPairingStore?
    private var listener: NWListener?
    private var connections: [UUID: ConnectionContext] = [:]
    private var sessions: [String: SessionState] = [:]
    private var sessionOrder: [String] = []
    private var pairingObserver: NSObjectProtocol?
    private var aggregateBufferedByteCount = 0

    private func startListenerIfNeeded() {
        guard listener == nil else {
            return
        }
        guard let port = NWEndpoint.Port(rawValue: BabylonCaptureProtocol.port) else {
            updateListenerState(error: "Invalid Babylon capture port.")
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters, on: port)
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Rockxy Mac",
                type: BabylonCaptureProtocol.serviceType
            )
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else {
                    return
                }
                handleListenerState(state, listener: listener)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            pairingObserver = NotificationCenter.default.addObserver(
                forName: .babylonPairingTokenDidChange,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.disconnectAllClients()
                }
            }
            listener.start(queue: queue)
        } catch {
            updateListenerState(error: error.localizedDescription)
        }
    }

    private func handleListenerState(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            updateListenerState(listening: true)
        case let .failed(error):
            listener.cancel()
            if self.listener === listener {
                self.listener = nil
            }
            updateListenerState(error: error.localizedDescription)
        case .cancelled:
            if self.listener === listener {
                self.listener = nil
            }
            updateListenerState(listening: false)
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maximumConnectionCount else {
            connection.cancel()
            return
        }
        let context = ConnectionContext(connection: connection)
        connections[context.id] = context
        publishConnectedClientCount()
        connection.stateUpdateHandler = { [weak self, weak context] state in
            guard let self, let context else {
                return
            }
            switch state {
            case .ready:
                receiveNext(context)
            case .cancelled:
                remove(context)
            case let .failed(error):
                Self.logger.error("Babylon connection failed: \(error.localizedDescription, privacy: .public)")
                remove(context)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.authenticationTimeout) { [weak self, weak context] in
            guard let self, let context, !context.hasAuthenticatedFrame else {
                return
            }
            remove(context)
        }
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
                Self.logger.error("Babylon receive failed: \(error.localizedDescription, privacy: .public)")
                context.connection.cancel()
                remove(context)
                return
            }
            if let data, !data.isEmpty {
                let previousBufferedByteCount = context.accumulator.bufferedByteCount
                var reconciledBufferedByteCount = false
                do {
                    guard data.count <= Self.maximumAggregateBufferedBytes,
                          aggregateBufferedByteCount <= Self.maximumAggregateBufferedBytes - data.count else
                    {
                        throw BabylonCaptureProtocolError.frameTooLarge
                    }
                    let frames = try context.accumulator.append(data)
                    reconcileBufferedByteCount(for: context, previousByteCount: previousBufferedByteCount)
                    reconciledBufferedByteCount = true
                    for frameData in frames {
                        try handle(frameData, context: context)
                    }
                } catch {
                    if !reconciledBufferedByteCount {
                        reconcileBufferedByteCount(for: context, previousByteCount: previousBufferedByteCount)
                    }
                    Self.logger.warning("Rejected Babylon frame: \(error.localizedDescription, privacy: .public)")
                    context.connection.cancel()
                    remove(context)
                    return
                }
            }
            if isComplete {
                remove(context)
            } else {
                receiveNext(context)
            }
        }
    }

    private func handle(_ frameData: Data, context: ConnectionContext) throws {
        guard let token = pairingStore?.currentToken(), !token.isEmpty else {
            throw BabylonCaptureProtocolError.authenticationFailed
        }
        let (frame, payload) = try BabylonSecureFrameCodec.decodeFrame(frameData, pairingToken: token)
        context.hasAuthenticatedFrame = true
        let state = sessionState(clientID: frame.clientID, sessionID: frame.sessionID)
        let replayDisposition = try state.accept(frame: frame)
        if replayDisposition == .duplicate {
            if payload.messageType != .ack {
                try sendAcknowledgement(for: frame, state: state, context: context, pairingToken: token)
            }
            return
        }

        switch payload.messageType {
        case .connection:
            try handleConnection(payload, frame: frame, state: state)
        case .traffic:
            try handleTraffic(payload, state: state)
        case .websocket:
            try handleWebSocket(payload, state: state)
        case .runtime:
            try handleRuntime(payload, state: state)
        case .heartbeat,
             .ack:
            break
        case .error:
            _ = try? BabylonCaptureProtocol.decoder.decode(BabylonProtocolErrorPayload.self, from: payload.content)
        }
        if payload.messageType != .ack {
            try sendAcknowledgement(for: frame, state: state, context: context, pairingToken: token)
        }
    }

    private func handleConnection(
        _ payload: BabylonPayloadEnvelope,
        frame: BabylonSecureFrame,
        state: SessionState
    )
        throws
    {
        let package = try BabylonCaptureProtocol.decoder.decode(BabylonConnectionPackageDTO.self, from: payload.content)
        let identity = BabylonCaptureIdentity(
            clientID: frame.clientID,
            sessionID: frame.sessionID,
            projectName: String(package.project.name.prefix(120)),
            bundleIdentifier: String(package.project.bundleIdentifier.prefix(255)),
            deviceName: String(package.device.name.prefix(120)),
            deviceModel: String(package.device.model.prefix(255))
        )
        state.identity = identity
        Task { @MainActor [weak coordinator] in
            coordinator?.registerBabylonCapture(identity: identity)
        }
    }

    private func handleTraffic(_ payload: BabylonPayloadEnvelope, state: SessionState) throws {
        guard let identity = state.identity else {
            throw BabylonCaptureProtocolError.invalidIdentity
        }
        let package = try BabylonCaptureProtocol.decoder.decode(BabylonTrafficPackageDTO.self, from: payload.content)
        guard state.transactions[package.id] == nil else {
            return
        }
        let transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
        remember(transaction: transaction, packageID: package.id, state: state)
        Task { [weak coordinator] in
            await coordinator?.receiveBabylonTransaction(transaction)
        }
    }

    private func handleWebSocket(_ payload: BabylonPayloadEnvelope, state: SessionState) throws {
        guard let identity = state.identity else {
            throw BabylonCaptureProtocolError.invalidIdentity
        }
        let package = try BabylonCaptureProtocol.decoder.decode(BabylonTrafficPackageDTO.self, from: payload.content)
        let transaction: HTTPTransaction
        if let existing = state.transactions[package.id] {
            transaction = existing
        } else {
            transaction = try BabylonCaptureMapper.makeTransaction(from: package, identity: identity)
            remember(transaction: transaction, packageID: package.id, state: state)
            Task { [weak coordinator] in
                await coordinator?.receiveBabylonTransaction(transaction)
            }
        }
        let frame = try BabylonCaptureMapper.makeWebSocketFrame(from: package)
        guard let connection = transaction.webSocketConnection,
              connection.addFrame(frame, maximumTotalPayloadSize: ProxyLimits.maxWebSocketConnectionSize) else
        {
            throw BabylonCaptureMappingError.oversizedBody
        }
        Task { @MainActor in
            transaction.webSocketFrameVersion += 1
        }
    }

    private func handleRuntime(_ payload: BabylonPayloadEnvelope, state: SessionState) throws {
        guard let identity = state.identity else {
            throw BabylonCaptureProtocolError.invalidIdentity
        }
        let package = try BabylonCaptureProtocol.decoder.decode(BabylonRuntimePackageDTO.self, from: payload.content)
        let event = BabylonRuntimeEvent(package: package, source: identity)
        Task { @MainActor in
            BabylonRuntimeEventStore.shared.append(event)
        }
    }

    private func remember(transaction: HTTPTransaction, packageID: String, state: SessionState) {
        while state.transactions.count >= Self.maximumTrackedTransactions,
              let oldest = state.transactions.keys.first
        {
            state.transactions[oldest] = nil
        }
        state.transactions[packageID] = transaction
    }

    private func sendAcknowledgement(
        for frame: BabylonSecureFrame,
        state: SessionState,
        context: ConnectionContext,
        pairingToken: String
    )
        throws
    {
        let acknowledgement = BabylonAcknowledgement(messageID: frame.messageID)
        let payload = try BabylonPayloadEnvelope(
            messageType: .ack,
            sentAt: Date().timeIntervalSince1970,
            content: BabylonCaptureProtocol.encoder.encode(acknowledgement)
        )
        let encoded = try BabylonSecureFrameCodec.encodeFrame(
            payload: payload,
            sessionID: frame.sessionID,
            clientID: frame.clientID,
            sequence: state.nextOutboundSequence(),
            pairingToken: pairingToken
        )
        let framed = try BabylonFrameAccumulator.frame(encoded)
        context.connection.send(content: framed, completion: .contentProcessed { error in
            if let error {
                Self.logger.error("Babylon acknowledgement failed: \(error.localizedDescription, privacy: .public)")
            }
        })
    }

    private func sessionState(clientID: String, sessionID: String) -> SessionState {
        let key = "\(clientID):\(sessionID)"
        if let existing = sessions[key] {
            return existing
        }
        while sessionOrder.count >= Self.maximumSessionCount {
            sessions[sessionOrder.removeFirst()] = nil
        }
        let state = SessionState()
        sessions[key] = state
        sessionOrder.append(key)
        return state
    }

    private func remove(_ context: ConnectionContext) {
        guard connections.removeValue(forKey: context.id) != nil else {
            return
        }
        aggregateBufferedByteCount -= context.accumulator.bufferedByteCount
        context.connection.cancel()
        publishConnectedClientCount()
    }

    private func reconcileBufferedByteCount(for context: ConnectionContext, previousByteCount: Int) {
        let delta = context.accumulator.bufferedByteCount - previousByteCount
        aggregateBufferedByteCount = max(0, aggregateBufferedByteCount + delta)
    }

    private func disconnectAllClients() {
        connections.values.forEach { $0.connection.cancel() }
        connections.removeAll()
        aggregateBufferedByteCount = 0
        sessions.removeAll()
        sessionOrder.removeAll()
        publishConnectedClientCount()
    }

    private func stopInternal() {
        listener?.cancel()
        listener = nil
        disconnectAllClients()
        if let pairingObserver {
            NotificationCenter.default.removeObserver(pairingObserver)
            self.pairingObserver = nil
        }
        updateListenerState(listening: false)
    }

    private func updateListenerState(listening: Bool = false, error: String? = nil) {
        Task { @MainActor [weak self] in
            self?.isListening = listening
            self?.listenerError = error
        }
    }

    private func publishConnectedClientCount() {
        let count = connections.count
        Task { @MainActor [weak self] in
            self?.connectedClientCount = count
        }
    }
}
