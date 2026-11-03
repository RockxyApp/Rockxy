import Foundation
@testable import Rockxy
import Testing

// Regression tests for the host-finding sorts. Each of these sorts ranks a dictionary and then
// takes a prefix, so without a key tiebreak the tied host that survived was whichever one the
// hash buckets happened to put first -- findings appeared and disappeared between rebuilds with
// no change in the traffic. Shuffling the samples changes the dictionary's insertion order, and
// therefore its bucket layout, so a tie that is not broken by name shows up as a different
// expected host.

// MARK: - TrafficInsightsFindingOrderTests

@Suite("Traffic Insights finding order")
struct TrafficInsightsFindingOrderTests {
    // MARK: Internal

    @Test("Tied 5xx hosts are ranked by name, so the same three survive every rebuild")
    func serverErrorTiesAreStable() {
        var samples: [TrafficInsightsSample] = []
        for host in Self.tiedHosts {
            samples.append(makeSample(host: host, status: 500))
            samples.append(makeSample(host: host, status: 503))
        }

        for _ in 0 ..< Self.rebuildCount {
            let findings = TrafficInsightsEngine.buildReport(samples: samples.shuffled()).report.findings
            #expect(hosts(in: findings, kind: .serverErrorHost) == Array(Self.tiedHosts.prefix(3)))
        }
    }

    @Test("Tied 4xx hosts are ranked by name")
    func clientErrorTiesAreStable() {
        var samples: [TrafficInsightsSample] = []
        for host in Self.tiedHosts {
            samples.append(makeSample(host: host, status: 404))
            samples.append(makeSample(host: host, status: 403))
            for _ in 0 ..< 3 {
                samples.append(makeSample(host: host, status: 200))
            }
        }

        for _ in 0 ..< Self.rebuildCount {
            let findings = TrafficInsightsEngine.buildReport(samples: samples.shuffled()).report.findings
            #expect(hosts(in: findings, kind: .clientErrorHost) == Array(Self.tiedHosts.prefix(3)))
        }
    }

    @Test("Hosts with an identical p95 tail are ranked by name")
    func slowHostTiesAreStable() {
        var samples: [TrafficInsightsSample] = []
        for host in Self.tiedHosts {
            for _ in 0 ..< TrafficInsightsEngine.hostSampleFloor {
                samples.append(makeSample(host: host, duration: 3.0))
            }
        }

        for _ in 0 ..< Self.rebuildCount {
            let findings = TrafficInsightsEngine.buildReport(samples: samples.shuffled()).report.findings
            #expect(hosts(in: findings, kind: .slowHost) == Array(Self.tiedHosts.prefix(3)))
        }
    }

    @Test("Hosts with an identical average TLS handshake are ranked by name")
    func slowTLSTiesAreStable() {
        let timing = TimingInfo(
            dnsLookup: 0.01,
            tcpConnection: 0.01,
            tlsHandshake: 0.5,
            timeToFirstByte: 0.01,
            contentTransfer: 0.01
        )
        var samples: [TrafficInsightsSample] = []
        for host in Self.tiedHosts {
            // Three is the slow-TLS floor and below the slow-host floor, so these samples
            // produce the TLS finding only.
            for _ in 0 ..< 3 {
                samples.append(makeSample(host: host, timing: timing))
            }
        }

        for _ in 0 ..< Self.rebuildCount {
            let findings = TrafficInsightsEngine.buildReport(samples: samples.shuffled()).report.findings
            #expect(hosts(in: findings, kind: .slowTLSHandshake) == Array(Self.tiedHosts.prefix(2)))
        }
    }

    // MARK: Private

    /// Deliberately more hosts than any of the prefixes keeps, all tied, and declared in the
    /// order the fixed sorts must produce.
    private static let tiedHosts = [
        "a.example.com",
        "b.example.com",
        "c.example.com",
        "d.example.com",
        "e.example.com",
        "f.example.com",
    ]

    private static let rebuildCount = 25

    private func hosts(
        in findings: [TrafficInsightsFinding],
        kind: TrafficInsightsFindingKind
    )
        -> [String]
    {
        findings
            .filter { $0.kind == kind }
            .compactMap { finding in
                guard case let .focusHost(host) = finding.handoff else {
                    return nil
                }
                return host
            }
    }

    private func makeSample(
        host: String,
        status: Int? = 200,
        duration: TimeInterval? = 0.1,
        timing: TimingInfo? = nil
    )
        -> TrafficInsightsSample
    {
        guard let url = URL(string: "https://\(host)/test") else {
            preconditionFailure("Expected valid fixture URL")
        }
        let responseHeaders = [HTTPHeader(name: "Content-Type", value: "application/json")]
        let request = HTTPRequestData(
            method: "GET",
            url: url,
            httpVersion: "HTTP/1.1",
            headers: [],
            body: nil,
            contentType: nil
        )
        let response: HTTPResponseData? = status.map { code in
            var data = HTTPResponseData(
                statusCode: code,
                statusMessage: "",
                headers: responseHeaders,
                body: nil
            )
            data.contentType = ContentType.detect(from: "application/json")
            return data
        }
        return TrafficInsightsSample(
            id: UUID(),
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
            request: request,
            response: response,
            state: .completed,
            isTLSFailure: false,
            isTunneled: false,
            clientApp: "Safari",
            duration: timing?.totalDuration ?? duration,
            timing: timing,
            webSocketSentBytes: 0,
            webSocketReceivedBytes: 0,
            hasWebSocket: false,
            hasGraphQL: false,
            hasWeb3RPC: false,
            matchedRuleName: nil
        )
    }
}
