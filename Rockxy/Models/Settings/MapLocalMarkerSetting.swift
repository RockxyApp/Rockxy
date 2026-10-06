import Foundation

// Optional marker header on Map Local responses.

// MARK: - MapLocalMarkerSetting

enum MapLocalMarkerSetting {
    /// When on, a mocked response carries `X-Rockxy-Applied: Map Local`, so a client's own tools
    /// (a browser's network panel, a test's logs) show which responses Rockxy served.
    static let markKey = RockxyIdentity.current.defaultsKey("mapLocal.markResponses")
    static let markHeaderName = "X-Rockxy-Applied"

    nonisolated static func markedHeaders(
        _ headers: [HTTPHeader],
        defaults: UserDefaults = .standard
    )
        -> [HTTPHeader]
    {
        guard defaults.bool(forKey: markKey),
              !headers.contains(where: { $0.name.caseInsensitiveCompare(markHeaderName) == .orderedSame }) else
        {
            return headers
        }
        return headers + [HTTPHeader(name: markHeaderName, value: "Map Local")]
    }
}
