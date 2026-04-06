import Foundation
import JavaScriptCore
import os

// Implements script runtime behavior for the plugin and scripting subsystem.

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

        let queue = DispatchQueue(label: RockxyIdentity.current.pluginRuntimePrefix(pluginID: info.id) + ".queue", qos: .userInitiated)
        guard let context = JSContext() else {
            throw ScriptRuntimeError.scriptLoadFailed("Failed to create JSContext")
        }

        let pluginID = info.id
        context.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "Unknown JS error"
            Self.logger.error("JS exception in plugin \(pluginID): \(message)")
        }

        let pluginLogger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "Plugin.\(info.id)")
        ScriptBridge.install(in: context, pluginID: info.id, logger: pluginLogger)

        context.evaluateScript(source)
        if let exception = context.exception {
            let message = exception.toString() ?? "Unknown error"
            throw ScriptRuntimeError.jsException(message)
        }

        contexts[info.id] = context
        queues[info.id] = queue
        Self.logger.info("Loaded script plugin: \(info.id)")
    }

    func unloadPlugin(id: String) {
        contexts.removeValue(forKey: id)
        queues.removeValue(forKey: id)
        Self.logger.info("Unloaded script plugin: \(id)")
    }

    func callOnRequest(
        pluginID: String,
        context requestContext: ScriptRequestContext
    )
        async throws -> ScriptRequestContext
    {
        guard let jsContext = contexts[pluginID], let queue = queues[pluginID] else {
            throw ScriptRuntimeError.pluginNotLoaded(pluginID)
        }

        guard let onRequest = jsContext.objectForKeyedSubscript("onRequest"), !onRequest.isUndefined else {
            return requestContext
        }

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let workItem = DispatchWorkItem {
                let jsArg = requestContext.toJSValue(in: jsContext)
                let result = onRequest.call(withArguments: [jsArg])

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
                    continuation.resume(throwing: ScriptRuntimeError.jsException(exception.toString() ?? "Unknown"))
                    return
                }

                if let result, !result.isUndefined, !result.isNull {
                    let modified = ScriptRequestContext.from(jsValue: result, original: requestContext)
                    continuation.resume(returning: modified)
                } else {
                    continuation.resume(returning: requestContext)
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

    func callOnResponse(pluginID: String, context responseContext: ScriptResponseContext) async throws {
        guard let jsContext = contexts[pluginID], let queue = queues[pluginID] else {
            throw ScriptRuntimeError.pluginNotLoaded(pluginID)
        }

        guard let onResponse = jsContext.objectForKeyedSubscript("onResponse"), !onResponse.isUndefined else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let workItem = DispatchWorkItem {
                let jsArg = responseContext.toJSValue(in: jsContext)
                onResponse.call(withArguments: [jsArg])

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
                    continuation.resume(throwing: ScriptRuntimeError.jsException(exception.toString() ?? "Unknown"))
                    return
                }

                continuation.resume()
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

    func hasPlugin(id: String) -> Bool {
        contexts[id] != nil
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptRuntime")
    private static let timeout: TimeInterval = 5

    private var contexts: [String: JSContext] = [:]
    private var queues: [String: DispatchQueue] = [:]
}
