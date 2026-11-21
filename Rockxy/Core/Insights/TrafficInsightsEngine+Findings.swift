import Foundation

// Deterministic findings for the Traffic Insights report.

extension TrafficInsightsEngine {
    /// Builds every finding from one walk over the samples. The walk collects the index sets
    /// each finding needs; the finding builders then only touch their own handful of rows.
    static func findings(
        _ samples: [ResolvedSample],
        evidenceLimit: Int,
        isCancelled: () -> Bool
    )
        -> [TrafficInsightsFinding]?
    {
        let index = FindingsIndex(samples)
        guard !isCancelled() else {
            return nil
        }

        var findings: [TrafficInsightsFinding] = []
        findings += errorHostFindings(samples, index: index, evidenceLimit: evidenceLimit)
        if let finding = failedRequestsFinding(samples, index: index, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        findings += slowHostFindings(samples, index: index, evidenceLimit: evidenceLimit)
        if let finding = uncompressedTextFinding(samples, index: index, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        if let finding = missingCacheHeadersFinding(samples, index: index, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        findings += repeatedRequestFindings(samples, index: index, evidenceLimit: evidenceLimit)
        if let finding = plainHTTPFinding(samples, index: index, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        if let finding = tunneledFinding(samples, index: index, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        if let finding = largeUploadFinding(samples, index: index, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }
        findings += slowTLSFindings(samples, index: index, evidenceLimit: evidenceLimit)
        if let finding = rulesAppliedFinding(samples, index: index, evidenceLimit: evidenceLimit) {
            findings.append(finding)
        }

        let kindOrder = Dictionary(
            uniqueKeysWithValues: TrafficInsightsFindingKind.allCases.enumerated().map { ($1, $0) }
        )
        return findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            let lhsOrder = kindOrder[lhs.kind] ?? 0
            let rhsOrder = kindOrder[rhs.kind] ?? 0
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.title < rhs.title
        }
    }

    // MARK: - Index

    /// Sample indices grouped by the predicate each finding evaluates, gathered in one pass.
    private struct FindingsIndex {
        // MARK: Lifecycle

        init(_ samples: [ResolvedSample]) {
            for (index, sample) in samples.enumerated() {
                add(sample, at: index)
            }
        }

        // MARK: Internal

        struct HostErrors {
            var completed = 0
            var serverErrors: [Int] = []
            var clientErrors: [Int] = []
        }

        var errorsByHost: [String: HostErrors] = [:]
        var failed: [Int] = []
        var timedByHost: [String: [(TimeInterval, Int)]] = [:]
        var uncompressedText: [Int] = []
        var uncachedStatic: [Int] = []
        var repeatedGETs: [String: [Int]] = [:]
        var plainHTTP: [Int] = []
        var tunneled: [Int] = []
        var largeUploads: [Int] = []
        var slowTLSByHost: [String: [(TimeInterval, Int)]] = [:]
        var ruleModified: [Int] = []

        // MARK: Private

        private static let textCategories: Set<TrafficInsightsContentCategory> = [
            .json, .html, .javascript, .css, .xml, .text,
        ]
        private static let staticCategories: Set<TrafficInsightsContentCategory> = [
            .image, .javascript, .css, .font,
        ]

        private mutating func add(_ sample: ResolvedSample, at index: Int) {
            let statusClass = sample.statusClass
            let host = sample.host

            if !host.isEmpty, statusClass != .pending {
                errorsByHost[host, default: HostErrors()].completed += 1
                switch statusClass {
                case .serverError:
                    errorsByHost[host, default: HostErrors()].serverErrors.append(index)
                case .clientError:
                    errorsByHost[host, default: HostErrors()].clientErrors.append(index)
                default:
                    break
                }
            }
            if statusClass == .failed {
                failed.append(index)
            }
            if !host.isEmpty, !sample.hasWebSocket, let duration = sample.timedDuration {
                timedByHost[host, default: []].append((duration, index))
            }
            if let response = sample.response, !sample.isTunneled,
               Int64(response.body?.count ?? 0) >= uncompressedTextThreshold,
               Self.textCategories.contains(sample.contentCategory)
            {
                let encoding = sample.sample.responseContentEncoding ?? ""
                if encoding.isEmpty || encoding == "identity" {
                    uncompressedText.append(index)
                }
            }
            if sample.method == "GET" {
                if statusClass == .success, Self.staticCategories.contains(sample.contentCategory),
                   !sample.sample.hasCacheHeaders
                {
                    uncachedStatic.append(index)
                }
                if !sample.hasWebSocket, !sample.isTunneled {
                    repeatedGETs[sample.sample.repeatKey, default: []].append(index)
                }
            }
            if sample.scheme == "http", !sample.hasWebSocket, !sample.isTunneled {
                plainHTTP.append(index)
            }
            if sample.isTunneled {
                tunneled.append(index)
            }
            if Int64(sample.request.body?.count ?? 0) >= largeUploadThreshold {
                largeUploads.append(index)
            }
            if !host.isEmpty, let timing = sample.timing, timing.tlsHandshake >= slowTLSHandshakeThreshold {
                slowTLSByHost[host, default: []].append((timing.tlsHandshake, index))
            }
            if sample.matchedRuleName != nil {
                ruleModified.append(index)
            }
        }
    }

    // MARK: - Builders

    private static func errorHostFindings(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        var results: [TrafficInsightsFinding] = []
        let serverHosts = index.errorsByHost
            .filter { !$0.value.serverErrors.isEmpty }
            .sorted { lhs, rhs in
                if lhs.value.serverErrors.count != rhs.value.serverErrors.count {
                    return lhs.value.serverErrors.count > rhs.value.serverErrors.count
                }
                // Total ordering: a dictionary iterates in bucket order, so without the key
                // tiebreak two hosts with the same count swapped places whenever the dictionary
                // rehashed, and `prefix` silently dropped a different one each rebuild. Same
                // shape as `repeatedRequestFindings`.
                return lhs.key < rhs.key
            }
            .prefix(3)
        for (host, entry) in serverHosts {
            let count = entry.serverErrors.count
            let rate = Double(count) / Double(max(entry.completed, 1))
            results.append(TrafficInsightsFinding(
                kind: .serverErrorHost,
                severity: count >= 3 || rate >= 0.1 ? .warning : .notice,
                title: TrafficInsightsText
                    .inflected(
                        "\(host): 5xx on \(count) of ^[\(entry.completed) request](inflect: true)"
                    ),
                detail: String(
                    localized: "Server-side failures. Compare failing and succeeding requests on this host.",
                    bundle: RockxyLocalization.bundle
                ),
                evidence: entry.serverErrors.prefix(evidenceLimit).map { reference(samples[$0]) },
                handoff: .focusHost(host)
            ))
        }

        let clientHosts = index.errorsByHost
            .filter { entry in
                entry.value.completed >= hostSampleFloor
                    && Double(entry.value.clientErrors.count) / Double(entry.value.completed) >= 0.2
            }
            .sorted { lhs, rhs in
                if lhs.value.clientErrors.count != rhs.value.clientErrors.count {
                    return lhs.value.clientErrors.count > rhs.value.clientErrors.count
                }
                return lhs.key < rhs.key
            }
            .prefix(3)
        for (host, entry) in clientHosts {
            let count = entry.clientErrors.count
            results.append(TrafficInsightsFinding(
                kind: .clientErrorHost,
                severity: .notice,
                title: TrafficInsightsText
                    .inflected("\(host): 4xx on \(count) of ^[\(entry.completed) request](inflect: true)"),
                detail: String(
                    localized: "Usually expired credentials, a wrong path, or missing parameters.",
                    bundle: RockxyLocalization.bundle
                ),
                evidence: entry.clientErrors.prefix(evidenceLimit).map { reference(samples[$0]) },
                handoff: .focusHost(host)
            ))
        }
        return results
    }

    private static func failedRequestsFinding(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let failed = index.failed
        guard !failed.isEmpty else {
            return nil
        }
        let tlsCount = failed.filter { samples[$0].isTLSFailure }.count
        let detail = if tlsCount > 0 {
            String(
                localized: "\(tlsCount) failed in the TLS handshake: the client does not trust the Rockxy certificate or pins its own.",
                bundle: RockxyLocalization.bundle
            )
        } else {
            String(
                localized: "Connection closed, timed out, or upstream unreachable.",
                bundle: RockxyLocalization.bundle
            )
        }
        let evidence = failed.prefix(evidenceLimit)
        return TrafficInsightsFinding(
            kind: .failedRequests,
            severity: failed.count >= 5 ? .warning : .notice,
            title: TrafficInsightsText
                .inflected("^[\(failed.count) request](inflect: true) failed without a response"),
            detail: detail,
            evidence: evidence.map { reference(samples[$0]) },
            handoff: .revealTransactions(evidence.map { samples[$0].id })
        )
    }

    private static func slowHostFindings(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        index.timedByHost
            .compactMap { host, entries -> (String, TimeInterval, [Int])? in
                guard entries.count >= hostSampleFloor else {
                    return nil
                }
                let sorted = entries.sorted { $0.0 < $1.0 }
                guard let tail = percentile(sorted.map(\.0), fraction: 0.95), tail >= slowHostTailThreshold else {
                    return nil
                }
                return (host, tail, sorted.suffix(evidenceLimit).reversed().map(\.1))
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                // The array still carries `timedByHost`'s bucket order, so equal tails need the
                // host name to settle which one `prefix` keeps.
                return lhs.0 < rhs.0
            }
            .prefix(3)
            .map { host, tail, evidence in
                TrafficInsightsFinding(
                    kind: .slowHost,
                    severity: .notice,
                    title: String(
                        localized: "\(host): p95 \(DurationFormatter.format(seconds: tail))",
                        bundle: RockxyLocalization.bundle
                    ),
                    detail: String(
                        localized: "1 in 20 requests to this host took at least this long. The Timing tab shows which phase dominates.",
                        bundle: RockxyLocalization.bundle
                    ),
                    evidence: evidence.map { reference(samples[$0]) },
                    handoff: .focusHost(host)
                )
            }
    }

    private static func uncompressedTextFinding(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let uncompressed = index.uncompressedText
        guard !uncompressed.isEmpty else {
            return nil
        }
        let totalBytes = uncompressed.reduce(Int64(0)) { $0 + samples[$1].receivedBytes }
        let sorted = uncompressed.sorted { samples[$0].receivedBytes > samples[$1].receivedBytes }
        let evidence = sorted.prefix(evidenceLimit)
        return TrafficInsightsFinding(
            kind: .uncompressedText,
            severity: .info,
            title: TrafficInsightsText
                .inflected(
                    "^[\(uncompressed.count) text response](inflect: true) ≥ 100 KB without compression (\(SizeFormatter.format(bytes: Int(totalBytes))))"
                ),
            detail: String(
                localized: "No Content-Encoding. gzip or Brotli usually shrinks JSON, HTML, and scripts by 70 percent or more.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: evidence.map { reference(samples[$0]) },
            handoff: .revealTransactions(evidence.map { samples[$0].id })
        )
    }

    private static func missingCacheHeadersFinding(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let uncached = index.uncachedStatic
        guard uncached.count >= hostSampleFloor else {
            return nil
        }
        let sorted = uncached.sorted { samples[$0].receivedBytes > samples[$1].receivedBytes }
        let evidence = sorted.prefix(evidenceLimit)
        return TrafficInsightsFinding(
            kind: .missingCacheHeaders,
            severity: .info,
            title: TrafficInsightsText
                .inflected("^[\(uncached.count) static asset](inflect: true) without cache headers"),
            detail: String(
                localized: "No Cache-Control, ETag, Expires, or Last-Modified, so they download again on every visit.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: evidence.map { reference(samples[$0]) },
            handoff: .revealTransactions(evidence.map { samples[$0].id })
        )
    }

    private static func repeatedRequestFindings(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        index.repeatedGETs
            .filter { $0.value.count >= repeatedRequestThreshold }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return lhs.key < rhs.key
            }
            .prefix(3)
            .compactMap { _, group in
                guard let first = group.first.map({ samples[$0] }) else {
                    return nil
                }
                let count = group.count
                let path = first.sample.displayPath
                let evidence = group.prefix(evidenceLimit)
                return TrafficInsightsFinding(
                    kind: .repeatedRequests,
                    severity: .info,
                    title: String(
                        localized: "GET \(path) repeated \(count)× on \(first.host)",
                        bundle: RockxyLocalization.bundle
                    ),
                    detail: String(
                        localized: "Same URL fetched repeatedly: missing client cache, polling, or retries.",
                        bundle: RockxyLocalization.bundle
                    ),
                    evidence: evidence.map { reference(samples[$0]) },
                    handoff: .revealTransactions(evidence.map { samples[$0].id })
                )
            }
    }

    private static func plainHTTPFinding(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let plain = index.plainHTTP
        guard !plain.isEmpty else {
            return nil
        }
        let hosts = Set(plain.map { samples[$0].host }.filter { !$0.isEmpty })
        let localOnly = hosts.allSatisfy(isLoopbackHost)
        let evidence = plain.prefix(evidenceLimit)
        return TrafficInsightsFinding(
            kind: .plainHTTP,
            severity: localOnly ? .info : .notice,
            title: TrafficInsightsText
                .inflected(
                    "^[\(plain.count) request](inflect: true) over plain HTTP (^[\(hosts.count) host](inflect: true))"
                ),
            detail: localOnly
                ? String(
                    localized: "Local addresses only — normal for development servers.",
                    bundle: RockxyLocalization.bundle
                )
                : String(
                    localized: "Headers, cookies, and bodies travel unencrypted.",
                    bundle: RockxyLocalization.bundle
                ),
            evidence: evidence.map { reference(samples[$0]) },
            handoff: .revealTransactions(evidence.map { samples[$0].id })
        )
    }

    private static func tunneledFinding(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let tunneled = index.tunneled
        guard !tunneled.isEmpty else {
            return nil
        }
        let hosts = Set(tunneled.map { samples[$0].host }.filter { !$0.isEmpty })
        return TrafficInsightsFinding(
            kind: .tunneledHosts,
            severity: .info,
            title: TrafficInsightsText
                .inflected(
                    "^[\(tunneled.count) connection](inflect: true) to ^[\(hosts.count) host](inflect: true) not decrypted"
                ),
            detail: String(
                localized: "Only the CONNECT is visible. Enable HTTPS Decryption for these hosts to inspect them.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: tunneled.prefix(evidenceLimit).map { reference(samples[$0]) },
            handoff: .openHTTPSDecryption
        )
    }

    private static func largeUploadFinding(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let uploads = index.largeUploads
        guard !uploads.isEmpty else {
            return nil
        }
        let sorted = uploads.sorted {
            (samples[$0].request.body?.count ?? 0) > (samples[$1].request.body?.count ?? 0)
        }
        let largest = Int(sorted.first.map { samples[$0].request.body?.count ?? 0 } ?? 0)
        let evidence = sorted.prefix(evidenceLimit)
        return TrafficInsightsFinding(
            kind: .largeUploads,
            severity: .info,
            title: TrafficInsightsText
                .inflected(
                    "^[\(uploads.count) upload](inflect: true) over 5 MB (largest \(SizeFormatter.format(bytes: largest)))"
                ),
            detail: String(
                localized: "Large bodies dominate upload time on slow links.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: evidence.map { reference(samples[$0]) },
            handoff: .revealTransactions(evidence.map { samples[$0].id })
        )
    }

    private static func slowTLSFindings(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> [TrafficInsightsFinding]
    {
        index.slowTLSByHost
            .filter { $0.value.count >= 3 }
            .map { host, entries -> (String, TimeInterval, [Int]) in
                let average = entries.reduce(0) { $0 + $1.0 } / Double(entries.count)
                let evidence = entries.sorted { $0.0 > $1.0 }.prefix(evidenceLimit).map(\.1)
                return (host, average, evidence)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0 < rhs.0
            }
            .prefix(2)
            .map { host, average, evidence in
                TrafficInsightsFinding(
                    kind: .slowTLSHandshake,
                    severity: .info,
                    title: String(
                        localized: "\(host): TLS handshake avg \(DurationFormatter.format(seconds: average)) over \(evidence.count) connections",
                        bundle: RockxyLocalization.bundle
                    ),
                    detail: String(
                        localized: "Repeated handshakes mean connections are not reused.",
                        bundle: RockxyLocalization.bundle
                    ),
                    evidence: evidence.map { reference(samples[$0]) },
                    handoff: .focusHost(host)
                )
            }
    }

    private static func rulesAppliedFinding(
        _ samples: [ResolvedSample],
        index: FindingsIndex,
        evidenceLimit: Int
    )
        -> TrafficInsightsFinding?
    {
        let modified = index.ruleModified
        guard !modified.isEmpty else {
            return nil
        }
        let ruleNames = Array(Set(modified.compactMap { samples[$0].matchedRuleName })).sorted()
        let summary = ruleNames.prefix(3).joined(separator: ", ")
        let evidence = modified.prefix(evidenceLimit)
        return TrafficInsightsFinding(
            kind: .rulesApplied,
            severity: .info,
            title: TrafficInsightsText
                .inflected("^[\(modified.count) request](inflect: true) changed by rules: \(summary)"),
            detail: String(
                localized: "Timing and payloads of these requests do not reflect the real server.",
                bundle: RockxyLocalization.bundle
            ),
            evidence: evidence.map { reference(samples[$0]) },
            handoff: .revealTransactions(evidence.map { samples[$0].id })
        )
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered == "localhost" || lowered == "::1" || lowered.hasPrefix("127.")
            || lowered.hasSuffix(".local") || lowered.hasSuffix(".localhost")
            || lowered.hasPrefix("10.") || lowered.hasPrefix("192.168.")
            || lowered.hasPrefix("0.0.0.0")
    }
}
