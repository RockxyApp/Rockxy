import Foundation

/// In-memory representation of user preferences, backed by `AppSettingsStorage` (UserDefaults).
/// Default values match the settings UI's initial state.
struct AppSettings {
    var proxyPort: Int = 9_090
    var autoStartProxy: Bool = false
    var recordOnLaunch: Bool = true
    var maxBufferSize: Int = 50_000
    var maxLogBufferSize: Int = 100_000
    var enableLogCapture: Bool = true
    var onlyListenOnLocalhost: Bool = true
    var listenIPv6: Bool = false
    var autoSelectPort: Bool = true

    /// Master toggle for the Scripting List window. When false, scripts are loaded
    /// but not executed in the proxy pipeline. Default true for backward compat.
    var scriptingToolEnabled: Bool = true

    /// Allows scripts to read the host system's environment variables via
    /// `$rockxy.env.system(key)`. Default false; user must opt in via Advance menu.
    var allowSystemEnvVars: Bool = false

    /// When true, all matching scripts run in id-sorted order on the same request.
    /// When false (default), only the first matching script runs.
    var allowMultipleScriptsPerRequest: Bool = false

    /// Master toggle for the MCP server. Disabled by default for security.
    var mcpServerEnabled: Bool = false

    /// TCP port for the MCP HTTP server. Defaults to 9710.
    var mcpServerPort: Int = 9_710

    /// When true, sensitive headers and body fields are redacted in MCP responses.
    var mcpRedactSensitiveData: Bool = true

    /// The effective listen address derived from `onlyListenOnLocalhost`.
    var effectiveListenAddress: String {
        onlyListenOnLocalhost ? "127.0.0.1" : "0.0.0.0"
    }

    /// The loopback address shown in the status popover.
    var loopbackAddress: String {
        onlyListenOnLocalhost ? "127.0.0.1" : "0.0.0.0"
    }
}
