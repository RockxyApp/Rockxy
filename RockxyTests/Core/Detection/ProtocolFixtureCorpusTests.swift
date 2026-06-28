import Foundation
import Testing

@Suite("Protocol Fixture Corpus")
struct ProtocolFixtureCorpusTests {
    @Test("Fixture IDs are unique and stable")
    func fixtureIDsAreUniqueAndStable() {
        let ids = ProtocolFixtureCorpus.fixtures.map(\.id)

        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.contains(" ") })
        #expect(ids.allSatisfy { $0.contains(".") })
    }

    @Test("Fixtures satisfy the shared schema contract")
    func fixturesSatisfySharedSchemaContract() {
        let failures = ProtocolFixtureCorpus.fixtures.flatMap(ProtocolFixtureValidation.validate)

        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n")))
    }

    @Test("Corpus covers foundation protocol families")
    func corpusCoversFoundationProtocolFamilies() {
        let families = Set(ProtocolFixtureCorpus.fixtures.map(\.family))

        #expect(families.isSuperset(of: [.ordinaryHTTP, .ai, .web3RPC, .x402, .unknown]))
    }

    @Test("Protocol fixtures include UX contract expectations")
    func protocolFixturesIncludeUXContractExpectations() {
        for fixture in ProtocolFixtureCorpus.fixtures where fixture.family != .ordinaryHTTP {
            let ux = fixture.expected.ux

            #expect(!ux.requestListBadges.isEmpty, "\(fixture.id) must declare request-list badge expectations")
            #expect(!ux.optionalColumns.isEmpty, "\(fixture.id) must declare optional-column expectations")
            #expect(!ux.inspectorTabs.isEmpty, "\(fixture.id) must declare inspector-tab expectations")
            #expect(!ux.exportSummaryFields.isEmpty, "\(fixture.id) must declare export-summary expectations")
            #expect(!ux.mcpSummaryFields.isEmpty, "\(fixture.id) must declare MCP-summary expectations")
        }
    }

    @Test("Malformed fixtures declare bounded fallback behavior")
    func malformedFixturesDeclareFallbackBehavior() {
        let malformedFixtures = ProtocolFixtureCorpus.fixtures.filter { $0.safetyClass == .malformed }

        #expect(!malformedFixtures.isEmpty)
        for fixture in malformedFixtures {
            #expect(fixture.expected.ux.fallbackBehavior != nil, "\(fixture.id) must declare fallback behavior")
            #expect(fixture.expected.metadataHints.contains("fallback"), "\(fixture.id) must include fallback metadata hint")
        }
    }

    @Test("Corpus passes public safety scan")
    func corpusPassesPublicSafetyScan() {
        let findings = ProtocolFixtureCorpus.fixtures.flatMap(ProtocolFixtureSafetyScanner.scan)

        #expect(findings.isEmpty, Comment(rawValue: findings.map(formatFinding).joined(separator: "\n")))
    }

    @Test("Safety scanner catches local paths")
    func safetyScannerCatchesLocalPaths() {
        let findings = ProtocolFixtureSafetyScanner.scan(text: #"{"path":"/Users/example/private.json"}"#)

        #expect(findings.contains { $0.reason.contains("local filesystem path") })
    }

    @Test("Safety scanner catches production-looking tokens")
    func safetyScannerCatchesProductionLookingTokens() {
        let findings = ProtocolFixtureSafetyScanner.scan(text: "Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456")

        #expect(findings.contains { $0.reason.contains("bearer token") })
    }

    @Test("Safety scanner allows synthetic token placeholders")
    func safetyScannerAllowsSyntheticTokenPlaceholders() {
        let findings = ProtocolFixtureSafetyScanner.scan(text: "Authorization: Bearer synthetic-ai-token")

        #expect(findings.isEmpty)
    }

    @Test("Safety scanner catches non-synthetic hosts in messages")
    func safetyScannerCatchesNonSyntheticHosts() {
        let fixture = ProtocolFixture(
            id: "manual.real-host",
            title: "Manual real host fixture",
            family: .ordinaryHTTP,
            scenarioTags: ["manual"],
            traffic: ProtocolFixtureTraffic(exchanges: [
                ProtocolFixtureExchange(
                    request: ProtocolFixtureMessage(method: "GET", url: "https://production.example.net/data")
                )
            ]),
            expected: ProtocolFixtureExpectations(
                metadataHints: ["manual"],
                redaction: ProtocolFixtureRedactionExpectation(
                    sensitiveFields: [],
                    redactedMarkers: [],
                    safeFields: []
                ),
                ux: ProtocolFixtureUXExpectation(
                    requestListBadges: ["Manual"],
                    optionalColumns: ["kind": "manual"],
                    inspectorTabs: ["Raw"],
                    warningStates: [],
                    exportSummaryFields: ["host"],
                    mcpSummaryFields: ["host"],
                    fallbackBehavior: nil
                )
            ),
            safetyClass: .ordinary,
            sizeClass: .small,
            traceability: ProtocolFixtureTraceability(parentIssue: 176, childIssues: [186], futureIssues: [])
        )

        let findings = ProtocolFixtureSafetyScanner.scan(fixture)

        #expect(findings.contains { $0.reason.contains("non-synthetic host") })
    }

    @Test("Safety scanner catches private-key-like material")
    func safetyScannerCatchesPrivateKeyLikeMaterial() {
        let findings = ProtocolFixtureSafetyScanner.scan(text: "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")

        #expect(findings.contains { $0.reason.contains("private-key-like") })
    }

    @Test("Safety scanner allows example.com email placeholders")
    func safetyScannerAllowsExampleEmailPlaceholders() {
        let findings = ProtocolFixtureSafetyScanner.scan(text: "owner@example.com")

        #expect(findings.isEmpty)
    }

    @Test("Safety scanner catches personal email-like values")
    func safetyScannerCatchesPersonalEmailLikeValues() {
        let findings = ProtocolFixtureSafetyScanner.scan(text: "owner@real-company.invalid")

        #expect(findings.contains { $0.reason.contains("personal email-like") })
    }

    @Test("Fixtures trace back to parent and Group A child issues")
    func fixturesTraceBackToParentAndGroupAChildIssues() {
        let requiredChildIssues: Set<Int> = [186, 187, 194, 195]
        let requiredFutureIssues: Set<Int> = [143, 144, 145, 146, 177, 178, 179, 180]

        for fixture in ProtocolFixtureCorpus.fixtures {
            #expect(fixture.traceability.parentIssue == 176)
            #expect(fixture.traceability.childIssues.isSuperset(of: requiredChildIssues))
            #expect(fixture.traceability.futureIssues.isSuperset(of: requiredFutureIssues))
        }
    }

    private func formatFinding(_ finding: ProtocolFixtureSafetyScanner.Finding) -> String {
        "\(finding.fixtureID): \(finding.reason): \(finding.excerpt)"
    }
}
