import Foundation
import NIOSSL
@testable import Rockxy
import Testing

// MARK: - TLSKeyLogSettingsTests

@MainActor
struct TLSKeyLogSettingsTests {
    @Test("Logging is off by default and installs nothing on TLS configurations")
    func offByDefault() {
        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.TLSKeyLogSettingsTests")
        let writer = TLSKeyLogWriter()
        let settings = TLSKeyLogSettings(defaults: defaults, writer: writer)
        #expect(!settings.isEnabled)
        #expect(writer.destination == nil)
        var configuration = TLSConfiguration.makeClientConfiguration()
        TLSKeyLogWriter.apply(to: &configuration, writer: writer)
        #expect(configuration.keyLogCallback == nil)
    }

    @Test("Turning logging on opens the chosen file and survives a relaunch")
    func enableAndRelaunch() throws {
        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.TLSKeyLogSettingsTests")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keys-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = TLSKeyLogWriter()
        let settings = TLSKeyLogSettings(defaults: defaults, writer: writer)
        settings.setFileURL(url)
        settings.setEnabled(true)
        #expect(writer.destination == url)
        #expect(settings.errorMessage == nil)
        var configuration = TLSConfiguration.makeClientConfiguration()
        TLSKeyLogWriter.apply(to: &configuration, writer: writer)
        #expect(configuration.keyLogCallback != nil)

        let relaunchedWriter = TLSKeyLogWriter()
        let relaunched = TLSKeyLogSettings(defaults: defaults, writer: relaunchedWriter)
        #expect(relaunched.isEnabled)
        #expect(relaunchedWriter.destination == url)
        relaunched.setEnabled(false)
        #expect(relaunchedWriter.destination == nil)
    }

    @Test("An unwritable file turns logging off and explains why")
    func unwritableFile() {
        let defaults = IsolatedDefaultsSuite.make(prefix: "Rockxy.TLSKeyLogSettingsTests")
        let writer = TLSKeyLogWriter()
        let settings = TLSKeyLogSettings(defaults: defaults, writer: writer)
        settings.setFileURL(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/keys.log"))
        settings.setEnabled(true)
        #expect(writer.destination == nil)
        #expect(settings.errorMessage != nil)
    }
}
