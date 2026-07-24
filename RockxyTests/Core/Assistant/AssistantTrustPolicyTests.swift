import Foundation
@testable import Rockxy
import Testing

// MARK: - AssistantTrustPolicyTests

struct AssistantTrustPolicyTests {
    @Test("Assistant defaults to selected-only read-only analysis")
    func safeDefaults() {
        #expect(AssistantTrustPolicy.defaultTrafficScope == .selectedOnly)
        #expect(!AssistantTrustPolicy.permitsDirectMutation)
    }

    @Test("Reviewed model data must stay inside the deterministic investigation scope")
    func validatesReviewedScope() {
        let selectedID = UUID()
        let relatedID = UUID()
        let result = InvestigationResult(
            recipe: .explainFailure,
            selectedTransactionID: selectedID,
            scopeTransactionIDs: [selectedID, relatedID],
            scopeSummary: "2 requests",
            summary: "Summary",
            evidence: [],
            nextStep: "Next"
        )

        #expect(AssistantTrustPolicy.isReviewedScopeValid(pack(ids: [selectedID, relatedID]), for: result))
        #expect(!AssistantTrustPolicy.isReviewedScopeValid(pack(ids: [relatedID, selectedID]), for: result))
        #expect(!AssistantTrustPolicy.isReviewedScopeValid(pack(ids: [selectedID, UUID()]), for: result))
    }

    private func pack(ids: [UUID]) -> InvestigationContextPack {
        InvestigationContextPack(
            scopeTransactionIDs: ids,
            payload: Data("{}".utf8),
            preview: "{}",
            manifest: InvestigationContextManifest(
                requestCount: ids.count,
                outboundBytes: 2,
                redactedHeaderCount: 0,
                redactedQueryCount: 0,
                redactedBodyFieldCount: 0,
                truncatedBodyCount: 0,
                omittedBinaryBodyCount: 0,
                omittedTransactionCount: 0
            )
        )
    }
}
