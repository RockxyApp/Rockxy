import Foundation

// MARK: - ConnectionLog

/// What Rockxy observed while reaching the server for one exchange: the address it connected
/// to, the route it took, and the TLS session it negotiated. Only measured facts are stored;
/// the readable log is built from them (plus the recorded request and response) when shown.
struct ConnectionLog: Codable, Sendable, Equatable {
    enum Route: Codable, Sendable, Equatable {
        case direct
        /// An external proxy from Settings; `kind` is its scheme (HTTP, HTTPS, SOCKS5).
        case externalProxy(kind: String, host: String, port: Int)
    }

    enum FailureStage: String, Codable, Sendable {
        case connect
        case proxy
        case tls
        case response
    }

    struct Failure: Codable, Sendable, Equatable {
        let stage: FailureStage
        let message: String
        /// Each address tried before giving up, as "address port N: reason".
        var attempts: [String] = []
    }

    struct Certificate: Codable, Sendable, Equatable {
        let subject: String
        let issuer: String
        let alternativeNames: [String]
        let notValidBefore: Date?
        let notValidAfter: Date?
        let serialNumber: String?
    }

    enum Verification: String, Codable, Sendable {
        case verified
        /// The chain was checked but the host name could not be (IP-address origins).
        case hostnameSkipped
        /// "Accept untrusted upstream certificates" was on for this connection.
        case disabled
    }

    struct TLS: Codable, Sendable, Equatable {
        var serverName: String?
        var offeredProtocols: [String] = []
        var negotiatedProtocol: String?
        var version: String?
        var handshakeDuration: TimeInterval?
        var verification: Verification?
        var certificate: Certificate?
    }

    /// Host and port the request addressed.
    var host: String
    var port: Int
    /// The address actually dialled when it differs from `host` (DNS Spoofing, emulator alias,
    /// Map Remote target resolution).
    var connectHost: String?
    var route: Route = .direct
    /// The route came from the proxy auto-configuration (PAC) script.
    var routeChosenByPAC = false
    /// Peer of the upstream socket: the server, or the external proxy when one is used.
    var remoteAddress: String?
    var remotePort: Int?
    var localAddress: String?
    var localPort: Int?
    var connectDuration: TimeInterval?
    var tls: TLS?
    var failure: Failure?
}

// MARK: - ConnectionLogLine

/// One rendered line of the connection log. `role` drives both color and the leading marker,
/// mirroring the familiar `curl -v` convention (`*` event, `>` sent, `<` received).
struct ConnectionLogLine: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case event
        case host
        case tls
        case success
        case warning
        case failure
        case requestHeader
        case responseHeader
        case note
    }

    let marker: String
    let text: String
    let role: Role

    var rendered: String {
        marker.isEmpty ? text : "\(marker) \(text)"
    }
}
