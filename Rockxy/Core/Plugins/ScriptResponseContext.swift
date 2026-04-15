import Foundation
import JavaScriptCore

// Implements script response context behavior for the plugin and scripting subsystem.
// The context is mutable: scripts may change `statusCode`, `headers`, or `body`
// from `onResponse(ctx)` either by mutating the JS object returned to Swift or by
// calling the `setStatus`, `setHeader`, or `setBody` helpers exposed on the wrapper.

// MARK: - ScriptResponseContext

struct ScriptResponseContext {
    // MARK: Lifecycle

    init(request: HTTPRequestData, response: HTTPResponseData) {
        self.method = request.method
        self.url = request.url.absoluteString
        self.requestHeaders = Dictionary(
            request.headers.map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        self.statusCode = response.statusCode
        self.responseHeaders = Dictionary(
            response.headers.map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        if let body = response.body {
            let utf8String = String(data: body, encoding: .utf8)
            self.body = utf8String ?? body.base64EncodedString()
            self.bodyIsUTF8 = utf8String != nil
        } else {
            self.body = nil
            self.bodyIsUTF8 = true
        }
    }

    private init(
        method: String,
        url: String,
        requestHeaders: [String: String],
        statusCode: Int,
        responseHeaders: [String: String],
        body: String?,
        bodyIsUTF8: Bool
    ) {
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.body = body
        self.bodyIsUTF8 = bodyIsUTF8
    }

    // MARK: Internal

    let method: String
    let url: String
    let requestHeaders: [String: String]
    var statusCode: Int
    var responseHeaders: [String: String]
    var body: String?
    /// Whether `body` is UTF-8 text. When false, `body` holds a base64-encoded string.
    var bodyIsUTF8: Bool

    /// Rebuild a context from the JS value returned by `onResponse`. Any fields missing
    /// on the returned object fall back to `original` so scripts that only set one field
    /// still produce a coherent result.
    static func from(jsValue: JSValue, original: ScriptResponseContext) -> ScriptResponseContext {
        let nestedResponse = jsValue.objectForKeyedSubscript("response")
        let topLevelStatus = intValue(jsValue.objectForKeyedSubscript("statusCode"))
        let nestedStatus = intValue(nestedResponse?.objectForKeyedSubscript("statusCode"))
        let topLevelHeaders = stringDictionaryValue(jsValue.objectForKeyedSubscript("responseHeaders"))
        let nestedHeaders = stringDictionaryValue(nestedResponse?.objectForKeyedSubscript("headers"))
        let topLevelBody = stringValue(jsValue.objectForKeyedSubscript("body"))
        let nestedBody = stringValue(nestedResponse?.objectForKeyedSubscript("body"))
        let topLevelBodyIsBase64 = boolValue(jsValue.objectForKeyedSubscript("__bodyIsBase64"))
        let nestedBodyIsBase64 = boolValue(nestedResponse?.objectForKeyedSubscript("__bodyIsBase64"))

        // Single-arg `onResponse(ctx)` reads + mutates fields directly on the
        // top-level wrapper. Read each independently and fall back to original
        // when missing. Some newer scripts may also mutate a nested `response`
        // object, so we honor that as an additive fallback without letting an
        // untouched nested mirror override top-level legacy edits.
        let statusCode: Int = if let topLevelStatus,
                                 topLevelStatus != original.statusCode || nestedStatus == nil
        {
            topLevelStatus
        } else if let nestedStatus {
            nestedStatus
        } else {
            original.statusCode
        }

        let headers: [String: String] = if let topLevelHeaders,
                                           topLevelHeaders != original.responseHeaders || nestedHeaders == nil
        {
            topLevelHeaders
        } else if let nestedHeaders {
            nestedHeaders
        } else {
            original.responseHeaders
        }

        let body: String?
        let bodyIsUTF8: Bool
        if let topLevelBody,
           topLevelBody != original.body || nestedBody == nil
        {
            body = topLevelBody
            bodyIsUTF8 = !(topLevelBodyIsBase64 ?? !original.bodyIsUTF8)
        } else if let nestedBody {
            body = nestedBody
            bodyIsUTF8 = !(nestedBodyIsBase64 ?? !original.bodyIsUTF8)
        } else {
            body = original.body
            bodyIsUTF8 = original.bodyIsUTF8
        }

        return ScriptResponseContext(
            method: original.method,
            url: original.url,
            requestHeaders: original.requestHeaders,
            statusCode: statusCode,
            responseHeaders: headers,
            body: body,
            bodyIsUTF8: bodyIsUTF8
        )
    }

    func toJSValue(in context: JSContext) -> JSValue {
        let wrapper = JSValue(newObjectIn: context)

        // Single-arg `onResponse(ctx)` API: scripts read + mutate fields directly
        // on `ctx` (top-level). We deliberately do NOT shadow these in a nested
        // `response` object — that would let an unmutated nested copy silently
        // override a script's top-level mutation on apply-back.
        wrapper?.setObject(method, forKeyedSubscript: "method" as NSString)
        wrapper?.setObject(url, forKeyedSubscript: "url" as NSString)
        wrapper?.setObject(requestHeaders, forKeyedSubscript: "requestHeaders" as NSString)
        wrapper?.setObject(statusCode, forKeyedSubscript: "statusCode" as NSString)
        wrapper?.setObject(responseHeaders, forKeyedSubscript: "responseHeaders" as NSString)
        wrapper?.setObject(body as Any, forKeyedSubscript: "body" as NSString)
        if !bodyIsUTF8 {
            wrapper?.setObject(true, forKeyedSubscript: "__bodyIsBase64" as NSString)
        }

        let setHeaderFn: @convention(block) (String, String) -> Void = { name, value in
            let topHeaders = wrapper?.objectForKeyedSubscript("responseHeaders")
            topHeaders?.setObject(value, forKeyedSubscript: name as NSString)
        }
        let setBodyFn: @convention(block) (String) -> Void = { newBody in
            wrapper?.setObject(newBody, forKeyedSubscript: "body" as NSString)
        }
        let setStatusFn: @convention(block) (Int) -> Void = { newStatus in
            wrapper?.setObject(newStatus, forKeyedSubscript: "statusCode" as NSString)
        }

        wrapper?.setObject(setHeaderFn, forKeyedSubscript: "setHeader" as NSString)
        wrapper?.setObject(setBodyFn, forKeyedSubscript: "setBody" as NSString)
        wrapper?.setObject(setStatusFn, forKeyedSubscript: "setStatus" as NSString)

        return wrapper ?? JSValue(undefinedIn: context)
    }

    /// Apply the mutable fields of this context back onto the provided response.
    /// Preserves `statusMessage` and `contentType` from the original when the script did
    /// not supply them.
    func apply(to response: inout HTTPResponseData) {
        let newHeaders = responseHeaders.map { HTTPHeader(name: $0.key, value: $0.value) }
        let newBody: Data? = if let body {
            if bodyIsUTF8 {
                body.data(using: .utf8)
            } else {
                Data(base64Encoded: body)
            }
        } else {
            nil
        }
        let status = HTTPResponseStatusLookup.reasonPhrase(for: statusCode) ?? response.statusMessage
        response = HTTPResponseData(
            statusCode: statusCode,
            statusMessage: status,
            headers: newHeaders,
            body: newBody,
            bodyTruncated: response.bodyTruncated,
            contentType: ContentTypeDetector.detect(headers: newHeaders, body: newBody)
        )
    }

    // MARK: Private

    private static func intValue(_ value: JSValue?) -> Int? {
        guard let value, !value.isUndefined, !value.isNull, value.isNumber else {
            return nil
        }
        return Int(value.toInt32())
    }

    private static func stringDictionaryValue(_ value: JSValue?) -> [String: String]? {
        guard let value, !value.isUndefined, !value.isNull else {
            return nil
        }
        return value.toDictionary() as? [String: String]
    }

    private static func stringValue(_ value: JSValue?) -> String? {
        guard let value, !value.isUndefined, !value.isNull else {
            return nil
        }
        return value.toString()
    }

    private static func boolValue(_ value: JSValue?) -> Bool? {
        guard let value, !value.isUndefined, !value.isNull else {
            return nil
        }
        return value.toBool()
    }
}

// MARK: - HTTPResponseStatusLookup

/// Minimal mapping from status code to HTTP reason phrase, used when a script
/// changes only the status code and we need a sensible `statusMessage` to carry
/// through the transaction record.
enum HTTPResponseStatusLookup {
    static func reasonPhrase(for statusCode: Int) -> String? {
        switch statusCode {
        case 100: "Continue"
        case 101: "Switching Protocols"
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 304: "Not Modified"
        case 307: "Temporary Redirect"
        case 308: "Permanent Redirect"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 409: "Conflict"
        case 410: "Gone"
        case 418: "I'm a teapot"
        case 422: "Unprocessable Entity"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        default: nil
        }
    }
}
