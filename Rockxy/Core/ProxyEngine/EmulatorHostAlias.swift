import Foundation

// Maps the Android emulator's name for the host Mac back to loopback.

// MARK: - EmulatorHostAlias

/// Inside the stock Android emulator the Mac's loopback is `10.0.2.2` (`10.0.3.2` in
/// Genymotion). When an emulator is routed through Rockxy, a request to its dev
/// server — for example Metro at `http://10.0.2.2:8081` — reaches Rockxy on the
/// Mac, where that address means nothing. Rockxy connects to `127.0.0.1` instead,
/// but only for loopback clients (emulator traffic arrives from loopback) and only
/// when no interface on this Mac sits in the alias's /24, where the address could be
/// a real neighbor. The captured URL keeps the address the client used.
enum EmulatorHostAlias {
    static let aliases: Set<String> = ["10.0.2.2", "10.0.3.2"]

    static func connectHost(
        for host: String,
        clientHost: String?,
        localAddresses: [String] = RootCADownloadServer.lanIPv4Addresses()
    )
        -> String
    {
        guard aliases.contains(host),
              let clientHost,
              HostPatternMatcher.isLocalhost(clientHost) else
        {
            return host
        }
        let subnet = host.split(separator: ".").prefix(3).joined(separator: ".") + "."
        guard !localAddresses.contains(where: { $0.hasPrefix(subnet) }) else {
            return host
        }
        return "127.0.0.1"
    }
}
