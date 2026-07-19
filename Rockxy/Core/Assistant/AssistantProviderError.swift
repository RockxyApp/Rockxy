import Foundation

enum AssistantProviderError: LocalizedError, Equatable {
    case disabled
    case notConfigured
    case credentialMissing
    case invalidEndpoint
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

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .disabled:
            String(localized: "AI Assistant model access is disabled in Settings.")
        case .notConfigured:
            String(localized: "No complete AI Assistant provider is configured.")
        case .credentialMissing:
            String(localized: "The provider credential is missing. Replace it in Settings.")
        case .invalidEndpoint:
            String(localized: "The configured provider endpoint is invalid.")
        case .authentication:
            String(localized: "The provider rejected the saved credential.")
        case .permission:
            String(localized: "The provider credential cannot access this model or endpoint.")
        case let .rateLimited(retryAfterSeconds):
            if let retryAfterSeconds {
                String(localized: "The provider rate limit was reached. Try again in \(retryAfterSeconds) seconds.")
            } else {
                String(localized: "The provider rate limit was reached. Try again later.")
            }
        case let .modelNotFound(model):
            String(localized: "The configured model ‘\(model)’ was not found.")
        case let .validation(message):
            String(localized: "The provider rejected the request: \(message)")
        case let .capabilityMismatch(message):
            String(localized: "The selected model does not support this request: \(message)")
        case let .network(message):
            String(localized: "The provider could not be reached: \(message)")
        case .timedOut:
            String(localized: "The provider request timed out.")
        case let .server(statusCode, message):
            String(localized: "The provider returned HTTP \(statusCode): \(message)")
        case let .malformedResponse(message):
            String(localized: "The provider returned an invalid response: \(message)")
        case .cancelled:
            String(localized: "The provider request was cancelled.")
        }
    }
}
