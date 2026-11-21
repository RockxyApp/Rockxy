import Foundation
import JavaScriptCore
import os

// MARK: - ScriptSourceValidationResult

enum ScriptSourceValidationResult: Equatable {
    case valid
    case invalid(String)
}

// MARK: - ScriptSourceValidator

enum ScriptSourceValidator {
    // MARK: Internal

    /// How long a script gets to finish validating before the editor gives up on it.
    static let timeout: TimeInterval = 5

    /// Validate a script's source without ever blocking the caller.
    ///
    /// Evaluating untrusted JavaScript can run forever — `while (true) {}` is a one-line
    /// script — and JavaScriptCore offers no public way to interrupt a running
    /// evaluation, so the work goes to a dedicated thread that is simply abandoned if it
    /// overruns. A single leaked thread is a far better outcome than what this used to
    /// do: evaluate synchronously on the main actor and hang the whole app until Force
    /// Quit. The abandoned thread only ever writes into a resume-once guard nothing
    /// reads afterwards, so it cannot corrupt the result reported here.
    static func validate(
        source: String,
        runOnRequest: Bool,
        runOnResponse: Bool,
        runAsMock: Bool
    )
        async -> ScriptSourceValidationResult
    {
        if !runOnRequest, !runOnResponse {
            return .invalid("Enable Request or Response before validating.")
        }
        if runAsMock, !runOnRequest {
            return .invalid("Mock API scripts must run on Request.")
        }

        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let claim: @Sendable (ScriptSourceValidationResult) -> Void = { result in
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    if alreadyResumed {
                        return false
                    }
                    alreadyResumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: result)
                }
            }

            let thread = Thread {
                claim(evaluate(source: source, runOnRequest: runOnRequest, runOnResponse: runOnResponse))
            }
            thread.name = "\(RockxyIdentity.current.logSubsystem).script-validation"
            thread.start()

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                claim(
                    .invalid("Validation did not finish within \(Int(timeout)) seconds. The script may not terminate.")
                )
            }
        }
    }

    // MARK: Private

    /// Runs entirely on the caller's thread, which is the throwaway thread above, so the
    /// `JSContext` it creates never crosses a thread boundary.
    private static func evaluate(
        source: String,
        runOnRequest: Bool,
        runOnResponse: Bool
    )
        -> ScriptSourceValidationResult
    {
        guard let context = JSContext() else {
            return .invalid("Failed to create JavaScript context.")
        }

        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString() ?? "Unknown JavaScript error"
        }

        // Validation storage never touches disk: a named suite leaves a plist behind even
        // after `removePersistentDomain`, and falling back to `.standard` would let an
        // untrusted script write into the user's real defaults domain.
        let defaults = ScriptValidationDefaults()

        let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptValidation")
        ScriptBridge.install(in: context, pluginID: "validation", logger: logger, defaults: defaults)

        context.evaluateScript("var module = { exports: {} }; var exports = module.exports;")
        context.evaluateScript(source)

        if let exceptionMessage {
            return .invalid(exceptionMessage)
        }
        if let exception = context.exception {
            let message = exception.toString() ?? "Unknown JavaScript error"
            context.exception = nil
            return .invalid(message)
        }

        if runOnRequest, !hasHook(named: "onRequest", in: context) {
            return .invalid("Request is enabled, but onRequest is missing.")
        }
        if runOnResponse, !hasHook(named: "onResponse", in: context) {
            return .invalid("Response is enabled, but onResponse is missing.")
        }

        return .valid
    }

    private static func hasHook(named name: String, in context: JSContext) -> Bool {
        let moduleObj = context.objectForKeyedSubscript("module")
        let moduleExports = moduleObj?.objectForKeyedSubscript("exports")
        if let exports = moduleExports,
           !exports.isUndefined,
           !exports.isNull,
           let fn = exports.objectForKeyedSubscript(name),
           !fn.isUndefined,
           fn.isObject
        {
            return true
        }
        if let global = context.objectForKeyedSubscript(name),
           !global.isUndefined,
           global.isObject
        {
            return true
        }
        return false
    }
}

// MARK: - ScriptValidationDefaults

/// A `UserDefaults` whose storage is a private in-memory dictionary.
///
/// `ScriptBridge` only reads, writes, and removes keys through `object(forKey:)`,
/// `set(_:forKey:)`, and `removeObject(forKey:)`; all three are overridden, so nothing a
/// validated script does reaches `cfprefsd`, creates a preference file, or lands in the
/// real app domain. The inherited `init()` is used as-is -- the SDK documents it as
/// equivalent to `initWithSuiteName:nil`, and it is non-failable, so there is no degraded
/// path to guard. No inherited accessor that would write to the real domain is reachable
/// from the bridge.
final class ScriptValidationDefaults: UserDefaults {
    // MARK: Internal

    var storedKeys: [String] {
        lock.withLock { values.keys.sorted() }
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }

    // MARK: Private

    private let lock = OSAllocatedUnfairLock()
    private var values: [String: Any] = [:]
}
