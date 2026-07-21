import Foundation

// MARK: - AssistantContextPlan

/// A conservative prompt allocation shared by Review Data and the provider request.
/// The estimate intentionally leaves room for provider chat templates and tokenization variance.
struct AssistantContextPlan: Equatable, Sendable {
    let contextWindowTokens: Int?
    let maxOutputTokens: Int
    let estimatedInputTokenBudget: Int?
    let maxOutboundBytes: Int
}

// MARK: - AssistantContextBudgeter

struct AssistantContextBudgeter {
    // MARK: Internal

    func plan(for configuration: AssistantProviderConfiguration) -> AssistantContextPlan {
        let configuredOutput = AssistantProviderConfiguration.validMaxOutputTokens(
            configuration.maxOutputTokens
        )
        guard let contextWindow = configuration.effectiveContextWindowTokens else {
            return AssistantContextPlan(
                contextWindowTokens: nil,
                maxOutputTokens: configuredOutput,
                estimatedInputTokenBudget: nil,
                maxOutboundBytes: InvestigationContextLimits.default.maxOutboundBytes
            )
        }

        let instructionReserve = min(Self.maxInstructionReserveTokens, max(256, contextWindow / 8))
        let safetyReserve = min(Self.maxSafetyReserveTokens, max(128, contextWindow / 16))
        let outputCeiling = max(Self.minOutputTokens, contextWindow / 4)
        let outputTokens = min(configuredOutput, outputCeiling)
        let inputTokens = max(
            Self.minEvidenceTokens,
            contextWindow - instructionReserve - safetyReserve - outputTokens
        )
        let byteBudget = min(
            InvestigationContextLimits.default.maxOutboundBytes,
            max(Self.minEvidenceBytes, inputTokens * Self.conservativeBytesPerToken)
        )

        return AssistantContextPlan(
            contextWindowTokens: contextWindow,
            maxOutputTokens: outputTokens,
            estimatedInputTokenBudget: inputTokens,
            maxOutboundBytes: byteBudget
        )
    }

    func contextLimits(for configuration: AssistantProviderConfiguration) -> InvestigationContextLimits {
        let plan = plan(for: configuration)
        var limits = InvestigationContextLimits.default
        limits.maxOutboundBytes = plan.maxOutboundBytes
        limits.maxBodyBytes = min(
            limits.maxBodyBytes,
            max(512, plan.maxOutboundBytes / max(1, limits.maxTransactions * 2))
        )
        return limits
    }

    // MARK: Private

    private static let conservativeBytesPerToken = 3
    private static let maxInstructionReserveTokens = 1_024
    private static let maxSafetyReserveTokens = 512
    private static let minOutputTokens = 256
    private static let minEvidenceTokens = 384
    private static let minEvidenceBytes = 4 * 1_024
}
