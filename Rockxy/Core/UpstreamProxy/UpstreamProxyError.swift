import Foundation
import NIOCore
import NIOPosix

// MARK: - UpstreamProxyError

enum UpstreamProxyError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case authenticationRequired
    case authenticationRejected
    case connectRejected(statusCode: Int)
    case malformedResponse
    case responseTooLarge
    case unsupportedSOCKS5AuthMethod(UInt8)
    case socks5Reply(SOCKS5Reply)
    case targetHostTooLong
    case pacURLInvalid
    case pacTargetURLInvalid
    case pacEvaluationFailed(String)
    case pacNoSupportedRoute
    case pacSOCKS5Unavailable
    case timeout
    /// The external proxy itself could not be reached, as opposed to the site behind it.
    case proxyUnreachable(host: String, port: Int, reason: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            message
        case .authenticationRequired:
            String(localized: "Upstream proxy authentication is required.", bundle: RockxyLocalization.bundle)
        case .authenticationRejected:
            String(localized: "Upstream proxy authentication was rejected.", bundle: RockxyLocalization.bundle)
        case let .connectRejected(statusCode):
            String(
                localized: "Upstream proxy CONNECT failed with HTTP \(statusCode).",
                bundle: RockxyLocalization.bundle
            )
        case .malformedResponse:
            String(localized: "Upstream proxy returned a malformed response.", bundle: RockxyLocalization.bundle)
        case .responseTooLarge:
            String(
                localized: "Upstream proxy handshake response exceeded the size limit.",
                bundle: RockxyLocalization.bundle
            )
        case let .unsupportedSOCKS5AuthMethod(method):
            String(
                localized: "SOCKS5 proxy selected unsupported authentication method \(Int(method)).",
                bundle: RockxyLocalization.bundle
            )
        case let .socks5Reply(reply):
            reply.errorDescription
        case .targetHostTooLong:
            String(localized: "SOCKS5 target host is too long.", bundle: RockxyLocalization.bundle)
        case .pacURLInvalid:
            String(localized: "Automatic proxy configuration URL is invalid.", bundle: RockxyLocalization.bundle)
        case .pacTargetURLInvalid:
            String(localized: "Automatic proxy configuration target URL is invalid.", bundle: RockxyLocalization.bundle)
        case let .pacEvaluationFailed(message):
            String(
                localized: "Automatic proxy configuration failed: \(Self.redactingURLCredentials(in: message))",
                bundle: RockxyLocalization.bundle
            )
        case .pacNoSupportedRoute:
            String(
                localized: "Automatic proxy configuration did not return a supported proxy route.",
                bundle: RockxyLocalization.bundle
            )
        case .pacSOCKS5Unavailable:
            String(
                localized: "Automatic proxy configuration selected SOCKS5, which is unavailable in this build.",
                bundle: RockxyLocalization.bundle
            )
        case .timeout:
            String(localized: "Upstream proxy connection timed out.", bundle: RockxyLocalization.bundle)
        case let .proxyUnreachable(host, port, reason):
            String(
                localized: "Couldn't reach the external proxy \(host):\(String(port)) (\(reason)). Check that it is running, or turn off External Proxy.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    /// Replaces `user:password@` in any URL inside `text`, so a PAC URL with embedded credentials
    /// never reaches logs, the Connection Log, or exports.
    static func redactingURLCredentials(in text: String) -> String {
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return credentialPattern.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "$1[REDACTED]@"
        )
    }

    /// Short, credential-free description of why a TCP connection to the proxy failed.
    static func unreachableReason(_ error: Error) -> String {
        if let channelError = error as? ChannelError, case .connectTimeout = channelError {
            return String(localized: "timed out", bundle: RockxyLocalization.bundle)
        }
        if let connectionError = error as? NIOConnectionError,
           let ioError = connectionError.connectionErrors.first?.error as? IOError
        {
            return reason(errno: ioError.errnoCode)
        }
        if let ioError = error as? IOError {
            return reason(errno: ioError.errnoCode)
        }
        if error is NIOConnectionError {
            return String(localized: "host not found", bundle: RockxyLocalization.bundle)
        }
        return redactingURLCredentials(in: error.localizedDescription)
    }

    // MARK: Private

    // swiftlint:disable:next force_try
    private static let credentialPattern = try! NSRegularExpression(
        pattern: #"([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s@:]+(?::[^/\s@]*)?@"#
    )

    private static func reason(errno code: CInt) -> String {
        switch code {
        case ECONNREFUSED:
            String(localized: "connection refused", bundle: RockxyLocalization.bundle)
        case EHOSTUNREACH,
             ENETUNREACH:
            String(localized: "host unreachable", bundle: RockxyLocalization.bundle)
        case ETIMEDOUT:
            String(localized: "timed out", bundle: RockxyLocalization.bundle)
        default:
            String(cString: strerror(code))
        }
    }
}

// MARK: - SOCKS5Reply

enum SOCKS5Reply: UInt8, CaseIterable {
    case succeeded = 0x00
    case generalFailure = 0x01
    case connectionNotAllowed = 0x02
    case networkUnreachable = 0x03
    case hostUnreachable = 0x04
    case connectionRefused = 0x05
    case ttlExpired = 0x06
    case commandNotSupported = 0x07
    case addressTypeNotSupported = 0x08

    // MARK: Lifecycle

    init(code: UInt8) {
        self = Self(rawValue: code) ?? .generalFailure
    }

    // MARK: Internal

    var errorDescription: String {
        switch self {
        case .succeeded:
            String(localized: "SOCKS5 proxy connection succeeded.", bundle: RockxyLocalization.bundle)
        case .generalFailure:
            String(localized: "SOCKS5 proxy reported a general failure.", bundle: RockxyLocalization.bundle)
        case .connectionNotAllowed:
            String(localized: "SOCKS5 proxy rejected the connection by rule.", bundle: RockxyLocalization.bundle)
        case .networkUnreachable:
            String(localized: "SOCKS5 proxy could not reach the network.", bundle: RockxyLocalization.bundle)
        case .hostUnreachable:
            String(localized: "SOCKS5 proxy could not reach the host.", bundle: RockxyLocalization.bundle)
        case .connectionRefused:
            String(localized: "SOCKS5 target connection was refused.", bundle: RockxyLocalization.bundle)
        case .ttlExpired:
            String(localized: "SOCKS5 target connection TTL expired.", bundle: RockxyLocalization.bundle)
        case .commandNotSupported:
            String(localized: "SOCKS5 proxy does not support CONNECT.", bundle: RockxyLocalization.bundle)
        case .addressTypeNotSupported:
            String(localized: "SOCKS5 proxy does not support domain-name targets.", bundle: RockxyLocalization.bundle)
        }
    }
}
