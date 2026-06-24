import Foundation

/// Breakdown of an HTTP request's timing phases, measured by the proxy pipeline.
/// Used to render the waterfall chart in the timeline inspector.
struct TimingInfo: Sendable {
    let dnsLookup: TimeInterval
    let tcpConnection: TimeInterval
    let tlsHandshake: TimeInterval
    let timeToFirstByte: TimeInterval
    let contentTransfer: TimeInterval

    var totalDuration: TimeInterval {
        dnsLookup + tcpConnection + tlsHandshake + timeToFirstByte + contentTransfer
    }
}
