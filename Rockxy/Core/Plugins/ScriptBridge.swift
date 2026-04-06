import CryptoKit
import Foundation
import JavaScriptCore
import os

// Implements script bridge behavior for the plugin and scripting subsystem.

// MARK: - ScriptBridge

enum ScriptBridge {
    // MARK: Internal

    static func install(in context: JSContext, pluginID: String, logger: Logger) {
        let rockxy = JSValue(newObjectIn: context)

        installLogging(on: rockxy, context: context, logger: logger)
        installCrypto(on: rockxy, context: context)
        installEncoding(on: rockxy, context: context)
        installStorage(on: rockxy, context: context, pluginID: pluginID)
        installEnv(on: rockxy, context: context, pluginID: pluginID)

        context.setObject(rockxy, forKeyedSubscript: "$rockxy" as NSString)

        let consoleObj = JSValue(newObjectIn: context)
        let logFn: @convention(block) (String) -> Void = { msg in
            logger.info("[\(pluginID)] \(msg)")
        }
        consoleObj?.setObject(logFn, forKeyedSubscript: "log" as NSString)
        context.setObject(consoleObj, forKeyedSubscript: "console" as NSString)
    }

    // MARK: Private

    private static let bridgeLogger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ScriptBridge")

    private static func installLogging(on rockxy: JSValue?, context: JSContext, logger: Logger) {
        let log = JSValue(newObjectIn: context)

        let infoFn: @convention(block) (String) -> Void = { msg in logger.info("\(msg)") }
        let warnFn: @convention(block) (String) -> Void = { msg in logger.warning("\(msg)") }
        let errorFn: @convention(block) (String) -> Void = { msg in logger.error("\(msg)") }
        let debugFn: @convention(block) (String) -> Void = { msg in logger.debug("\(msg)") }

        log?.setObject(infoFn, forKeyedSubscript: "info" as NSString)
        log?.setObject(warnFn, forKeyedSubscript: "warn" as NSString)
        log?.setObject(errorFn, forKeyedSubscript: "error" as NSString)
        log?.setObject(debugFn, forKeyedSubscript: "debug" as NSString)

        rockxy?.setObject(log, forKeyedSubscript: "log" as NSString)
    }

    private static func installCrypto(on rockxy: JSValue?, context: JSContext) {
        let crypto = JSValue(newObjectIn: context)

        let sha256Fn: @convention(block) (String) -> String = { input in
            let digest = SHA256.hash(data: Data(input.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        let md5Fn: @convention(block) (String) -> String = { input in
            let digest = Insecure.MD5.hash(data: Data(input.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        crypto?.setObject(sha256Fn, forKeyedSubscript: "sha256" as NSString)
        crypto?.setObject(md5Fn, forKeyedSubscript: "md5" as NSString)

        rockxy?.setObject(crypto, forKeyedSubscript: "crypto" as NSString)
    }

    private static func installEncoding(on rockxy: JSValue?, context: JSContext) {
        let encoding = JSValue(newObjectIn: context)

        let base64EncodeFn: @convention(block) (String) -> String = { input in
            Data(input.utf8).base64EncodedString()
        }
        let base64DecodeFn: @convention(block) (String) -> String = { input in
            guard let data = Data(base64Encoded: input),
                  let decoded = String(data: data, encoding: .utf8) else
            {
                return ""
            }
            return decoded
        }
        let urlEncodeFn: @convention(block) (String) -> String = { input in
            input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        }
        let urlDecodeFn: @convention(block) (String) -> String = { input in
            input.removingPercentEncoding ?? input
        }

        encoding?.setObject(base64EncodeFn, forKeyedSubscript: "base64Encode" as NSString)
        encoding?.setObject(base64DecodeFn, forKeyedSubscript: "base64Decode" as NSString)
        encoding?.setObject(urlEncodeFn, forKeyedSubscript: "urlEncode" as NSString)
        encoding?.setObject(urlDecodeFn, forKeyedSubscript: "urlDecode" as NSString)

        rockxy?.setObject(encoding, forKeyedSubscript: "encoding" as NSString)
    }

    private static func installStorage(on rockxy: JSValue?, context: JSContext, pluginID: String) {
        let storage = JSValue(newObjectIn: context)
        let prefix = RockxyIdentity.current.pluginStoragePrefix(pluginID: pluginID)

        let getFn: @convention(block) (String) -> Any? = { key in
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("storage.get rejected invalid key '\(key)' for \(pluginID)")
                return nil
            }
            return UserDefaults.standard.object(forKey: prefix + key)
        }
        let setFn: @convention(block) (String, Any) -> Void = { key, value in
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("storage.set rejected invalid key '\(key)' for \(pluginID)")
                return
            }
            UserDefaults.standard.set(value, forKey: prefix + key)
        }
        let deleteFn: @convention(block) (String) -> Void = { key in
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("storage.delete rejected invalid key '\(key)' for \(pluginID)")
                return
            }
            UserDefaults.standard.removeObject(forKey: prefix + key)
        }

        storage?.setObject(getFn, forKeyedSubscript: "get" as NSString)
        storage?.setObject(setFn, forKeyedSubscript: "set" as NSString)
        storage?.setObject(deleteFn, forKeyedSubscript: "delete" as NSString)

        rockxy?.setObject(storage, forKeyedSubscript: "storage" as NSString)
    }

    private static func installEnv(on rockxy: JSValue?, context: JSContext, pluginID: String) {
        let env = JSValue(newObjectIn: context)
        let prefix = RockxyIdentity.current.pluginConfigPrefix(pluginID: pluginID)

        let getFn: @convention(block) (String) -> Any? = { key in
            guard PluginValidator.isValidKey(key) else {
                bridgeLogger.debug("env.get rejected invalid key '\(key)' for \(pluginID)")
                return nil
            }
            return UserDefaults.standard.object(forKey: prefix + key)
        }

        env?.setObject(getFn, forKeyedSubscript: "get" as NSString)

        rockxy?.setObject(env, forKeyedSubscript: "env" as NSString)
    }
}
