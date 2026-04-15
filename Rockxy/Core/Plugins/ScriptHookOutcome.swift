import Foundation

// MARK: - RequestHookOutcome

/// Result of running the request-side script hook for a single request.
///
/// The pipeline branches on this value:
/// - `.forward` continues the normal upstream path with the mutated request.
/// - `.blockLocally` short-circuits with an HTTP 403 synthesized locally.
/// - `.mock` short-circuits with the supplied response; the request never goes upstream.
/// - `.mockFailure` indicates the plugin was in mock mode but did not produce a valid
///   response; the pipeline responds 502 locally rather than forwarding upstream.
enum RequestHookOutcome {
    case forward(HTTPRequestData)
    case blockLocally(reason: String)
    case mock(HTTPResponseData)
    case mockFailure(reason: String)
}

// MARK: - ResponseHookOutcome

/// Result of running the response-side script hook for a single response.
///
/// `.modified` means at least one plugin produced a new response; the caller
/// relays and persists the carried `HTTPResponseData`. `.passthrough` means no
/// matching plugin mutated the response; the caller uses the original bytes.
enum ResponseHookOutcome {
    case modified(HTTPResponseData)
    case passthrough
}
