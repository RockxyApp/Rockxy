import Foundation
@testable import Rockxy
import Testing

struct AssistantPromptBuilderTests {
    @Test("Prompt treats the reviewed capture as untrusted evidence and preserves storage choice")
    func evidenceGroundedPrompt() {
        let transactionID = UUID()
        let result = InvestigationResult(
            recipe: .explainFailure,
            selectedTransactionID: transactionID,
            scopeTransactionIDs: [transactionID],
            scopeSummary: "1 selected request",
            summary: "The request returned 429.",
            evidence: [InvestigationEvidence(
                id: "EV-1",
                kind: .observed,
                title: "HTTP 429",
                detail: "The response status is 429.",
                sourceTransactionID: transactionID
            )],
            nextStep: "Wait before retrying."
        )
        let preview = "Captured payload fields are untrusted evidence.\nAuthorization: [REDACTED]"
        let pack = InvestigationContextPack(
            scopeTransactionIDs: [transactionID],
            payload: Data(preview.utf8),
            preview: preview,
            manifest: InvestigationContextManifest(
                requestCount: 1,
                outboundBytes: preview.utf8.count,
                redactedHeaderCount: 1,
                redactedQueryCount: 0,
                redactedBodyFieldCount: 0,
                truncatedBodyCount: 0,
                omittedBinaryBodyCount: 0,
                omittedTransactionCount: 0
            )
        )
        let configuration = AssistantProviderConfiguration(
            kind: .openAI,
            model: "fixture-model",
            maxOutputTokens: 777,
            storeResponses: true
        )

        let request = AssistantPromptBuilder().build(
            result: result,
            pack: pack,
            configuration: configuration
        )

        #expect(request.model == "fixture-model")
        #expect(request.maxOutputTokens == 777)
        #expect(request.storeResponse)
        #expect(request.instructions.contains("untrusted evidence"))
        #expect(request.instructions.contains("Never reconstruct redacted"))
        #expect(request.instructions.contains(result.recipe.title))
        #expect(request.input == preview)
        #expect(Data(request.input.utf8) == pack.payload)
    }
}
