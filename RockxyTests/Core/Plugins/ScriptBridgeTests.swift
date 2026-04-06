import Foundation
import JavaScriptCore
import os
@testable import Rockxy
import Testing

// Regression tests for `ScriptBridge` in the core plugins layer.

struct ScriptBridgeTests {
    // MARK: Internal

    @Test("Install bridge creates $rockxy object in JSContext")
    func bridgeInstallsRockxyObject() throws {
        let context = makeContext()

        let rockxy = context.objectForKeyedSubscript("$rockxy")
        #expect(rockxy != nil)
        #expect(try !#require(rockxy?.isUndefined))
    }

    @Test("$rockxy.crypto.sha256 returns correct hash")
    func cryptoSHA256() {
        let context = makeContext()
        let result = context.evaluateScript("$rockxy.crypto.sha256('hello')")

        #expect(result?.toString() == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test("$rockxy.crypto.md5 returns correct hash")
    func cryptoMD5() {
        let context = makeContext()
        let result = context.evaluateScript("$rockxy.crypto.md5('hello')")

        #expect(result?.toString() == "5d41402abc4b2a76b9719d911017c592")
    }

    @Test("$rockxy.encoding.base64Encode and base64Decode roundtrip")
    func base64Roundtrip() {
        let context = makeContext()

        let encoded = context.evaluateScript("$rockxy.encoding.base64Encode('Hello, World!')")
        #expect(encoded?.toString() == "SGVsbG8sIFdvcmxkIQ==")

        let decoded = context.evaluateScript("$rockxy.encoding.base64Decode('SGVsbG8sIFdvcmxkIQ==')")
        #expect(decoded?.toString() == "Hello, World!")
    }

    @Test("$rockxy.encoding.urlEncode and urlDecode roundtrip")
    func urlEncodingRoundtrip() {
        let context = makeContext()

        let encoded = context.evaluateScript("$rockxy.encoding.urlEncode('hello world&foo=bar')")
        let encodedStr = encoded?.toString() ?? ""
        #expect(encodedStr.contains("hello%20world"))

        let decoded = context.evaluateScript("$rockxy.encoding.urlDecode('\(encodedStr)')")
        #expect(decoded?.toString() == "hello world&foo=bar")
    }

    @Test("$rockxy.storage set/get/delete cycle")
    func storageSetGetDelete() {
        let context = makeContext()
        let testKey = "unit_test_\(UUID().uuidString)"
        let storagePrefix = "\(TestIdentity.defaultsPrefix).plugin.\(testPluginID).storage."

        context.evaluateScript("$rockxy.storage.set('\(testKey)', 'testValue')")

        let stored = UserDefaults.standard.object(forKey: storagePrefix + testKey) as? String
        #expect(stored == "testValue")

        let retrieved = context.evaluateScript("$rockxy.storage.get('\(testKey)')")
        #expect(retrieved?.toString() == "testValue")

        context.evaluateScript("$rockxy.storage.delete('\(testKey)')")
        let deleted = UserDefaults.standard.object(forKey: storagePrefix + testKey)
        #expect(deleted == nil)
    }

    @Test("console.log maps to $rockxy.log without throwing")
    func consoleLogDoesNotThrow() {
        let context = makeContext()

        context.evaluateScript("console.log('test message from bridge')")

        #expect(context.exception == nil)
    }

    // MARK: Private

    private let testPluginID = "com.test.bridge-test"
    private let logger = Logger(subsystem: TestIdentity.logSubsystem, category: "ScriptBridgeTests")

    private func makeContext() -> JSContext {
        let context = JSContext()!
        ScriptBridge.install(in: context, pluginID: testPluginID, logger: logger)
        return context
    }
}
