import Foundation
import JavaScriptCore
import os

/// Builds the JS-side `(context, url, request)` and `(context, url, request, response)`
/// argument shapes used by the multi-arg scripting API, and reads the mutated
/// objects back into Swift after `onRequest` / `onResponse` returns.
///
/// The single-arg `onRequest(ctx)` / `onResponse(ctx)` path lives in
/// `ScriptRuntime` directly. Arity is detected at runtime via JS function `length`.
enum ScriptMultiArgBridge {
    // MARK: Internal

    // MARK: - Build JS argument shapes

    /// Build the three positional args for `onRequest(context, url, request)`.
    /// Returns the JS objects so the caller can read mutations back.
    static func buildRequestArgs(
        in jsContext: JSContext,
        request: HTTPRequestData,
        sharedState: JSValue?,
        env: JSValue?,
        configs: JSValue?
    )
        -> (context: JSValue, url: JSValue, request: JSValue)?
    {
        guard let context = JSValue(newObjectIn: jsContext) else {
            return nil
        }
        if let sharedState {
            context.setObject(sharedState, forKeyedSubscript: "sharedState" as NSString)
        }
        if let env {
            context.setObject(env, forKeyedSubscript: "env" as NSString)
        }
        if let configs {
            context.setObject(configs, forKeyedSubscript: "configs" as NSString)
        }

        guard let urlVal = JSValue(object: request.url.absoluteString, in: jsContext) else {
            return nil
        }

        guard let req = JSValue(newObjectIn: jsContext) else {
            return nil
        }
        req.setObject(request.method, forKeyedSubscript: "method" as NSString)
        req.setObject(request.url.scheme ?? "", forKeyedSubscript: "scheme" as NSString)
        req.setObject(request.url.host ?? "", forKeyedSubscript: "host" as NSString)
        if let port = request.url.port {
            req.setObject(port, forKeyedSubscript: "port" as NSString)
        }
        req.setObject(request.url.path.isEmpty ? "/" : request.url.path, forKeyedSubscript: "path" as NSString)

        let headersDict = Dictionary(
            request.headers.map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        req.setObject(headersDict, forKeyedSubscript: "headers" as NSString)

        let queriesDict = parseQueries(request.url.query ?? "")
        req.setObject(queriesDict, forKeyedSubscript: "queries" as NSString)

        // Body — present as a UTF-8 string when decodable; otherwise as a base64 string with `__base64` flag.
        if let body = request.body {
            if let str = String(data: body, encoding: .utf8) {
                req.setObject(str, forKeyedSubscript: "body" as NSString)
            } else {
                req.setObject(body.base64EncodedString(), forKeyedSubscript: "body" as NSString)
                req.setObject(true, forKeyedSubscript: "__bodyIsBase64" as NSString)
            }
        }

        return (context, urlVal, req)
    }

    /// Read mutations from the JS-side `request` object back into a new HTTPRequestData.
    /// The `returnedValue` is the raw return of `onRequest(...)`. If non-null/undefined,
    /// it takes precedence over the in-place `requestArg` mutations.
    static func readRequestMutations(
        original: HTTPRequestData,
        requestArg: JSValue,
        returnedValue: JSValue?,
        pluginID: String
    )
        -> HTTPRequestData
    {
        let source: JSValue = if let returnedValue, !returnedValue.isUndefined, !returnedValue.isNull,
                                 returnedValue.isObject
        {
            returnedValue
        } else {
            requestArg
        }

        let method = (source.objectForKeyedSubscript("method")?.toString() ?? original.method)
        let path = source.objectForKeyedSubscript("path")?.toString() ?? original.url.path
        let queriesDict = parseQueryDictionary(source.objectForKeyedSubscript("queries"))
        let headersDict = (source.objectForKeyedSubscript("headers")?.toDictionary() as? [String: String]) ?? [:]
        let bodyVal = source.objectForKeyedSubscript("body")
        let bodyIsBase64Val = source.objectForKeyedSubscript("__bodyIsBase64")
        let bodyIsBase64 = bodyIsBase64Val?.toBool() ?? false

        let newBody: Data? = if let bodyVal, !bodyVal.isUndefined, !bodyVal.isNull {
            if bodyVal.isString, let s = bodyVal.toString() {
                if bodyIsBase64 {
                    Data(base64Encoded: s)
                } else {
                    s.data(using: .utf8)
                }
            } else if bodyVal.isObject,
                      let dict = bodyVal.toDictionary(),
                      let json = try? JSONSerialization.data(withJSONObject: dict, options: [])
            {
                json
            } else {
                original.body
            }
        } else {
            nil
        }

        // Build URL preserving the original host/port/scheme — those are intentionally
        // not script-mutable (security: cross-host rewrite belongs to MapRemote).
        var components = URLComponents(url: original.url, resolvingAgainstBaseURL: false)
        components?.path = path.isEmpty ? "/" : (path.hasPrefix("/") ? path : "/" + path)
        if !queriesDict.isEmpty {
            components?.queryItems = queriesDict.flatMap { key, values in
                values.map { URLQueryItem(name: key, value: $0) }
            }
        } else if let q = source.objectForKeyedSubscript("queries"), q.isObject, q.toDictionary()?.isEmpty == true {
            components?.queryItems = nil
        }
        let newURL = components?.url ?? original.url

        // Detect (and warn on) attempted host/port/scheme mutations.
        warnIfHostMutated(source: source, original: original, pluginID: pluginID)

        let newHeaders = headersDict.map { HTTPHeader(name: $0.key, value: $0.value) }
        return HTTPRequestData(
            method: method,
            url: newURL,
            httpVersion: original.httpVersion,
            headers: newHeaders,
            body: newBody,
            contentType: ContentTypeDetector.detect(headers: newHeaders, body: newBody)
        )
    }

    /// Build the four positional args for `onResponse(context, url, request, response)`.
    static func buildResponseArgs(
        in jsContext: JSContext,
        request: HTTPRequestData,
        response: HTTPResponseData,
        sharedState: JSValue?,
        env: JSValue?,
        configs: JSValue?
    )
        -> (context: JSValue, url: JSValue, request: JSValue, response: JSValue)?
    {
        guard let triplet = buildRequestArgs(
            in: jsContext, request: request, sharedState: sharedState, env: env, configs: configs
        ) else {
            return nil
        }
        guard let resp = JSValue(newObjectIn: jsContext) else {
            return nil
        }
        resp.setObject(response.statusCode, forKeyedSubscript: "statusCode" as NSString)
        let headersDict = Dictionary(
            response.headers.map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        resp.setObject(headersDict, forKeyedSubscript: "headers" as NSString)
        if let body = response.body {
            if let s = String(data: body, encoding: .utf8) {
                resp.setObject(s, forKeyedSubscript: "body" as NSString)
            } else {
                resp.setObject(body.base64EncodedString(), forKeyedSubscript: "body" as NSString)
                resp.setObject(true, forKeyedSubscript: "__bodyIsBase64" as NSString)
            }
        }
        // bodyFilePath starts undefined; scripts set it to a path string to map a local file.
        return (triplet.context, triplet.url, triplet.request, resp)
    }

    /// Read mutations from the JS-side `response` object back into a new HTTPResponseData.
    /// If `bodyFilePath` is set on the JS object, the body is loaded from disk via
    /// `ScriptResponseBodyLoader` (bounded + sandboxed). Loader errors result in
    /// the file being skipped (warning logged) and the original body retained.
    static func readResponseMutations(
        original: HTTPResponseData,
        responseArg: JSValue,
        returnedValue: JSValue?,
        pluginID: String
    )
        -> HTTPResponseData
    {
        let source: JSValue = if let returnedValue, !returnedValue.isUndefined, !returnedValue.isNull,
                                 returnedValue.isObject
        {
            returnedValue
        } else {
            responseArg
        }

        let statusCode: Int = if let stat = source.objectForKeyedSubscript("statusCode"), !stat.isUndefined,
                                 stat.isNumber
        {
            Int(stat.toInt32())
        } else {
            original.statusCode
        }

        let headersDict = (source.objectForKeyedSubscript("headers")?.toDictionary() as? [String: String]) ?? [:]
        let newHeaders = headersDict.map { HTTPHeader(name: $0.key, value: $0.value) }

        let newBody: Data? = resolveResponseBody(source: source, original: original, pluginID: pluginID)

        let reason = HTTPResponseStatusLookup.reasonPhrase(for: statusCode) ?? original.statusMessage
        return HTTPResponseData(
            statusCode: statusCode,
            statusMessage: reason,
            headers: newHeaders,
            body: newBody,
            bodyTruncated: original.bodyTruncated,
            contentType: ContentTypeDetector.detect(headers: newHeaders, body: newBody)
        )
    }

    // MARK: - Promise awaiting

    /// If `value` is a Promise (any object with a callable `then`), drives it to
    /// resolution by passing `resolve` and `reject` callbacks. Returns true if the
    /// value was a Promise (caller must NOT resume its continuation — the callback
    /// will). Returns false if the value is not a Promise (caller should treat the
    /// value as a synchronous result).
    @discardableResult
    static func awaitPromise(
        _ value: JSValue?,
        in context: JSContext,
        onResolve: @escaping @Sendable (JSValue?) -> Void,
        onReject: @escaping @Sendable (String) -> Void
    )
        -> Bool
    {
        guard let value, value.isObject else {
            return false
        }
        guard let thenFn = value.objectForKeyedSubscript("then"),
              !thenFn.isUndefined, thenFn.isObject else
        {
            return false
        }
        let resolveBlock: @convention(block) (JSValue) -> Void = { resolved in
            onResolve(resolved)
        }
        let rejectBlock: @convention(block) (JSValue) -> Void = { rejected in
            onReject(rejected.toString() ?? "Promise rejected")
        }
        let resolveJS = JSValue(object: resolveBlock, in: context)
        let rejectJS = JSValue(object: rejectBlock, in: context)
        if let resolveJS, let rejectJS {
            thenFn.call(withArguments: [resolveJS, rejectJS])
            // JavaScriptCore queues `then` callbacks as microtasks that only fire
            // when the engine processes its microtask queue. Synchronous Swift→JS
            // call sequences don't auto-drain — we force a drain by evaluating a
            // no-op script, which causes already-resolved Promises to fire their
            // resolve handlers before this function returns.
            _ = context.evaluateScript("undefined;")
        } else {
            return false
        }
        return true
    }

    // MARK: - Function arity detection

    /// Return the JS function's declared parameter count, or nil if not a function.
    static func functionLength(_ value: JSValue?) -> Int? {
        guard let value, value.isObject else {
            return nil
        }
        let lenVal = value.objectForKeyedSubscript("length")
        guard let lenVal, lenVal.isNumber else {
            return nil
        }
        return Int(lenVal.toInt32())
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "ScriptMultiArgBridge"
    )

    nonisolated(unsafe) private static var warnedHostMutations: Set<String> = []
    private static let warnedHostMutationsLock = NSLock()

    private static func resolveResponseBody(
        source: JSValue,
        original: HTTPResponseData,
        pluginID: String
    )
        -> Data?
    {
        // bodyFilePath wins over body if both are set.
        if let pathVal = source.objectForKeyedSubscript("bodyFilePath"),
           !pathVal.isUndefined, !pathVal.isNull,
           let path = pathVal.toString(), !path.isEmpty
        {
            do {
                return try ScriptResponseBodyLoader.load(path: path)
            } catch {
                logger.warning("Plugin \(pluginID) bodyFilePath load failed: \(error.localizedDescription)")
                // fall through to body resolution
            }
        }

        let bodyIsBase64 = source.objectForKeyedSubscript("__bodyIsBase64")?.toBool() ?? false
        if let bodyVal = source.objectForKeyedSubscript("body"), !bodyVal.isUndefined, !bodyVal.isNull {
            if bodyVal.isString, let s = bodyVal.toString() {
                return bodyIsBase64 ? Data(base64Encoded: s) : s.data(using: .utf8)
            }
            if bodyVal.isObject,
               let dict = bodyVal.toDictionary(),
               let json = try? JSONSerialization.data(withJSONObject: dict, options: [])
            {
                return json
            }
        }
        return original.body
    }

    private static func parseQueries(_ query: String) -> [String: [String]] {
        var dict: [String: [String]] = [:]
        guard !query.isEmpty else {
            return dict
        }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first?.removingPercentEncoding else {
                continue
            }
            let value = parts.count > 1 ? (parts[1].removingPercentEncoding ?? "") : ""
            dict[key, default: []].append(value)
        }
        return dict
    }

    private static func parseQueryDictionary(_ value: JSValue?) -> [String: [String]] {
        guard let raw = value?.toDictionary() as? [String: Any] else {
            return [:]
        }
        var queries: [String: [String]] = [:]
        for (key, rawValue) in raw {
            switch rawValue {
            case let string as String:
                queries[key] = [string]
            case let strings as [String]:
                queries[key] = strings
            case let values as [Any]:
                let flattened = values.compactMap { item -> String? in
                    if let string = item as? String {
                        return string
                    }
                    return nil
                }
                queries[key] = flattened
            default:
                continue
            }
        }
        return queries
    }

    private static func warnIfHostMutated(source: JSValue, original: HTTPRequestData, pluginID: String) {
        let kinds: [(String, String?)] = [
            ("host", source.objectForKeyedSubscript("host")?.toString()),
            ("scheme", source.objectForKeyedSubscript("scheme")?.toString()),
        ]
        for (kind, current) in kinds {
            guard let current else {
                continue
            }
            let originalValue: String? = kind == "host" ? original.url.host : original.url.scheme
            if let originalValue, current != originalValue {
                warnOnce(pluginID: pluginID, kind: kind)
            }
        }
        if let portVal = source.objectForKeyedSubscript("port"), portVal.isNumber {
            let p = Int(portVal.toInt32())
            if p != (original.url.port ?? 0) {
                warnOnce(pluginID: pluginID, kind: "port")
            }
        }
    }

    private static func warnOnce(pluginID: String, kind: String) {
        let key = "\(pluginID)|\(kind)"
        warnedHostMutationsLock.lock()
        defer { warnedHostMutationsLock.unlock() }
        guard !warnedHostMutations.contains(key) else {
            return
        }
        warnedHostMutations.insert(key)
        logger.warning(
            "Plugin \(pluginID) attempted to change request \(kind); discarding. Use MapRemote rule action for cross-host rewrite."
        )
    }
}
