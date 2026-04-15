import Foundation
import JavaScriptCore
import os

// Implements script runtime behavior for the plugin and scripting subsystem.
//
// This milestone preserves the single-argument public JS API: scripts define
// `onRequest(ctx)` and/or `onResponse(ctx)` plus use the `$rockxy` bridge.
// CommonJS `module.exports = { onRequest, onResponse }` is supported in addition
// to direct globals — the runtime extracts whichever it finds.
//
// The runtime now returns structured outcomes for request-side calls so the
// pipeline can branch on block / mock / forward without a second hop, and
// response-side calls return the mutated context so changes to status/headers/
// body actually reach the client and the persisted transaction.

// MARK: - ScriptRuntimeError

enum ScriptRuntimeError: Error, LocalizedError {
    case pluginNotLoaded(String)
    case scriptLoadFailed(String)
    case executionTimeout
    case jsException(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .pluginNotLoaded(id): "Plugin not loaded: \(id)"
        case let .scriptLoadFailed(reason): "Script load failed: \(reason)"
        case .executionTimeout: "Plugin script execution timed out"
        case let .jsException(message): "JS exception: \(message)"
        }
    }
}

// MARK: - ScriptRuntime

actor ScriptRuntime {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Internal

    func loadPlugin(_ info: PluginInfo) throws {
        guard let scriptEntry = info.manifest.entryPoints["script"] else {
            throw ScriptRuntimeError.scriptLoadFailed("No script entry point defined")
        }

        let scriptURL = info.bundlePath.appendingPathComponent(scriptEntry)
        let source: String
        do {
            source = try String(contentsOf: scriptURL, encoding: .utf8)
        } catch {
            throw ScriptRuntimeError.scriptLoadFailed("Cannot read \(scriptURL.path): \(error.localizedDescription)")
        }

        let queue = DispatchQueue(
            label: RockxyIdentity.current.pluginRuntimePrefix(pluginID: info.id) + ".queue",
            qos: .userInitiated
        )
        guard let context = JSContext() else {
            throw ScriptRuntimeError.scriptLoadFailed("Failed to create JSContext")
        }

        let pluginID = info.id
        context.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "Unknown JS error"
            Self.logger.error("JS exception in plugin \(pluginID): \(message)")
        }

        let pluginLogger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "Plugin.\(info.id)")
        ScriptBridge.install(in: context, pluginID: info.id, logger: pluginLogger, defaults: defaults)

        // CommonJS compatibility: prime `module` and `exports` as globals BEFORE
        // evaluating user source so scripts that use `module.exports = { ... }`
        // pick them up. Evaluating the user source at the top level (not inside an
        // IIFE) preserves direct-global declarations like `function onRequest()`,
        // so both patterns continue to work.
        context.evaluateScript("var module = { exports: {} }; var exports = module.exports;")
        context.evaluateScript(source)
        if let exception = context.exception {
            let message = exception.toString() ?? "Unknown error"
            context.exception = nil
            throw ScriptRuntimeError.jsException(message)
        }

        let moduleObj = context.objectForKeyedSubscript("module")
        let moduleExports = moduleObj?.objectForKeyedSubscript("exports")

        let onRequestFn: JSValue? = {
            if let exports = moduleExports, !exports.isUndefined, !exports.isNull,
               let fn = exports.objectForKeyedSubscript("onRequest"),
               !fn.isUndefined, fn.isObject
            {
                return fn
            }
            if let global = context.objectForKeyedSubscript("onRequest"),
               !global.isUndefined, global.isObject
            {
                return global
            }
            return nil
        }()

        let onResponseFn: JSValue? = {
            if let exports = moduleExports, !exports.isUndefined, !exports.isNull,
               let fn = exports.objectForKeyedSubscript("onResponse"),
               !fn.isUndefined, fn.isObject
            {
                return fn
            }
            if let global = context.objectForKeyedSubscript("onResponse"),
               !global.isUndefined, global.isObject
            {
                return global
            }
            return nil
        }()

        contexts[info.id] = context
        queues[info.id] = queue
        onRequestHandlers[info.id] = onRequestFn
        onResponseHandlers[info.id] = onResponseFn
        onRequestArity[info.id] = ScriptMultiArgBridge.functionLength(onRequestFn) ?? 1
        onResponseArity[info.id] = ScriptMultiArgBridge.functionLength(onResponseFn) ?? 1
        Self.logger.info("Loaded script plugin: \(info.id)")
    }

    func unloadPlugin(id: String) {
        contexts.removeValue(forKey: id)
        queues.removeValue(forKey: id)
        onRequestHandlers.removeValue(forKey: id)
        onResponseHandlers.removeValue(forKey: id)
        onRequestArity.removeValue(forKey: id)
        onResponseArity.removeValue(forKey: id)
        Self.logger.info("Unloaded script plugin: \(id)")
    }

    func hasPlugin(id: String) -> Bool {
        contexts[id] != nil
    }

    // MARK: - Request hook

    /// Invoke the plugin's `onRequest(ctx)`. The outcome is interpreted based on
    /// the plugin's `scriptBehavior.runAsMock` flag:
    ///
    /// - `runAsMock == false` (default): a `null` return blocks the request locally
    ///   with an HTTP 403; any non-null return is treated as the mutated request.
    /// - `runAsMock == true`: the plugin must return a response-shape object
    ///   (`{ statusCode, headers?, body? }`). A valid shape becomes `.mock`; an
    ///   invalid shape becomes `.mockFailure` — the pipeline never goes upstream.
    func callOnRequest(
        pluginID: String,
        context requestContext: ScriptRequestContext,
        behavior: ScriptBehavior,
        originalRequest: HTTPRequestData
    )
        async throws -> RequestHookOutcome
    {
        guard let jsContext = contexts[pluginID], let queue = queues[pluginID] else {
            throw ScriptRuntimeError.pluginNotLoaded(pluginID)
        }
        guard let onRequest = onRequestHandlers[pluginID] else {
            return .forward(originalRequest)
        }

        let runAsMock = behavior.runAsMock
        let arity = onRequestArity[pluginID] ?? 1

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let workItem = DispatchWorkItem {
                // Arity dispatch: 1 => single-arg legacy `onRequest(ctx)`,
                // 3 => multi-arg `onRequest(context, url, request)`.
                let initialResult: JSValue?
                let multiArgs: (JSValue, JSValue, JSValue)?
                if arity >= 3,
                   let triplet = ScriptMultiArgBridge.buildRequestArgs(
                       in: jsContext,
                       request: originalRequest,
                       sharedState: nil,
                       env: nil,
                       configs: nil
                   )
                {
                    multiArgs = (triplet.context, triplet.url, triplet.request)
                    initialResult = onRequest.call(withArguments: [triplet.context, triplet.url, triplet.request])
                } else {
                    multiArgs = nil
                    let jsArg = requestContext.toJSValue(in: jsContext)
                    initialResult = onRequest.call(withArguments: [jsArg])
                }

                // `interpret` is the single point that decides .forward / .block / .mock
                // from a (possibly Promise-resolved) JS value. It guards against
                // double-resume via `resumed`.
                let interpret: (JSValue?) -> Void = { value in
                    let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                        if alreadyResumed {
                            return false
                        }
                        alreadyResumed = true
                        return true
                    }
                    guard shouldResume else {
                        return
                    }

                    if let exception = jsContext.exception {
                        jsContext.exception = nil
                        continuation
                            .resume(throwing: ScriptRuntimeError.jsException(exception.toString() ?? "Unknown"))
                        return
                    }

                    if runAsMock {
                        guard let value, !value.isUndefined else {
                            continuation.resume(returning: .mockFailure(reason: "mock script returned undefined"))
                            return
                        }
                        if value.isNull {
                            continuation.resume(returning: .mockFailure(reason: "mock script returned null"))
                            return
                        }
                        if let mock = Self.makeMockResponse(from: value, originalRequest: originalRequest) {
                            continuation.resume(returning: .mock(mock))
                        } else {
                            continuation
                                .resume(returning: .mockFailure(reason: "mock script returned invalid response shape"))
                        }
                        return
                    }

                    if let value, value.isNull {
                        continuation.resume(returning: .blockLocally(reason: "script returned null"))
                        return
                    }
                    if let multiArgs {
                        let modified = ScriptMultiArgBridge.readRequestMutations(
                            original: originalRequest,
                            requestArg: multiArgs.2,
                            returnedValue: value,
                            pluginID: pluginID
                        )
                        continuation.resume(returning: .forward(modified))
                        return
                    }
                    if let value, !value.isUndefined {
                        let modifiedContext = ScriptRequestContext.from(jsValue: value, original: requestContext)
                        var modifiedRequest = originalRequest
                        modifiedContext.apply(to: &modifiedRequest, pluginID: pluginID)
                        continuation.resume(returning: .forward(modifiedRequest))
                    } else {
                        continuation.resume(returning: .forward(originalRequest))
                    }
                }

                // If the function returned a Promise (async function), drive it to
                // resolution before interpreting. Otherwise interpret synchronously.
                let isPromise = ScriptMultiArgBridge.awaitPromise(
                    initialResult,
                    in: jsContext,
                    onResolve: { resolved in
                        queue.async { interpret(resolved) }
                    },
                    onReject: { errMsg in
                        let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                            if alreadyResumed {
                                return false
                            }
                            alreadyResumed = true
                            return true
                        }
                        guard shouldResume else {
                            return
                        }
                        continuation.resume(throwing: ScriptRuntimeError.jsException(errMsg))
                    }
                )
                if !isPromise {
                    interpret(initialResult)
                }
            }

            queue.async(execute: workItem)

            queue.asyncAfter(deadline: .now() + Self.timeout) {
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    if alreadyResumed {
                        return false
                    }
                    alreadyResumed = true
                    return true
                }
                guard shouldResume else {
                    return
                }
                workItem.cancel()
                continuation.resume(throwing: ScriptRuntimeError.executionTimeout)
            }
        }
    }

    // MARK: - Response hook

    /// Invoke `onResponse(ctx)`. If the plugin mutates status/headers/body, the
    /// mutated response is returned. If the plugin has no `onResponse` function or
    /// returns undefined, the original response is returned unchanged.
    func callOnResponse(
        pluginID: String,
        context responseContext: ScriptResponseContext,
        originalRequest: HTTPRequestData,
        originalResponse: HTTPResponseData
    )
        async throws -> HTTPResponseData
    {
        guard let jsContext = contexts[pluginID], let queue = queues[pluginID] else {
            throw ScriptRuntimeError.pluginNotLoaded(pluginID)
        }
        guard let onResponse = onResponseHandlers[pluginID] else {
            return originalResponse
        }

        let arity = onResponseArity[pluginID] ?? 1

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let workItem = DispatchWorkItem {
                let initialResult: JSValue?
                let multiArgs: (JSValue, JSValue, JSValue, JSValue)?
                if arity >= 4,
                   let quad = ScriptMultiArgBridge.buildResponseArgs(
                       in: jsContext,
                       request: originalRequest,
                       response: originalResponse,
                       sharedState: nil,
                       env: nil,
                       configs: nil
                   )
                {
                    multiArgs = (quad.context, quad.url, quad.request, quad.response)
                    initialResult = onResponse
                        .call(withArguments: [quad.context, quad.url, quad.request, quad.response])
                } else {
                    multiArgs = nil
                    let jsArg = responseContext.toJSValue(in: jsContext)
                    initialResult = onResponse.call(withArguments: [jsArg])
                }

                let interpret: (JSValue?) -> Void = { value in
                    let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                        if alreadyResumed {
                            return false
                        }
                        alreadyResumed = true
                        return true
                    }
                    guard shouldResume else {
                        return
                    }

                    if let exception = jsContext.exception {
                        jsContext.exception = nil
                        continuation
                            .resume(throwing: ScriptRuntimeError.jsException(exception.toString() ?? "Unknown"))
                        return
                    }

                    if let multiArgs {
                        let mutated = ScriptMultiArgBridge.readResponseMutations(
                            original: originalResponse,
                            responseArg: multiArgs.3,
                            returnedValue: value,
                            pluginID: pluginID
                        )
                        continuation.resume(returning: mutated)
                        return
                    }

                    let resolved: ScriptResponseContext = if let value, !value.isUndefined, !value.isNull {
                        ScriptResponseContext.from(jsValue: value, original: responseContext)
                    } else {
                        responseContext
                    }
                    var mutated = originalResponse
                    resolved.apply(to: &mutated)
                    continuation.resume(returning: mutated)
                }

                let isPromise = ScriptMultiArgBridge.awaitPromise(
                    initialResult,
                    in: jsContext,
                    onResolve: { resolved in
                        queue.async { interpret(resolved) }
                    },
                    onReject: { errMsg in
                        let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                            if alreadyResumed {
                                return false
                            }
                            alreadyResumed = true
                            return true
                        }
                        guard shouldResume else {
                            return
                        }
                        continuation.resume(throwing: ScriptRuntimeError.jsException(errMsg))
                    }
                )
                if !isPromise {
                    interpret(initialResult)
                }
            }

            queue.async(execute: workItem)

            queue.asyncAfter(deadline: .now() + Self.timeout) {
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    if alreadyResumed {
                        return false
                    }
                    alreadyResumed = true
                    return true
                }
                guard shouldResume else {
                    return
                }
                workItem.cancel()
                continuation.resume(throwing: ScriptRuntimeError.executionTimeout)
            }
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptRuntime")
    private static let timeout: TimeInterval = 5

    private let defaults: UserDefaults
    private var contexts: [String: JSContext] = [:]
    private var queues: [String: DispatchQueue] = [:]
    private var onRequestHandlers: [String: JSValue] = [:]
    private var onResponseHandlers: [String: JSValue] = [:]
    private var onRequestArity: [String: Int] = [:]
    private var onResponseArity: [String: Int] = [:]

    // MARK: - Mock response parsing

    nonisolated private static func makeMockResponse(
        from value: JSValue,
        originalRequest: HTTPRequestData
    )
        -> HTTPResponseData?
    {
        let statusVal = value.objectForKeyedSubscript("statusCode")
        guard let statusVal, !statusVal.isUndefined, statusVal.isNumber else {
            return nil
        }
        let status = Int(statusVal.toInt32())
        guard (100 ... 599).contains(status) else {
            return nil
        }

        var headerPairs: [HTTPHeader] = []
        if let headersObj = value.objectForKeyedSubscript("headers"), !headersObj.isUndefined, !headersObj.isNull {
            if let dict = headersObj.toDictionary() as? [String: String] {
                for (name, value) in dict {
                    headerPairs.append(HTTPHeader(name: name, value: value))
                }
            }
        }

        var bodyData: Data?
        if let bodyVal = value.objectForKeyedSubscript("body"), !bodyVal.isUndefined, !bodyVal.isNull {
            if bodyVal.isString, let bodyString = bodyVal.toString() {
                bodyData = bodyString.data(using: .utf8)
            } else if bodyVal.isObject,
                      let dict = bodyVal.toDictionary(),
                      let json = try? JSONSerialization.data(withJSONObject: dict, options: [])
            {
                bodyData = json
            }
        }

        if let bodyData, bodyData.count > ProxyLimits.maxResponseBodySize {
            return nil
        }

        let reason = HTTPResponseStatusLookup.reasonPhrase(for: status) ?? ""
        return HTTPResponseData(
            statusCode: status,
            statusMessage: reason,
            headers: headerPairs,
            body: bodyData,
            bodyTruncated: false,
            contentType: ContentTypeDetector.detect(headers: headerPairs, body: bodyData)
        )
    }
}
