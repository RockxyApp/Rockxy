import Foundation
@testable import Rockxy
import Testing

// MARK: - ProxyDefaultsSnapshotTests

/// `NoCacheHeaderMutator.isEnabled` is read once per request and `HTTP2ProxyOptions.isEnabled`
/// once per intercepted connection, both from NIO event-loop threads, so each now answers from
/// a snapshot instead of taking the `UserDefaults` lock every time. Both toggles are live, and
/// a snapshot that only refreshed at launch would be a user-visible regression: the setting
/// would appear to do nothing until relaunch. These tests pin the refresh.
///
/// They write the app's shared defaults, which is what the production reader looks at, so each
/// one restores the value it found (`project_test_host_shares_app_defaults`).
@Suite(.serialized)
struct ProxyDefaultsSnapshotTests {
    @Test("Flipping the No Caching toggle takes effect without a relaunch")
    func noCachingToggleTakesEffectAfterChange() {
        let key = NoCacheHeaderMutator.userDefaultsKey
        let original = UserDefaults.standard.object(forKey: key)
        defer { restore(original, forKey: key) }

        UserDefaults.standard.set(false, forKey: key)
        #expect(!NoCacheHeaderMutator.isEnabled)
        // Reads the snapshotted `false` first, so this proves the invalidation and not just a
        // cold first read.
        UserDefaults.standard.set(true, forKey: key)
        #expect(NoCacheHeaderMutator.isEnabled)
        UserDefaults.standard.set(false, forKey: key)
        #expect(!NoCacheHeaderMutator.isEnabled)
    }

    @Test("Flipping the HTTP/2 toggle applies to the next connection without a relaunch")
    func http2ToggleTakesEffectAfterChange() {
        let key = HTTP2ProxyOptions.defaultsKey
        let original = UserDefaults.standard.object(forKey: key)
        HTTP2ProxyOptions.setOverride(nil)
        defer { restore(original, forKey: key) }

        UserDefaults.standard.set(false, forKey: key)
        #expect(!HTTP2ProxyOptions.isEnabled)
        UserDefaults.standard.set(true, forKey: key)
        #expect(HTTP2ProxyOptions.isEnabled)
        UserDefaults.standard.set(false, forKey: key)
        #expect(!HTTP2ProxyOptions.isEnabled)
    }

    @Test("The HTTP/2 test override still wins over the snapshot")
    func http2OverrideWinsOverSnapshot() {
        let key = HTTP2ProxyOptions.defaultsKey
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            HTTP2ProxyOptions.setOverride(nil)
            restore(original, forKey: key)
        }

        UserDefaults.standard.set(false, forKey: key)
        #expect(!HTTP2ProxyOptions.isEnabled)
        HTTP2ProxyOptions.setOverride(true)
        #expect(HTTP2ProxyOptions.isEnabled)
        HTTP2ProxyOptions.setOverride(nil)
        #expect(!HTTP2ProxyOptions.isEnabled)
    }

    @Test("Upstream trust is read live, so no snapshot can outlive the user turning it off")
    func upstreamTrustIsReadLive() {
        // Deliberately not snapshotted: a stale `true` would decrypt one connection without
        // checking the origin's certificate, and unlike a cache-control header that is not
        // recoverable on the next request. See `UpstreamTrustPolicy`.
        let key = UpstreamTrustPolicy.userDefaultsKey
        let original = UserDefaults.standard.object(forKey: key)
        defer { restore(original, forKey: key) }

        UserDefaults.standard.set(true, forKey: key)
        #expect(UpstreamTrustPolicy.acceptsUntrustedCertificates)
        UserDefaults.standard.set(false, forKey: key)
        #expect(!UpstreamTrustPolicy.acceptsUntrustedCertificates)
    }

    // MARK: Private

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
