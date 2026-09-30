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

    /// Shown as the plugin's status and last error in the scripting surfaces, so the
    /// templates are localized; the plugin ID and the script's own message stay verbatim.
    var errorDescription: String? {
        switch self {
        case let .pluginNotLoaded(id):
            String(localized: "Plugin not loaded: \(id)", bundle: RockxyLocalization.bundle)
        case let .scriptLoadFailed(reason):
            String(localized: "Script load failed: \(reason)", bundle: RockxyLocalization.bundle)
        case .executionTimeout:
            String(localized: "Plugin script execution timed out", bundle: RockxyLocalization.bundle)
        case let .jsException(message):
            String(localized: "JS exception: \(message)", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ScriptRuntime

actor ScriptRuntime {
    // MARK: Lifecycle

    init(
        defaults: UserDefaults = .standard,
        previewLedger: ScriptExecutionLedger? = nil,
        consoleSink: @escaping @Sendable (ScriptConsoleEvent) -> Void = { event in
            NotificationCenter.default.post(name: .scriptConsoleDidAppend, object: event)
        }
    ) {
        self.defaults = defaults
        self.previewLedger = previewLedger
        self.consoleSink = consoleSink
    }

    // MARK: Internal

    func loadPlugin(_ info: PluginInfo) throws {
        guard let scriptEntry = info.manifest.entryPoints["script"] else {
            throw ScriptRuntimeError.scriptLoadFailed(
                String(localized: "No script entry point defined", bundle: RockxyLocalization.bundle)
            )
        }

        let scriptURL = info.bundlePath.appendingPathComponent(scriptEntry)
        let source: String
        do {
            source = try String(contentsOf: scriptURL, encoding: .utf8)
        } catch {
            throw ScriptRuntimeError.scriptLoadFailed(
                String(
                    localized: "Cannot read \(scriptURL.path): \(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }

        let queue = DispatchQueue(
            label: RockxyIdentity.current.pluginRuntimePrefix(pluginID: info.id) + ".queue",
            qos: .userInitiated
        )
        guard let context = JSContext() else {
            throw ScriptRuntimeError.scriptLoadFailed(
                String(localized: "Failed to create JSContext", bundle: RockxyLocalization.bundle)
            )
        }

        let pluginID = info.id
        let exceptionLock = OSAllocatedUnfairLock<String?>(initialState: nil)
        context.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "Unknown JS error"
            exceptionLock.withLock { $0 = message }
            Self.logger.error("JS exception in plugin \(pluginID): \(message)")
        }

        let pluginLogger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "Plugin.\(info.id)")
        let consoleSink = consoleSink
        ScriptBridge.install(
            in: context,
            pluginID: info.id,
            logger: pluginLogger,
            defaults: defaults,
            consoleSink: consoleSink
        )

        // CommonJS compatibility: prime `module` and `exports` as globals BEFORE
        // evaluating user source so scripts that use `module.exports = { ... }`
        // pick them up. Evaluating the user source at the top level (not inside an
        // IIFE) preserves direct-global declarations like `function onRequest()`,
        // so both patterns continue to work.
        context.evaluateScript("var module = { exports: {} }; var exports = module.exports;")
        context.evaluateScript(source)
        if let message = Self.consumeException(from: context, lock: exceptionLock) {
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
        exceptionLocks[info.id] = exceptionLock
        onRequestHandlers[info.id] = onRequestFn
        onResponseHandlers[info.id] = onResponseFn
        flowStateStores[info.id] = ScriptFlowStateStore()
        onRequestArity[info.id] = ScriptMultiArgBridge.functionLength(onRequestFn) ?? 1
        onResponseArity[info.id] = ScriptMultiArgBridge.functionLength(onResponseFn) ?? 1
        Self.logger.info("Loaded script plugin: \(info.id)")
    }

    func unloadPlugin(id: String) {
        contexts.removeValue(forKey: id)
        queues.removeValue(forKey: id)
        exceptionLocks.removeValue(forKey: id)
        onRequestHandlers.removeValue(forKey: id)
        onResponseHandlers.removeValue(forKey: id)
        onRequestArity.removeValue(forKey: id)
        onResponseArity.removeValue(forKey: id)
        flowStateStores.removeValue(forKey: id)
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
        let exceptionLock = exceptionLocks[pluginID]
        guard let onRequest = onRequestHandlers[pluginID] else {
            return .forward(originalRequest)
        }

        let runAsMock = behavior.runAsMock
        let arity = onRequestArity[pluginID] ?? 1
        let flowStates = flowStateStores[pluginID]
        let previewLedger = previewLedger

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let workItem = DispatchWorkItem {
                Self.clearException(in: jsContext, lock: exceptionLock)
                // Arity dispatch: 1 => single-arg legacy `onRequest(ctx)`,
                // 3 => multi-arg `onRequest(context, url, request)`.
                let initialResult: JSValue?
                let multiArgs: (JSValue, JSValue, JSValue)?
                if arity >= 3,
                   let triplet = ScriptMultiArgBridge.buildRequestArgs(
                       in: jsContext,
                       request: originalRequest,
                       sharedState: flowStates?.beginFlow(originalRequest.flowID, in: jsContext),
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

                    if let message = Self.consumeException(from: jsContext, lock: exceptionLock) {
                        continuation
                            .resume(throwing: ScriptRuntimeError.jsException(message))
                        return
                    }

                    if let context = multiArgs?.0 {
                        previewLedger?.recordPreviews(
                            ScriptPreviewTab.read(from: context, panel: .request),
                            panel: .request,
                            flowID: originalRequest.flowID
                        )
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
        let exceptionLock = exceptionLocks[pluginID]
        guard let onResponse = onResponseHandlers[pluginID] else {
            return originalResponse
        }

        let arity = onResponseArity[pluginID] ?? 1
        let flowStates = flowStateStores[pluginID]
        let previewLedger = previewLedger

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let workItem = DispatchWorkItem {
                Self.clearException(in: jsContext, lock: exceptionLock)
                let initialResult: JSValue?
                let multiArgs: (JSValue, JSValue, JSValue, JSValue)?
                if arity >= 4,
                   let quad = ScriptMultiArgBridge.buildResponseArgs(
                       in: jsContext,
                       request: originalRequest,
                       response: originalResponse,
                       sharedState: flowStates?.endFlow(originalRequest.flowID, in: jsContext),
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

                    if let message = Self.consumeException(from: jsContext, lock: exceptionLock) {
                        continuation
                            .resume(throwing: ScriptRuntimeError.jsException(message))
                        return
                    }

                    if let multiArgs {
                        previewLedger?.recordPreviews(
                            ScriptPreviewTab.read(from: multiArgs.0, panel: .response),
                            panel: .response,
                            flowID: originalRequest.flowID
                        )
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
    private let previewLedger: ScriptExecutionLedger?
    private let consoleSink: @Sendable (ScriptConsoleEvent) -> Void
    private var contexts: [String: JSContext] = [:]
    private var queues: [String: DispatchQueue] = [:]
    private var exceptionLocks: [String: OSAllocatedUnfairLock<String?>] = [:]
    private var onRequestHandlers: [String: JSValue] = [:]
    private var onResponseHandlers: [String: JSValue] = [:]
    private var onRequestArity: [String: Int] = [:]
    private var onResponseArity: [String: Int] = [:]
    private var flowStateStores: [String: ScriptFlowStateStore] = [:]

    private static func clearException(in context: JSContext, lock: OSAllocatedUnfairLock<String?>?) {
        context.exception = nil
        lock?.withLock { $0 = nil }
    }

    private static func consumeException(from context: JSContext, lock: OSAllocatedUnfairLock<String?>?) -> String? {
        if let exception = context.exception {
            let message = exception.toString() ?? "Unknown"
            context.exception = nil
            lock?.withLock { $0 = nil }
            return message
        }
        return lock?.withLock { message in
            defer { message = nil }
            return message
        }
    }

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
