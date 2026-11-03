import Foundation

// Detects requests whose destination is Rockxy's own listener.

// MARK: - ProxyLoopGuard

/// A request aimed at the proxy's own listen port would be forwarded back into the proxy,
/// creating a new connection and transaction on every hop until the per-destination
/// connection cap trips. Rejecting it at the first hop keeps a misconfigured client, a Map
/// Remote rule pointing at Rockxy, or a hostile request from amplifying into dozens of rows.
enum ProxyLoopGuard {
    /// `true` when `host:port` resolves to the listener that accepted the connection.
    /// `proxyHost` is the local address the client connected to; `localAddresses` are the
    /// machine's other interface addresses (a device on the LAN can name the Mac by IP).
    ///
    /// `localAddresses` has no default on purpose. Swift evaluates a default argument at the
    /// call site, so a `RootCADownloadServer.lanIPv4Addresses()` default ran a `getifaddrs`
    /// walk and a locale-aware sort on the event loop for every request, before the
    /// `port == proxyPort` exit below could rule the request out. Callers resolve the
    /// addresses once per connection instead.
    nonisolated static func targetsOwnListener(
        host: String,
        port: Int,
        proxyPort: Int,
        proxyHost: String?,
        localAddresses: [String]
    )
        -> Bool
    {
        guard port == proxyPort else {
            return false
        }
        let normalized = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !normalized.isEmpty else {
            return false
        }
        if HostPatternMatcher.isLocalhost(normalized) || normalized == "0.0.0.0" || normalized == "::" {
            return true
        }
        if let proxyHost,
           normalized == proxyHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        {
            return true
        }
        return localAddresses.contains { $0.lowercased() == normalized }
    }
}
