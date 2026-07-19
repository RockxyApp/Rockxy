import Foundation

// MARK: - AppTheme

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

// MARK: - AppUISettings

struct AppUISettings: Equatable {
    static let defaultFontSize = 13
    static let defaultTabWidth = 2
    static let allowedFontSizes = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 24, 28]
    static let allowedTabWidths = [2, 4]

    static let `default` = AppUISettings()

    var fontSize: Int = Self.defaultFontSize
    var tabWidth: Int = Self.defaultTabWidth
    var useMonospacedFont = false
    var bodyWordWrap = true
    var bodyShowInvisibles = false
    var bodyShowMinimap = false
    var bodyScrollBeyondLastLine = false
    var useAlternatingRowBackgroundColors = true

    static func validFontSize(_ value: Int) -> Int {
        allowedFontSizes.contains(value) ? value : defaultFontSize
    }

    static func validTabWidth(_ value: Int) -> Int {
        allowedTabWidths.contains(value) ? value : defaultTabWidth
    }
}

// MARK: - AppSettings

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
    var appTheme: AppTheme = .system
    var appUI: AppUISettings = .default

    /// Model access is optional and remains off until the user explicitly enables it.
    var debugAssistantModelAccessEnabled = false

    /// App-wide model profiles. Credentials remain separate in Keychain and are keyed by profile ID.
    var assistantProviderConfigurations: [AssistantProviderConfiguration] = []

    /// The profile used by AI Assistant in every workspace.
    var activeAssistantProviderID: UUID?

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

    /// Default visibility for Publish to Gist. Secret Gists are unlisted but
    /// accessible to anyone who has the link.
    var githubGistVisibility: GitHubGistVisibility = .secret

    /// When true, sensitive headers, query parameters, and body fields are
    /// redacted before publishing selected traffic to GitHub Gist.
    var githubGistRedactSensitiveData: Bool = true

    /// Ask for confirmation before uploading captured traffic to GitHub.
    var githubGistAskBeforePublishing: Bool = true

    /// Open the created Gist in the default browser after a successful publish.
    var githubGistOpenInBrowser: Bool = true

    /// Copy the created Gist URL after a successful publish.
    var githubGistCopyURLToClipboard: Bool = false

    /// The last filesystem path the user explicitly chose when exporting the
    /// Rockxy root CA certificate. This is only a UI convenience hint for
    /// snippet generation and can be nil if the certificate has never been
    /// exported or the export location is unknown.
    var lastExportedRootCAPath: String?

    /// Compatibility accessor for call sites that need only the active global model.
    var assistantProviderConfiguration: AssistantProviderConfiguration? {
        get {
            if let activeAssistantProviderID,
               let active = assistantProviderConfigurations.first(where: { $0.id == activeAssistantProviderID })
            {
                return active
            }
            return assistantProviderConfigurations.first
        }
        set {
            guard let newValue else {
                assistantProviderConfigurations = []
                activeAssistantProviderID = nil
                return
            }
            if let index = assistantProviderConfigurations.firstIndex(where: { $0.id == newValue.id }) {
                assistantProviderConfigurations[index] = newValue
            } else {
                assistantProviderConfigurations.append(newValue)
            }
            activeAssistantProviderID = newValue.id
        }
    }

    /// The effective listen address derived from `onlyListenOnLocalhost`.
    var effectiveListenAddress: String {
        onlyListenOnLocalhost ? "127.0.0.1" : "0.0.0.0"
    }

    /// The loopback address shown in the status popover.
    var loopbackAddress: String {
        onlyListenOnLocalhost ? "127.0.0.1" : "0.0.0.0"
    }
}
