import Foundation
import Network
import Observation
import os

// MARK: - BabylonListenerStatus

enum BabylonListenerStatus: Equatable {
    case stopped
    case starting
    case waiting(String)
    case ready
    case failed(String)
}

// MARK: - BabylonCaptureReceiver

@Observable
final class BabylonCaptureReceiver: @unchecked Sendable {
    // MARK: Lifecycle

    /// `preferredPort` is the protocol's fixed port; tests pass another one.
    init(preferredPort: UInt16 = BabylonCaptureProtocol.port) {
        self.preferredPort = preferredPort
    }

    // MARK: Internal

    static let shared = BabylonCaptureReceiver()
    static let maximumRuntimePayloadSize = 2 * 1_024 * 1_024

    let preferredPort: UInt16

    private(set) var listenerStatus = BabylonListenerStatus.stopped
    /// The port the listener actually bound. Devices discover it through Bonjour, so it can differ
    /// from the fixed port when another app (often a second Rockxy) already holds that one;
    /// simulator clients dial the fixed port directly and reach whichever app holds it.
    private(set) var listeningPort: UInt16?
    /// The Bonjour service name as registered, after any rename the network made to keep it unique.
    /// Babylon clients that pin a host name must use this value.
    private(set) var advertisedServiceName: String?

    var isUsingFallbackPort: Bool {
        guard let listeningPort else {
            return false
        }
        return listeningPort != preferredPort
    }
    /// Number of live TCP connections. Increments before authentication, so a
    /// non-zero value does not imply any paired/authenticated Babylon client.
    private(set) var openConnectionCount = 0

    static func validateRuntimePayloadSize(_ byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumRuntimePayloadSize else {
            throw BabylonCaptureProtocolError.frameTooLarge
        }
    }

    @MainActor
    func start(
        coordinator: MainContentCoordinator,
        pairingStore: BabylonPairingStore
    ) {
        self.coordinator = coordinator
        self.pairingStore = pairingStore
        startListening()
    }

    /// Bind and advertise the listener without attaching a coordinator. Frames that need one are
    /// rejected until `start(coordinator:pairingStore:)` provides it.
    func startListening() {
        queue.async { [weak self] in
            self?.startListenerIfNeeded()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    /// Restart only the Bonjour listener after a failure.
    ///
    /// Serialized and coalesced on the capture queue via queue-owned state
    /// (`listener` / `isListenerStarting`). It restarts the listener alone —
    /// already-accepted connections, their sessions, replay guards, and tracked
    /// transactions are preserved, and the pairing-token observer is left intact.
    /// It deliberately does NOT call `stopInternal()`. Authentication,
    /// connection/session limits, cryptography, protocol, and session handling are
    /// all unchanged; any stale listener error is cleared before rebinding.
    func retryListener() {
        queue.async { [weak self] in
            self?.restartListener()
        }
    }

    /// Clear every retained runtime event with an ingestion barrier.
    ///
    /// Runs on the capture queue, so it is totally ordered with runtime intake.
    /// Any event accepted before this call is either already retained, invalidated
    /// while awaiting MainActor publication, or still pending and discarded here.
    /// The store clear is dispatched before any genuinely later publication, so no
    /// earlier event can reappear afterward. Runtime-only: traffic, WebSocket
    /// sessions, and pairing are untouched.
    func clearRuntimeEvents() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            runtimePublicationGate.advance()
            cancelRuntimeFlush()
            runtimeIntake.discardPending()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    BabylonRuntimeEventStore.shared.clear()
                }
            }
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
    private static let runtimeBatchSize = 128
    private static let runtimeFlushMaxLatency: DispatchTimeInterval = .milliseconds(100)
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
    private var isListenerStarting = false
    /// Set when the fixed port was taken; the next bind uses any free port. Retry clears it.
    private var usesAnyPort = false
    private var runtimeIntake = BabylonRuntimeIntakeBuffer(batchSize: BabylonCaptureReceiver.runtimeBatchSize)
    private var runtimeFlushWorkItem: DispatchWorkItem?
    private let runtimePublicationGate = BabylonRuntimePublicationGate()

    private func startListenerIfNeeded() {
        installPairingObserverIfNeeded()
        startListener()
    }

    /// Install the pairing-token observer exactly once for the receiver's
    /// lifetime. Retry rebinds the listener without touching it, so it is never
    /// duplicated; `stopInternal()` is the only path that removes it.
    private func installPairingObserverIfNeeded() {
        guard pairingObserver == nil else {
            return
        }
        pairingObserver = NotificationCenter.default.addObserver(
            forName: .babylonPairingTokenDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in
                self?.disconnectAllClients()
            }
        }
    }

    private func startListener() {
        guard listener == nil else {
            return
        }
        guard let port = usesAnyPort ? .any : NWEndpoint.Port(rawValue: preferredPort) else {
            publishListenerStatus(.failed("Invalid Babylon capture port."))
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
            listener.serviceRegistrationUpdateHandler = { [weak self, weak listener] change in
                guard let self, let listener, self.listener === listener,
                      case let .add(endpoint) = change,
                      case let .service(name, _, _, _) = endpoint else
                {
                    return
                }
                publishAdvertisedServiceName(name)
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                guard let self, let listener, self.listener === listener else {
                    connection.cancel()
                    return
                }
                accept(connection)
            }
            self.listener = listener
            isListenerStarting = true
            // Publish a truthful Starting state and clear any stale listener error.
            publishListenerStatus(.starting)
            listener.start(queue: queue)
        } catch {
            isListenerStarting = false
            publishListenerStatus(.failed(error.localizedDescription))
        }
    }

    /// Restart only the listener generation. Cancels the current listener (its
    /// late callbacks are ignored by the identity guard in `handleListenerState`)
    /// and binds a fresh one, leaving connections, sessions, and the pairing
    /// observer untouched. Coalesced while a bind is already in flight.
    private func restartListener() {
        guard !isListenerStarting else {
            return
        }
        let active = listener
        listener = nil
        active?.stateUpdateHandler = nil
        active?.cancel()
        // Retry reclaims the fixed port when the app that held it has quit.
        usesAnyPort = false
        startListener()
    }

    private func handleListenerState(_ state: NWListener.State, listener: NWListener) {
        // Ignore every callback from a listener that is no longer the current
        // generation, so a replaced listener can never publish state.
        guard self.listener === listener else {
            return
        }
        switch state {
        case .ready:
            isListenerStarting = false
            publishListeningPort(listener.port?.rawValue)
            publishListenerStatus(.ready)
        case let .waiting(error):
            publishListenerStatus(.waiting(error.localizedDescription))
        case let .failed(error) where !usesAnyPort && Self.isAddressInUse(error):
            // Another app holds the fixed port. Devices find this Mac through Bonjour, which
            // carries the real port, so listen anywhere instead of leaving Babylon unavailable.
            Self.logger.info("Babylon port \(self.preferredPort) is in use; listening on another port")
            self.listener = nil
            listener.stateUpdateHandler = nil
            listener.cancel()
            isListenerStarting = false
            usesAnyPort = true
            startListener()
        case let .failed(error):
            isListenerStarting = false
            self.listener = nil
            listener.cancel()
            publishListeningPort(nil)
            publishListenerStatus(.failed(error.localizedDescription))
        case .cancelled:
            isListenerStarting = false
            // The current listener was cancelled without our asking — surface a
            // retryable Unavailable state rather than a misleading Starting.
            self.listener = nil
            publishListeningPort(nil)
            publishListenerStatus(.failed(String(
                localized: "The Babylon listener stopped unexpectedly.",
                bundle: RockxyLocalization.bundle
            )))
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
        publishOpenConnectionCount()
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
            await coordinator?.registerBabylonCapture(identity: identity)
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
        try Self.validateRuntimePayloadSize(payload.content.count)
        let package = try BabylonCaptureProtocol.decoder.decode(BabylonRuntimePackageDTO.self, from: payload.content)
        // Validation runs before retention. An invalid package throws here and
        // fails the frame through the existing receive path, exactly like any
        // other malformed payload — authentication and protocol guards upstream
        // are untouched.
        let event = try BabylonRuntimeEvent(validating: package, source: identity)
        enqueueRuntimeEvent(event)
    }

    /// Accumulate a validated runtime event on the capture queue and publish it in
    /// a bounded FIFO batch. Never spawns one unstructured MainActor task per event.
    private func enqueueRuntimeEvent(_ event: BabylonRuntimeEvent) {
        dispatchPrecondition(condition: .onQueue(queue))
        runtimeIntake.enqueue(event)
        if runtimeIntake.isReadyForImmediateFlush {
            flushRuntimeEvents()
        } else {
            scheduleRuntimeFlush()
        }
    }

    private func scheduleRuntimeFlush() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard runtimeFlushWorkItem == nil else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushRuntimeEvents()
        }
        runtimeFlushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + Self.runtimeFlushMaxLatency, execute: workItem)
    }

    private func flushRuntimeEvents() {
        dispatchPrecondition(condition: .onQueue(queue))
        cancelRuntimeFlush()
        guard runtimeIntake.hasPending else {
            return
        }
        let batch = runtimeIntake.drain()
        let publicationGeneration = runtimePublicationGate.snapshot()
        // Dispatching from the serial capture queue to the main queue preserves
        // FIFO order relative to every other runtime append and to clear — a plain
        // main-queue hop keeps that ordering where unordered tasks would not.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard self.runtimePublicationGate.isCurrent(publicationGeneration) else {
                    return
                }
                BabylonRuntimeEventStore.shared.appendBatch(batch)
            }
        }
    }

    private func cancelRuntimeFlush() {
        dispatchPrecondition(condition: .onQueue(queue))
        runtimeFlushWorkItem?.cancel()
        runtimeFlushWorkItem = nil
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
        publishOpenConnectionCount()
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
        publishOpenConnectionCount()
    }

    private func stopInternal() {
        runtimePublicationGate.advance()
        cancelRuntimeFlush()
        runtimeIntake.discardPending()
        let active = listener
        listener = nil
        isListenerStarting = false
        active?.cancel()
        usesAnyPort = false
        publishListeningPort(nil)
        disconnectAllClients()
        if let pairingObserver {
            NotificationCenter.default.removeObserver(pairingObserver)
            self.pairingObserver = nil
        }
        publishListenerStatus(.stopped)
    }

    private func publishListenerStatus(_ status: BabylonListenerStatus) {
        dispatchPrecondition(condition: .onQueue(queue))
        // Every publication originates on `queue`; dispatching from that serial
        // source to the main queue preserves listener-generation ordering.
        DispatchQueue.main.async { [weak self] in
            self?.listenerStatus = status
        }
    }

    private func publishListeningPort(_ port: UInt16?) {
        dispatchPrecondition(condition: .onQueue(queue))
        DispatchQueue.main.async { [weak self] in
            self?.listeningPort = port
            if port == nil {
                self?.advertisedServiceName = nil
            }
        }
    }

    private func publishAdvertisedServiceName(_ name: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        DispatchQueue.main.async { [weak self] in
            self?.advertisedServiceName = name
        }
    }

    static func isAddressInUse(_ error: NWError) -> Bool {
        if case let .posix(code) = error {
            return code == .EADDRINUSE
        }
        return false
    }

    private func publishOpenConnectionCount() {
        dispatchPrecondition(condition: .onQueue(queue))
        let count = connections.count
        DispatchQueue.main.async { [weak self] in
            self?.openConnectionCount = count
        }
    }
}
