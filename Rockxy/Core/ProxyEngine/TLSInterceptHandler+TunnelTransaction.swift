import Foundation
import os

nonisolated(unsafe) private let tunnelLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "TLSInterceptHandler"
)

// CONNECT rows recorded for tunnels, shared by the TLS interception and protocol detection paths.

extension TLSInterceptHandler {
    nonisolated static func makeTunnelTransaction(
        host: String,
        port: Int,
        statusCode: Int,
        statusMessage: String,
        state: TransactionState,
        sourcePort: UInt16?,
        measuredDuration: TimeInterval? = nil,
        isTLSFailure: Bool = false,
        sslCapture: HTTPTransaction.SSLCaptureMode? = nil,
        captureContext: TrafficCaptureContext? = nil,
        clientIdentifier: String? = nil
    )
        -> HTTPTransaction
    {
        let hostPart: String = if host.contains(":"), !host.hasPrefix("["), !host.hasSuffix("]") {
            "[\(host)]"
        } else {
            host
        }

        guard let tunnelURL = URL(string: "https://\(hostPart):\(port)") else {
            tunnelLogger.warning("Failed to build CONNECT tunnel URL for host \(host, privacy: .public):\(port)")
            var fallbackComponents = URLComponents()
            fallbackComponents.scheme = "https"
            fallbackComponents.host = "invalid-tunnel.local"
            fallbackComponents.port = 443
            let fallbackURL = fallbackComponents.url ?? URL(fileURLWithPath: "/")
            return makeTunnelTransaction(
                host: fallbackURL.host ?? "invalid-tunnel.local",
                port: fallbackURL.port ?? 443,
                statusCode: statusCode,
                statusMessage: statusMessage,
                state: state,
                sourcePort: sourcePort,
                measuredDuration: measuredDuration,
                isTLSFailure: isTLSFailure,
                sslCapture: sslCapture,
                captureContext: captureContext,
                clientIdentifier: clientIdentifier
            )
        }
        let requestData = HTTPRequestData(
            method: "CONNECT",
            url: tunnelURL,
            httpVersion: "1.1",
            headers: [],
            body: nil,
            contentType: nil,
            captureContext: captureContext
        )
        let transaction = HTTPTransaction(
            request: requestData,
            response: HTTPResponseData(
                statusCode: statusCode,
                statusMessage: statusMessage,
                headers: []
            ),
            state: state
        )
        transaction.measuredDuration = measuredDuration
        transaction.sourcePort = sourcePort
        transaction.isTLSFailure = isTLSFailure
        transaction.sslCapture = sslCapture
        transaction.tlsClientScopeIdentifier = clientIdentifier
        return transaction
    }

    nonisolated static func withConnectionLog(_ log: ConnectionLog?, _ transaction: HTTPTransaction) -> HTTPTransaction {
        transaction.connectionLog = log
        return transaction
    }
}
