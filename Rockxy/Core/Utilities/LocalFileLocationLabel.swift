import Foundation

/// A local file's presentation label. Keep the absolute URL for file operations,
/// while omitting this computer's account and volume paths from default UI text.
enum LocalFileLocationLabel {
    static func label(
        for url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    )
        -> String
    {
        let path = url.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        if path == home {
            return "~"
        }
        let prefix = home.hasSuffix("/") ? home : home + "/"
        if path.hasPrefix(prefix) {
            return "~/" + path.dropFirst(prefix.count)
        }
        return url.lastPathComponent
    }
}
