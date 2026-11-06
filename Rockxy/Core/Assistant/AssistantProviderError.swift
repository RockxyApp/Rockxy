import Foundation

enum AssistantProviderError: LocalizedError, Equatable {
    case disabled
    case notConfigured
    case credentialMissing
    case invalidEndpoint
    case insecureEndpoint
    case authentication
    case permission
    case rateLimited(retryAfterSeconds: Int?)
    case modelNotFound(String)
    case validation(String)
    case capabilityMismatch(String)
    case network(String)
    case timedOut
    case server(statusCode: Int, message: String)
    case malformedResponse(String)
    case cancelled
    /// The provider is temporarily overloaded (Anthropic 529, `overloaded_error`).
    case overloaded(retryAfterSeconds: Int?)
    /// The provider stopped or refused the answer for safety or content-policy reasons.
    case contentBlocked(String)
    /// The provider reported a failed response inside an otherwise successful HTTP stream.
    case responseFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .disabled:
            String(localized: "AI Assistant model access is disabled in Settings.", bundle: RockxyLocalization.bundle)
        case .notConfigured:
            String(localized: "No complete AI Assistant provider is configured.", bundle: RockxyLocalization.bundle)
        case .credentialMissing:
            String(
                localized: "The provider credential is missing. Replace it in Settings.",
                bundle: RockxyLocalization.bundle
            )
        case .invalidEndpoint:
            String(localized: "The configured provider endpoint is invalid.", bundle: RockxyLocalization.bundle)
        case .insecureEndpoint:
            String(
                localized: "Remote model endpoints must use HTTPS. Plain HTTP is allowed only on this Mac.",
                bundle: RockxyLocalization.bundle
            )
        case .authentication:
            String(localized: "The provider rejected the saved credential.", bundle: RockxyLocalization.bundle)
        case .permission:
            String(
                localized: "The provider credential cannot access this model or endpoint.",
                bundle: RockxyLocalization.bundle
            )
        case let .rateLimited(retryAfterSeconds):
            if let retryAfterSeconds {
                String(AttributedString(
                    localized: "The provider rate limit was reached. Try again in ^[\(retryAfterSeconds) second](inflect: true).",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters)
            } else {
                String(
                    localized: "The provider rate limit was reached. Try again later.",
                    bundle: RockxyLocalization.bundle
                )
            }
        case let .modelNotFound(model):
            String(localized: "The configured model ‘\(model)’ was not found.", bundle: RockxyLocalization.bundle)
        case let .validation(message):
            String(localized: "The provider rejected the request: \(message)", bundle: RockxyLocalization.bundle)
        case let .capabilityMismatch(message):
            String(
                localized: "The selected model does not support this request: \(message)",
                bundle: RockxyLocalization.bundle
            )
        case let .network(message):
            String(localized: "The provider could not be reached: \(message)", bundle: RockxyLocalization.bundle)
        case .timedOut:
            String(localized: "The provider request timed out.", bundle: RockxyLocalization.bundle)
        case let .server(statusCode, message):
            String(localized: "The provider returned HTTP \(statusCode): \(message)", bundle: RockxyLocalization.bundle)
        case let .malformedResponse(message):
            String(
                localized: "The provider returned an invalid response: \(message)",
                bundle: RockxyLocalization.bundle
            )
        case .cancelled:
            String(localized: "The provider request was cancelled.", bundle: RockxyLocalization.bundle)
        case let .overloaded(retryAfterSeconds):
            if let retryAfterSeconds {
                String(AttributedString(
                    localized: "The provider is overloaded right now. Try again in ^[\(retryAfterSeconds) second](inflect: true).",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters)
            } else {
                String(
                    localized: "The provider is overloaded right now. Try again in a moment.",
                    bundle: RockxyLocalization.bundle
                )
            }
        case let .contentBlocked(reason):
            String(
                localized: "The provider blocked this answer for safety or content-policy reasons (\(reason)).",
                bundle: RockxyLocalization.bundle
            )
        case let .responseFailed(message):
            String(localized: "The provider stopped the response: \(message)", bundle: RockxyLocalization.bundle)
        }
    }
}
