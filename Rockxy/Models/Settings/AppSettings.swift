import Foundation

/// In-memory representation of user preferences, backed by `AppSettingsStorage` (UserDefaults).
/// Default values match the settings UI's initial state.
struct AppSettings {
    var proxyPort: Int = 9090
    var autoStartProxy: Bool = false
    var recordOnLaunch: Bool = true
    var maxBufferSize: Int = 50000
    var maxLogBufferSize: Int = 100_000
    var enableLogCapture: Bool = true
    var onlyListenOnLocalhost: Bool = true
    var listenIPv6: Bool = false
    var autoSelectPort: Bool = true

    /// The effective listen address derived from `onlyListenOnLocalhost`.
    var effectiveListenAddress: String {
        onlyListenOnLocalhost ? "127.0.0.1" : "0.0.0.0"
    }

    /// The loopback address shown in the status popover.
    var loopbackAddress: String {
        onlyListenOnLocalhost ? "127.0.0.1" : "0.0.0.0"
    }
}
