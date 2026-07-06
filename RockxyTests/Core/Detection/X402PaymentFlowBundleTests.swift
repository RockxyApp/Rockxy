import Foundation
import Testing

@Suite("x402 Payment Flow Bundle")
struct X402PaymentFlowBundleTests {
    @Test("Bundle decodes and covers required x402 flow cases")
    func bundleDecodesAndCoversRequiredCases() throws {
        let bundle = try loadBundle()
        let cases = try requiredArray(bundle["cases"], named: "cases")
        let caseNames = Set(try cases.map { try requiredString($0["case"], named: "case") })

        #expect(bundle["bundle"] as? String == "rockxy_x402_payment_flow_detection_fixtures")
        #expect(bundle["schema_version"] as? String == "fixture.x402.flow.v1")
        #expect(caseNames.isSuperset(of: [
            "unpaid_x402",
            "malformed_metadata",
            "verification_failure",
            "settled_retry_shape",
            "ordinary_non_x402_402",
            "settlement_failure",
        ]))
    }

    @Test("Each case declares detection, flow, redaction, and severity expectations")
    func casesDeclareExpectedOutcomes() throws {
        let cases = try requiredArray(loadBundle()["cases"], named: "cases")

        for item in cases {
            let name = try requiredString(item["case"], named: "case")
            let expected = try requiredObject(item["expected"], named: "\(name).expected")

            _ = try requiredString(expected["detect"], named: "\(name).expected.detect")
            _ = try requiredString(expected["flow"], named: "\(name).expected.flow")
            _ = try requiredArray(expected["redact"], named: "\(name).expected.redact")
            _ = try requiredString(expected["severity"], named: "\(name).expected.severity")
        }
    }

    @Test("Every case preserves its expected detection, flow, and severity values")
    func casesPreserveExpectedOutcomeValues() throws {
        let expectedOutcomes: [String: (detect: String, flow: String, severity: String)] = [
            "unpaid_x402": (
                detect: "x402_payment_required",
                flow: "partial",
                severity: "needs_payment_not_error"
            ),
            "malformed_metadata": (
                detect: "possible_x402_payment_required",
                flow: "partial_invalid_metadata",
                severity: "protocol_metadata_warning"
            ),
            "verification_failure": (
                detect: "x402_payment_attempt_failed",
                flow: "attempted_unsettled",
                severity: "payment_verification_failed"
            ),
            "settled_retry_shape": (
                detect: "x402_settled_retry",
                flow: "completed",
                severity: "success"
            ),
            "ordinary_non_x402_402": (
                detect: "ordinary_http_402",
                flow: "single_response",
                severity: "inspectable_http_status"
            ),
            "settlement_failure": (
                detect: "x402_settlement_failed",
                flow: "attempted_unsettled",
                severity: "payment_settlement_failed"
            ),
        ]

        for (name, outcome) in expectedOutcomes {
            let expected = try requiredObject(caseNamed(name)["expected"], named: "\(name).expected")

            #expect(expected["detect"] as? String == outcome.detect)
            #expect(expected["flow"] as? String == outcome.flow)
            #expect(expected["severity"] as? String == outcome.severity)
        }
    }

    @Test("Ordinary HTTP 402 remains separate from x402 payment metadata")
    func ordinaryHTTP402IsNotClassifiedAsX402() throws {
        let item = try caseNamed("ordinary_non_x402_402")
        let response = try requiredObject(item["response"], named: "response")
        let headers = try requiredObject(response["headers"], named: "response.headers")
        let expected = try requiredObject(item["expected"], named: "expected")
        let diagnostics = try requiredStringArray(expected["diagnostics"], named: "expected.diagnostics")

        #expect(response["status"] as? Int == 402)
        #expect(expected["detect"] as? String == "ordinary_http_402")
        #expect(expected["flow"] as? String == "single_response")
        #expect(headers["payment-required"] == nil)
        #expect(headers["www-authenticate"] == nil)
        #expect(headers["x-payment"] == nil)
        #expect(diagnostics.contains("no_x402_payment_metadata"))
        #expect(diagnostics.contains("no_payment_lifecycle_grouping"))
    }

    @Test("Settlement failure records payment attempt and failed settlement response")
    func settlementFailureCoversAttemptedUnsettledFlow() throws {
        let item = try caseNamed("settlement_failure")
        let requests = try requiredArray(item["request_sequence"], named: "request_sequence")
        let responses = try requiredArray(item["response_sequence"], named: "response_sequence")
        let expected = try requiredObject(item["expected"], named: "expected")
        let redacted = try requiredStringArray(expected["redact"], named: "expected.redact")
        let retry = try #require(requests.first { $0["step"] as? String == "retry_with_payment_payload" })
        let retryHeaders = try requiredObject(retry["headers"], named: "retry.headers")
        let failure = try #require(responses.first { $0["step"] as? String == "settlement_failed" })
        let failureBody = try requiredObject(failure["body"], named: "settlement_failed.body")

        #expect(retryHeaders["x-payment"] as? String == "[REDACTED_SYNTHETIC_PAYMENT_PAYLOAD]")
        #expect(failure["status"] as? Int == 402)
        #expect(failureBody["failure_class"] as? String == "settlement_failure")
        #expect(expected["detect"] as? String == "x402_settlement_failed")
        #expect(expected["flow"] as? String == "attempted_unsettled")
        #expect(Set(redacted).isSuperset(of: ["x-payment", "payment-required", "settlement_reference"]))
    }

    @Test("Bundle redaction policy and safety metadata protect payment secrets")
    func bundleSafetyMetadataProtectsPaymentSecrets() throws {
        let bundle = try loadBundle()
        let policy = try requiredObject(bundle["redaction_policy"], named: "redaction_policy")
        let safety = try requiredObject(bundle["safety"], named: "safety")
        let headers = Set(try requiredStringArray(policy["always_redact_headers"], named: "always_redact_headers"))
        let raw = try String(contentsOf: fixtureURL(), encoding: .utf8)
        let findings = ProtocolFixtureSafetyScanner.scan(text: raw, fixtureID: "x402-payment-flow-bundle.v1")

        #expect(headers.isSuperset(of: [
            "payment-required",
            "www-authenticate",
            "authorization",
            "x-payment",
            "x-payment-response",
        ]))
        #expect(safety["private_keys"] as? String == "none")
        #expect(safety["seed_phrases"] as? String == "none")
        #expect(safety["bearer_tokens"] as? String == "none")
        #expect(findings.isEmpty, Comment(rawValue: findings.map { "\($0.reason): \($0.excerpt)" }.joined(separator: "\n")))
    }

    private func caseNamed(_ name: String) throws -> [String: Any] {
        let cases = try requiredArray(loadBundle()["cases"], named: "cases")
        return try #require(cases.first { $0["case"] as? String == name })
    }

    private func loadBundle() throws -> [String: Any] {
        let data = try Data(contentsOf: fixtureURL())
        let value = try JSONSerialization.jsonObject(with: data)
        return try #require(value as? [String: Any])
    }

    private func fixtureURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "RockxyTests", url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        let fixture = url.appendingPathComponent("Fixtures/x402-payment-flow-bundle.v1.json")
        #expect(FileManager.default.fileExists(atPath: fixture.path))
        return fixture
    }

    private func requiredObject(_ value: Any?, named name: String) throws -> [String: Any] {
        let object = value as? [String: Any]
        #expect(object != nil, "\(name) must be an object")
        return try #require(object)
    }

    private func requiredArray(_ value: Any?, named name: String) throws -> [[String: Any]] {
        let array = value as? [[String: Any]]
        #expect(array != nil, "\(name) must be an array of objects")
        return try #require(array)
    }

    private func requiredString(_ value: Any?, named name: String) throws -> String {
        let string = value as? String
        #expect(string != nil, "\(name) must be a string")
        return try #require(string)
    }

    private func requiredStringArray(_ value: Any?, named name: String) throws -> [String] {
        let array = value as? [String]
        #expect(array != nil, "\(name) must be an array of strings")
        return try #require(array)
    }
}
