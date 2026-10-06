import Foundation

// User options for the cURL command Rockxy copies from a request.

// MARK: - CurlCopyOptions

struct CurlCopyOptions: Equatable {
    // MARK: Internal

    static let includeProxyKey = RockxyIdentity.current.defaultsKey("copy.curl.includeProxy")
    static let preserveOriginalKey = RockxyIdentity.current.defaultsKey("copy.curl.preserveOriginal")

    /// Clean command, no proxy flag: the shape used wherever no preference applies.
    static let standard = CurlCopyOptions(includesProxyFlag: false, preservesOriginalHeaders: false)

    /// The preferences chosen in Settings.
    static var current: CurlCopyOptions {
        let defaults = UserDefaults.standard
        return CurlCopyOptions(
            includesProxyFlag: defaults.bool(forKey: includeProxyKey),
            preservesOriginalHeaders: defaults.bool(forKey: preserveOriginalKey)
        )
    }

    /// Adds `--proxy` so running the command sends the request through Rockxy again.
    var includesProxyFlag: Bool
    /// Keeps `Content-Length`, `Accept-Encoding`, and `Content-Encoding` as captured. By default
    /// they are left out: curl computes the length itself, and an `Accept-Encoding` header
    /// without `--compressed` would print the response undecoded.
    var preservesOriginalHeaders: Bool
}
