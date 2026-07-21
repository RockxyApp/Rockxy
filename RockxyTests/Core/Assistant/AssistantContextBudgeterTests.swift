@testable import Rockxy
import Testing

struct AssistantContextBudgeterTests {
    @Test("Local context allocation reserves instructions, output, and safety headroom")
    func localAllocation() {
        let configuration = AssistantProviderConfiguration(
            kind: .ollama,
            model: "fixture",
            contextWindowTokens: 8_192,
            maxOutputTokens: 4_096
        )

        let plan = AssistantContextBudgeter().plan(for: configuration)

        #expect(plan.contextWindowTokens == 8_192)
        #expect(plan.maxOutputTokens == 2_048)
        #expect(plan.estimatedInputTokenBudget == 4_608)
        #expect(plan.maxOutboundBytes == 13_824)
    }

    @Test("Legacy local profiles receive a conservative context default")
    func localDefault() {
        let configuration = AssistantProviderConfiguration(kind: .ollama, model: "fixture")

        let plan = AssistantContextBudgeter().plan(for: configuration)

        #expect(plan.contextWindowTokens == AssistantProviderConfiguration.defaultLocalContextWindowTokens)
        #expect(plan.maxOutputTokens == AssistantProviderConfiguration.defaultMaxOutputTokens)
        #expect(plan.maxOutboundBytes < InvestigationContextLimits.default.maxOutboundBytes)
    }

    @Test("Remote providers without verified context metadata keep the global byte ceiling")
    func unknownRemoteContext() {
        let configuration = AssistantProviderConfiguration(kind: .openAI, model: "fixture")

        let plan = AssistantContextBudgeter().plan(for: configuration)

        #expect(plan.contextWindowTokens == nil)
        #expect(plan.estimatedInputTokenBudget == nil)
        #expect(plan.maxOutboundBytes == InvestigationContextLimits.default.maxOutboundBytes)
    }

    @Test("Review Data limits match the inference allocation")
    func reviewLimits() {
        let configuration = AssistantProviderConfiguration(
            kind: .ollama,
            model: "fixture",
            contextWindowTokens: 4_096,
            maxOutputTokens: 2_048
        )
        let budgeter = AssistantContextBudgeter()

        let plan = budgeter.plan(for: configuration)
        let limits = budgeter.contextLimits(for: configuration)

        #expect(plan.maxOutputTokens == 1_024)
        #expect(limits.maxOutboundBytes == plan.maxOutboundBytes)
        #expect(limits.maxBodyBytes <= InvestigationContextLimits.default.maxBodyBytes)
    }
}
