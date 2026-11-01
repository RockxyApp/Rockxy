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
    /// The plugin's script did not terminate, so its serial queue can never run
    /// anything again and the runtime stopped handing it out.
    case runawayScript(String)
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
        case let .runawayScript(id):
            String(
                localized: "Plugin script did not terminate and was disabled: \(id)",
                bundle: RockxyLocalization.bundle
            )
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

    func loadPlugin(_ info: PluginInfo) async throws {
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

        // Evaluating the source runs the script's TOP-LEVEL code, which can fail to
        // terminate exactly as a hook can, and `evaluateScript` is synchronous with no
        // public way to interrupt a running evaluation. Run on this actor it would hold
        // the actor's executor forever: every later call for every OTHER plugin, and the
        // unload that would retire this one, would never run again, and a saved runaway
        // script would hang the runtime on every launch because startup reconciliation
        // loads enabled plugins one after another. So it runs on the plugin's own queue
        // behind the same watchdog the hooks use, and a load that does not finish
        // abandons that queue and context instead of registering them.
        let products = try await evaluateSource(
            source,
            in: context,
            on: queue,
            pluginID: pluginID,
            lock: exceptionLock
        )
        let onRequestFn = products.onRequest
        let onResponseFn = products.onResponse

        contexts[info.id] = context
        queues[info.id] = queue
        exceptionLocks[info.id] = exceptionLock
        onRequestHandlers[info.id] = onRequestFn
        onResponseHandlers[info.id] = onResponseFn
        flowStateStores[info.id] = ScriptFlowStateStore()
        onRequestArity[info.id] = ScriptMultiArgBridge.functionLength(onRequestFn) ?? 1
        onResponseArity[info.id] = ScriptMultiArgBridge.functionLength(onResponseFn) ?? 1
        lastLoadGeneration += 1
        loadGenerations[info.id] = lastLoadGeneration
        Self.logger.info("Loaded script plugin: \(info.id)")
    }

    func unloadPlugin(id: String) {
        // Must clear, or reloading a corrected script would stay permanently retired.
        wedgedPlugins.remove(id)
        loadGenerations.removeValue(forKey: id)
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
        if wedgedPlugins.contains(pluginID) {
            throw ScriptRuntimeError.runawayScript(pluginID)
        }
        guard let jsContext = contexts[pluginID], let queue = queues[pluginID] else {
            throw ScriptRuntimeError.pluginNotLoaded(pluginID)
        }
        let exceptionLock = exceptionLocks[pluginID]
        guard let onRequest = onRequestHandlers[pluginID] else {
            return .forward(originalRequest)
        }

        let runAsMock = behavior.runAsMock
        let loadGeneration = loadGenerations[pluginID] ?? 0
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

            // The watchdog must not share the plugin's serial queue: a serial queue runs
            // one block at a time, so while a runaway script holds it the watchdog could
            // never be dequeued and the timeout below never fired at all.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.timeout) {
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
                // `cancel()` is a documented no-op for work already executing, so the
                // script keeps spinning and this plugin's queue stays occupied. Retire
                // the plugin so later requests fail immediately instead of each paying
                // the full timeout behind a loop that will never end.
                workItem.cancel()
                // Retire the plugin BEFORE telling the caller, so by the time anyone sees
                // this failure the next request already fails fast instead of racing the
                // bookkeeping and queueing behind the loop for another full timeout. The
                // hop is safe: the runaway holds the plugin's dispatch queue, not this
                // actor, so the actor is free to run this.
                Task {
                    await self.markPluginWedged(pluginID, generation: loadGeneration)
                    continuation.resume(throwing: ScriptRuntimeError.executionTimeout)
                }
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
        if wedgedPlugins.contains(pluginID) {
            throw ScriptRuntimeError.runawayScript(pluginID)
        }
        guard let jsContext = contexts[pluginID], let queue = queues[pluginID] else {
            throw ScriptRuntimeError.pluginNotLoaded(pluginID)
        }
        let exceptionLock = exceptionLocks[pluginID]
        guard let onResponse = onResponseHandlers[pluginID] else {
            return originalResponse
        }

        let loadGeneration = loadGenerations[pluginID] ?? 0
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

            // The watchdog must not share the plugin's serial queue: a serial queue runs
            // one block at a time, so while a runaway script holds it the watchdog could
            // never be dequeued and the timeout below never fired at all.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.timeout) {
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
                // `cancel()` is a documented no-op for work already executing, so the
                // script keeps spinning and this plugin's queue stays occupied. Retire
                // the plugin so later requests fail immediately instead of each paying
                // the full timeout behind a loop that will never end.
                workItem.cancel()
                // Retire the plugin BEFORE telling the caller, so by the time anyone sees
                // this failure the next request already fails fast instead of racing the
                // bookkeeping and queueing behind the loop for another full timeout. The
                // hop is safe: the runaway holds the plugin's dispatch queue, not this
                // actor, so the actor is free to run this.
                Task {
                    await self.markPluginWedged(pluginID, generation: loadGeneration)
                    continuation.resume(throwing: ScriptRuntimeError.executionTimeout)
                }
            }
        }
    }

    // MARK: Private

    /// Carries a load's extracted hook functions from the plugin's own queue back to
    /// the actor. `JSValue` is not `Sendable`; the hand-off is safe because the queue
    /// finishes writing before the continuation resumes, and nothing else holds the box.
    private final class ScriptLoadProducts: @unchecked Sendable {
        var onRequest: JSValue?
        var onResponse: JSValue?
    }

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptRuntime")
    private static let timeout: TimeInterval = 5

    private let defaults: UserDefaults
    private let previewLedger: ScriptExecutionLedger?
    private let consoleSink: @Sendable (ScriptConsoleEvent) -> Void
    private var contexts: [String: JSContext] = [:]
    /// Plugins whose serial queue is occupied forever by a script that did not
    /// terminate. Their queue and `JSContext` are abandoned rather than reused: a
    /// later call enqueued behind an infinite loop would wait the whole timeout and
    /// then fail anyway, so failing it at once is both faster and more truthful.
    private var wedgedPlugins: Set<String> = []
    /// Which load a plugin's current context came from. A runaway script is detected
    /// up to `timeout` seconds late, by which time the user may have fixed and
    /// reloaded it, so the watchdog must prove it is retiring the load it timed out
    /// on and not a healthy replacement.
    private var loadGenerations: [String: Int] = [:]
    private var lastLoadGeneration = 0
    private var queues: [String: DispatchQueue] = [:]
    private var exceptionLocks: [String: OSAllocatedUnfairLock<String?>] = [:]
    private var onRequestHandlers: [String: JSValue] = [:]
    private var onResponseHandlers: [String: JSValue] = [:]
    private var onRequestArity: [String: Int] = [:]
    private var onResponseArity: [String: Int] = [:]
    private var flowStateStores: [String: ScriptFlowStateStore] = [:]

    /// Picks a hook out of `module.exports` first, then the globals, which is the order
    /// the two supported authoring styles need.
    private static func hookFunction(
        named name: String,
        in context: JSContext,
        exports: JSValue?
    )
        -> JSValue?
    {
        if let exports, !exports.isUndefined, !exports.isNull,
           let fn = exports.objectForKeyedSubscript(name),
           !fn.isUndefined, fn.isObject
        {
            return fn
        }
        if let global = context.objectForKeyedSubscript(name),
           !global.isUndefined, global.isObject
        {
            return global
        }
        return nil
    }

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

    /// Evaluates a plugin's own source on its serial queue and extracts its hooks,
    /// failing with `runawayScript` if the top-level code does not finish within
    /// `timeout`. On that path the queue and context are left behind unregistered: the
    /// evaluation still holds the queue and JavaScriptCore cannot interrupt it, so the
    /// only safe thing is never to hand either out again.
    private func evaluateSource(
        _ source: String,
        in context: JSContext,
        on queue: DispatchQueue,
        pluginID: String,
        lock: OSAllocatedUnfairLock<String?>
    )
        async throws -> ScriptLoadProducts
    {
        let products = ScriptLoadProducts()
        let resumed = OSAllocatedUnfairLock<Bool>(initialState: false)
        func claimResume() -> Bool {
            resumed.withLock { alreadyResumed -> Bool in
                if alreadyResumed {
                    return false
                }
                alreadyResumed = true
                return true
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let workItem = DispatchWorkItem {
                // CommonJS compatibility: prime `module` and `exports` as globals BEFORE
                // evaluating user source so scripts that use `module.exports = { ... }`
                // pick them up. Evaluating the user source at the top level (not inside an
                // IIFE) preserves direct-global declarations like `function onRequest()`,
                // so both patterns continue to work.
                context.evaluateScript("var module = { exports: {} }; var exports = module.exports;")
                context.evaluateScript(source)
                let failure = Self.consumeException(from: context, lock: lock)
                if failure == nil {
                    let moduleExports = context.objectForKeyedSubscript("module")?
                        .objectForKeyedSubscript("exports")
                    products.onRequest = Self.hookFunction(
                        named: "onRequest", in: context, exports: moduleExports
                    )
                    products.onResponse = Self.hookFunction(
                        named: "onResponse", in: context, exports: moduleExports
                    )
                }
                guard claimResume() else {
                    return
                }
                if let failure {
                    continuation.resume(throwing: ScriptRuntimeError.jsException(failure))
                } else {
                    continuation.resume(returning: products)
                }
            }

            queue.async(execute: workItem)

            // The watchdog must not share the plugin's serial queue: a serial queue runs
            // one block at a time, so while a runaway evaluation holds it the watchdog
            // could never be dequeued and the timeout would never fire at all.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.timeout) {
                guard claimResume() else {
                    return
                }
                // `cancel()` is a documented no-op for work already executing, so the
                // evaluation keeps spinning on its own queue. Nothing is registered for
                // this plugin, so later calls fail fast with `pluginNotLoaded` rather
                // than queueing behind a loop that will never end.
                workItem.cancel()
                Self.logger.error(
                    "Script plugin source did not finish evaluating: \(pluginID, privacy: .public)"
                )
                continuation.resume(throwing: ScriptRuntimeError.runawayScript(pluginID))
            }
        }
    }

    /// Retires a plugin whose script never returned. Drops exactly what
    /// `unloadPlugin(id:)` drops, because the queue and context are unusable: the
    /// runaway script still holds the queue and no public JavaScriptCore API can
    /// interrupt a running evaluation. The abandoned thread keeps the queue object
    /// alive through its own retain; the point is only that nothing is handed it again.
    private func markPluginWedged(_ id: String, generation: Int) {
        // A reload during the timeout window replaces the context, and retiring that
        // fresh load would disable a plugin the user has just fixed.
        guard loadGenerations[id] == generation else {
            return
        }
        wedgedPlugins.insert(id)
        loadGenerations.removeValue(forKey: id)
        contexts.removeValue(forKey: id)
        queues.removeValue(forKey: id)
        exceptionLocks.removeValue(forKey: id)
        onRequestHandlers.removeValue(forKey: id)
        onResponseHandlers.removeValue(forKey: id)
        onRequestArity.removeValue(forKey: id)
        onResponseArity.removeValue(forKey: id)
        flowStateStores.removeValue(forKey: id)
        Self.logger.error("Retired script plugin whose script did not terminate: \(id, privacy: .public)")
    }
}
