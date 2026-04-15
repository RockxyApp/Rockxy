import Foundation
import JavaScriptCore
import os

// Implements script request context behavior for the plugin and scripting subsystem.
//
// Scripts can mutate method, path/query, headers, and body through the wrapper
// helpers (`setHeader`, `setBody`, `setURL`) or by mutating the `request` object.
// Changes to host/port/scheme are intentionally ignored on apply-back — cross-host
// rewrite is the responsibility of the `MapRemote` rule action. See the
// scripting milestone plan for details.

// MARK: - ScriptRequestContext

struct ScriptRequestContext {
    // MARK: Lifecycle

    init(from request: HTTPRequestData) {
        self.method = request.method
        self.url = request.url.absoluteString
        self.originalHost = request.url.host
        self.originalScheme = request.url.scheme
        self.originalPort = request.url.port
        self.headers = Dictionary(
            request.headers.map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        self.body = request.body?.base64EncodedString()
        self.originalBodyBase64 = request.body?.base64EncodedString()
    }

    private init(
        method: String,
        url: String,
        headers: [String: String],
        body: String?,
        originalHost: String?,
        originalScheme: String?,
        originalPort: Int?,
        originalBodyBase64: String?
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.originalHost = originalHost
        self.originalScheme = originalScheme
        self.originalPort = originalPort
        self.originalBodyBase64 = originalBodyBase64
    }

    // MARK: Internal

    var method: String
    var url: String
    var headers: [String: String]
    var body: String?
    let originalHost: String?
    let originalScheme: String?
    let originalPort: Int?
    let originalBodyBase64: String?

    static func from(jsValue: JSValue, original: ScriptRequestContext) -> ScriptRequestContext {
        let request = jsValue.objectForKeyedSubscript("request")

        let method = request?.objectForKeyedSubscript("method")?.toString() ?? original.method
        let url = request?.objectForKeyedSubscript("url")?.toString() ?? original.url

        var headers = original.headers
        if let headersObj = request?.objectForKeyedSubscript("headers"),
           let headersDict = headersObj.toDictionary() as? [String: String]
        {
            headers = headersDict
        }

        let body: String? = if let bodyVal = request?.objectForKeyedSubscript("body"), !bodyVal.isUndefined,
                               !bodyVal.isNull
        {
            bodyVal.toString()
        } else {
            original.body
        }

        return ScriptRequestContext(
            method: method,
            url: url,
            headers: headers,
            body: body,
            originalHost: original.originalHost,
            originalScheme: original.originalScheme,
            originalPort: original.originalPort,
            originalBodyBase64: original.originalBodyBase64
        )
    }

    func toJSValue(in context: JSContext) -> JSValue {
        let wrapper = JSValue(newObjectIn: context)
        let request = JSValue(newObjectIn: context)

        request?.setObject(method, forKeyedSubscript: "method" as NSString)
        request?.setObject(url, forKeyedSubscript: "url" as NSString)
        request?.setObject(headers, forKeyedSubscript: "headers" as NSString)
        request?.setObject(body as Any, forKeyedSubscript: "body" as NSString)

        wrapper?.setObject(request, forKeyedSubscript: "request" as NSString)

        let setHeaderFn: @convention(block) (String, String) -> Void = { name, value in
            let headersObj = request?.objectForKeyedSubscript("headers")
            headersObj?.setObject(value, forKeyedSubscript: name as NSString)
        }
        let setBodyFn: @convention(block) (String) -> Void = { newBody in
            request?.setObject(newBody, forKeyedSubscript: "body" as NSString)
        }
        let setURLFn: @convention(block) (String) -> Void = { newURL in
            request?.setObject(newURL, forKeyedSubscript: "url" as NSString)
        }

        wrapper?.setObject(setHeaderFn, forKeyedSubscript: "setHeader" as NSString)
        wrapper?.setObject(setBodyFn, forKeyedSubscript: "setBody" as NSString)
        wrapper?.setObject(setURLFn, forKeyedSubscript: "setURL" as NSString)

        return wrapper ?? JSValue(undefinedIn: context)
    }

    /// Apply script mutations back onto the outbound request.
    ///
    /// Only the following fields propagate: `method`, path, query, headers, body.
    /// Changes to host, port, or scheme are dropped and a single warning is logged
    /// per-plugin per-mutation-kind. Cross-host rewrite must use `MapRemote` instead.
    func apply(to request: inout HTTPRequestData, pluginID: String) {
        let resolvedURL = URL(string: url) ?? request.url
        let sanitizedURL = Self.sanitizeURLRetainingHost(
            attempted: resolvedURL,
            original: request.url,
            pluginID: pluginID
        )
        // Body decoding policy: scripts may set `body` either via `ctx.setBody("plain")`
        // (UTF-8 string) or by leaving the original base64-seeded value untouched.
        // We try base64 first ONLY when the value looks like base64 of the original
        // body bytes; otherwise we treat it as UTF-8 text. This makes
        // `ctx.setBody("hello world")` actually replace the request body instead of
        // silently falling back to the original.
        let newBody: Data? = if let body {
            if Self.looksLikeOriginalBase64(body, originalBase64: originalBodyBase64),
               let decoded = Data(base64Encoded: body)
            {
                decoded
            } else {
                body.data(using: .utf8) ?? request.body
            }
        } else {
            request.body
        }
        let newHeaders = headers.map { HTTPHeader(name: $0.key, value: $0.value) }

        request = HTTPRequestData(
            method: method,
            url: sanitizedURL,
            httpVersion: request.httpVersion,
            headers: newHeaders,
            body: newBody,
            contentType: request.contentType
        )
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ScriptRequestContext"
    )

    nonisolated(unsafe) private static var warnedMutations: Set<String> = []
    nonisolated(unsafe) private static var warnedMutationOrder: [String] = []
    private static let warnedMutationsLock = NSLock()
    private static let warnedMutationLimit = 256

    private static func sanitizeURLRetainingHost(
        attempted: URL,
        original: URL,
        pluginID: String
    )
        -> URL
    {
        var attemptedComponents = URLComponents(url: attempted, resolvingAgainstBaseURL: false)
        let originalComponents = URLComponents(url: original, resolvingAgainstBaseURL: false)

        if attempted.host != original.host {
            warnOnce(pluginID: pluginID, mutationKind: "host")
            attemptedComponents?.host = originalComponents?.host
        }
        if attempted.scheme != original.scheme {
            warnOnce(pluginID: pluginID, mutationKind: "scheme")
            attemptedComponents?.scheme = originalComponents?.scheme
        }
        if attempted.port != original.port {
            warnOnce(pluginID: pluginID, mutationKind: "port")
            attemptedComponents?.port = originalComponents?.port
        }

        return attemptedComponents?.url ?? original
    }

    /// Did the script leave the body as the unchanged base64 of the original?
    /// Used to decide whether to decode as base64 vs treat as UTF-8 plain text.
    private static func looksLikeOriginalBase64(_ candidate: String, originalBase64: String?) -> Bool {
        guard let originalBase64 else {
            return false
        }
        return candidate == originalBase64
    }

    private static func warnOnce(pluginID: String, mutationKind: String) {
        let key = "\(pluginID)|\(mutationKind)"
        warnedMutationsLock.lock()
        defer { warnedMutationsLock.unlock() }
        guard !warnedMutations.contains(key) else {
            return
        }
        warnedMutations.insert(key)
        warnedMutationOrder.append(key)
        if warnedMutationOrder.count > warnedMutationLimit,
           let evicted = warnedMutationOrder.first
        {
            warnedMutationOrder.removeFirst()
            warnedMutations.remove(evicted)
        }
        logger.warning(
            "Plugin \(pluginID) attempted to change request \(mutationKind); discarding. Use MapRemote rule action for cross-host rewrite."
        )
    }
}
