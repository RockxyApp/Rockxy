import Foundation

// Applies anti-cache header mutations when the global no-caching mode is enabled.

// MARK: - NoCacheHeaderMutator

/// Applies anti-cache header mutations to outbound requests when the global
/// "No Caching" toggle is active. Adds `Cache-Control` and `Pragma` directives,
/// and strips conditional request headers (`If-Modified-Since`, `If-None-Match`)
/// to force origin servers to return fresh responses.
enum NoCacheHeaderMutator {
    /// The UserDefaults key matching the `@AppStorage` toggle in ToolsSettingsTab.
    static let userDefaultsKey = RockxyIdentity.current.defaultsKey("noCaching")

    /// Returns `true` when the user has enabled the No Caching toggle.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Mutates an array of `HTTPHeader` values by injecting anti-cache directives
    /// and removing conditional request headers. Returns the modified array.
    static func apply(to headers: [HTTPHeader]) -> [HTTPHeader] {
        var result = headers.filter {
            $0.name.caseInsensitiveCompare("If-Modified-Since") != .orderedSame
                && $0.name.caseInsensitiveCompare("If-None-Match") != .orderedSame
        }

        result.removeAll { $0.name.caseInsensitiveCompare("Cache-Control") == .orderedSame }
        result.append(HTTPHeader(name: "Cache-Control", value: "no-cache, no-store, must-revalidate"))

        result.removeAll { $0.name.caseInsensitiveCompare("Pragma") == .orderedSame }
        result.append(HTTPHeader(name: "Pragma", value: "no-cache"))

        return result
    }
}
