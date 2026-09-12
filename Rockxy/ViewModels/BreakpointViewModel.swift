import Foundation

// Defines the breakpoint request, response, and decision types shared across breakpoint
// workflows.

// MARK: - BreakpointPhase

/// Whether the breakpoint fires on the outgoing request or the incoming response.
enum BreakpointPhase {
    case request
    case response
}

// MARK: - BreakpointDecision

/// The user's chosen action when a breakpoint-paused request is presented.
enum BreakpointDecision {
    /// Forward the (potentially modified) request to the upstream server.
    case execute
    /// Drop the request and return a 503 Service Unavailable response.
    case abort
    /// Forward the original paused message without applying the current draft.
    case cancel
}

// MARK: - BreakpointRequestData

/// Editable snapshot of an intercepted HTTP request/response shown in the breakpoint sheet.
struct BreakpointRequestData {
    var method: String
    var url: String
    var headers: [EditableHeader]
    var body: String
    var statusCode: Int
    var phase: BreakpointPhase = .request
    var isBodyEditable = true
    var fixedHTTPSAuthority: String?
    var matchedRuleName: String?

    /// Whether the original request uses HTTPS. Used by the breakpoint editor to constrain
    /// the URL editor so the user can only modify path and query — the host is fixed by the
    /// TLS tunnel and cannot be changed mid-connection.
    var isHTTPS: Bool {
        url.lowercased().hasPrefix("https://")
    }

    /// Phase-aware validation shared by the structured editor and proxy builders.
    /// Origin-form targets remain valid because Raw editing intentionally exposes
    /// the HTTP request line while preserving the captured connection authority.
    var executionValidationMessage: String? {
        if phase == .request {
            if url.utf8.count > ProxyLimits.maxURILength {
                return String(
                    localized: "The edited request URL exceeds Rockxy's safety limit.",
                    bundle: RockxyLocalization.bundle
                )
            }
            let normalizedMethod = method.trimmingCharacters(in: .whitespacesAndNewlines)
            if !Self.isValidHTTPToken(normalizedMethod) {
                return String(localized: "Enter a valid HTTP method.", bundle: RockxyLocalization.bundle)
            }

            if url.hasPrefix("/") {
                guard let target = URLComponents(string: url),
                      !target.percentEncodedPath.isEmpty else
                {
                    return String(localized: "Enter a valid request path.", bundle: RockxyLocalization.bundle)
                }
            } else {
                guard let components = URLComponents(string: url),
                      let scheme = components.scheme?.lowercased(),
                      scheme == "http" || scheme == "https",
                      let host = components.host,
                      !host.isEmpty,
                      components.url != nil else
                {
                    return String(localized: "Enter a valid HTTP URL with a host.", bundle: RockxyLocalization.bundle)
                }
            }
        } else if !(100 ... 599).contains(statusCode) {
            return String(localized: "Enter a valid HTTP status code.", bundle: RockxyLocalization.bundle)
        }

        if Self.bodyExceedsLimit(body, phase: phase) {
            return String(
                localized: "The edited message body exceeds Rockxy's safety limit.",
                bundle: RockxyLocalization.bundle
            )
        }

        for header in headers {
            if !Self.isValidHTTPHeaderName(header.name) {
                return String(localized: "Header names must use valid HTTP token characters.", bundle: RockxyLocalization.bundle)
            }
            if !Self.isValidHTTPHeaderValue(header.value) {
                return String(localized: "Header values cannot contain line breaks.", bundle: RockxyLocalization.bundle)
            }
        }
        return nil
    }

    var requestLimitViolationStatusCode: Int? {
        guard phase == .request else {
            return nil
        }
        return Self.requestLimitViolationStatusCode(url: url, body: body)
    }

    static func requestLimitViolationStatusCode(
        url: String,
        body: String,
        urlLimit: Int = ProxyLimits.maxURILength,
        bodyLimit: Int = ProxyLimits.maxRequestBodySize
    ) -> Int? {
        if url.utf8.count > urlLimit {
            return 414
        }
        if Self.bodyExceedsLimit(body, phase: .request, requestLimit: bodyLimit) {
            return 413
        }
        return nil
    }

    /// Projects captured bytes into the text-only breakpoint editor without
    /// claiming that a lossy conversion is editable.
    static func editableBodyProjection(from data: Data?) -> (text: String, isEditable: Bool) {
        guard let data else {
            return ("", true)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return ("", false)
        }
        return (text, true)
    }

    /// Applies an origin-form request target while preserving its percent-
    /// encoded delimiters and the current connection authority.
    static func applyingOriginForm(_ value: String, to currentURL: String) -> String? {
        let normalized = value.hasPrefix("/") ? value : "/\(value)"
        guard let editedTarget = URLComponents(string: normalized),
              var components = URLComponents(string: currentURL)
        else {
            return nil
        }
        components.percentEncodedPath = editedTarget.percentEncodedPath
        components.percentEncodedQuery = editedTarget.percentEncodedQuery
        return components.string
    }

    static func isValidHTTPHeaderName(_ name: String) -> Bool {
        isValidHTTPToken(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isValidHTTPHeaderValue(_ value: String) -> Bool {
        !value.unicodeScalars.contains { scalar in
            scalar.value == 0 || scalar.value == 10 || scalar.value == 13
        }
    }

    static func bodyExceedsLimit(
        _ body: String,
        phase: BreakpointPhase,
        requestLimit: Int = ProxyLimits.maxRequestBodySize,
        responseLimit: Int = ProxyLimits.maxResponseBodySize
    ) -> Bool {
        let limit = switch phase {
        case .request: requestLimit
        case .response: responseLimit
        }
        return body.utf8.count > limit
    }

    private static func isValidHTTPToken(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }
        let allowedPunctuation = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~")
        return value.unicodeScalars.allSatisfy {
            $0.value < 128
                && (CharacterSet.alphanumerics.contains($0) || allowedPunctuation.contains($0))
        }
    }
}

// MARK: - EditableHeader

/// A mutable header name-value pair for the breakpoint editor table.
struct EditableHeader: Identifiable {
    let id = UUID()
    var name: String
    var value: String
}
