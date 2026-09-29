import Foundation
@testable import Rockxy
import Testing

// MARK: - SOCKSListenerSettingsTests

@MainActor
struct SOCKSListenerSettingsTests {
    @Test("The listener is off by default and requests a port only when enabled")
    func defaultsAndRequestedPort() throws {
        let suite = "SOCKSListenerSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SOCKSListenerSettings(defaults: defaults)
        #expect(!settings.isEnabled)
        #expect(settings.status == .disabled)
        #expect(settings.port == 8_889)
        #expect(settings.requestedPort == nil)

        settings.update(isEnabled: true, port: 9_999)
        #expect(settings.requestedPort == 9_999)
        let reloaded = SOCKSListenerSettings(defaults: defaults)
        #expect(reloaded.isEnabled)
        #expect(reloaded.port == 9_999)
    }

    @Test("Status reflects the last listener result")
    func statusMapping() throws {
        let suite = "SOCKSListenerSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SOCKSListenerSettings(defaults: defaults)

        settings.applyListenerResult(nil)
        #expect(settings.status == .disabled)

        settings.update(isEnabled: true, port: 8_889)
        #expect(settings.status == .proxyStopped)
        settings.applyListenerResult(nil)
        #expect(settings.status == .listening)
        settings.applyListenerResult(.portInUse)
        #expect(settings.status == .portInUse)
        settings.markProxyStopped()
        #expect(settings.status == .proxyStopped)
    }
}
