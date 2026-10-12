import Foundation

// Defines `UnrestoredPreviousProxy`, `SystemProxyRestoreReport`, and `PreviousProxyRestorePolicy`,
// which describe proxy settings Rockxy deliberately did not put back when capture ended, so the
// user can decide instead of losing them silently.

// MARK: - UnrestoredPreviousProxy

/// A network service whose pre-capture proxy settings were not put back when capture ended.
///
/// Restore never writes over settings that something other than Rockxy changed during the session
/// — another proxy app toggling or quitting, a VPN, or a person in System Settings. When that
/// happens the settings the user had before capture are still worth offering back, because they
/// are often exactly what the user expects to return to.
struct UnrestoredPreviousProxy: Equatable {
    let service: String
    /// The settings captured before Rockxy changed anything.
    let previous: ServiceProxySnapshot
    /// The bypass list captured before Rockxy changed anything, when it could be read.
    let previousBypassDomains: [String]?
    /// The settings found after restore finished. A later restore writes only if these still hold.
    let current: ServiceProxySnapshot
}

// MARK: - SystemProxyRestoreReport

/// What turning Rockxy's system proxy off left for the user to decide.
struct SystemProxyRestoreReport: Equatable {
    static let empty = SystemProxyRestoreReport(unrestoredPreviousProxies: [])

    let unrestoredPreviousProxies: [UnrestoredPreviousProxy]

    var needsDecision: Bool {
        !unrestoredPreviousProxies.isEmpty
    }
}

// MARK: - PreviousProxyRestoreResult

/// The outcome of writing previous settings back at the user's request.
struct PreviousProxyRestoreResult: Equatable {
    var restoredServices: [String] = []
    /// Services whose settings changed again after the report, so nothing was written to them.
    var changedServices: [String] = []
}

// MARK: - PreviousProxyRestorePolicy

enum PreviousProxyRestorePolicy {
    /// True when the snapshot sends traffic anywhere other than directly.
    static func routesTraffic(_ snapshot: ServiceProxySnapshot) -> Bool {
        snapshot.httpEnabled || snapshot.httpsEnabled || snapshot.socksEnabled
            || snapshot.pacEnabled || snapshot.autoDiscoveryEnabled
    }

    /// Compares only what decides routing. A switched-off endpoint keeps whatever host and port
    /// were last written to it, and restore leaves those alone, so comparing them would report a
    /// difference no user could see.
    static func effectiveRoutingMatches(_ lhs: ServiceProxySnapshot, _ rhs: ServiceProxySnapshot) -> Bool {
        func endpoint(_ enabled: Bool, _ host: String, _ port: Int) -> String? {
            enabled ? "\(host):\(port)" : nil
        }
        return endpoint(lhs.httpEnabled, lhs.httpHost, lhs.httpPort)
            == endpoint(rhs.httpEnabled, rhs.httpHost, rhs.httpPort)
            && endpoint(lhs.httpsEnabled, lhs.httpsHost, lhs.httpsPort)
            == endpoint(rhs.httpsEnabled, rhs.httpsHost, rhs.httpsPort)
            && endpoint(lhs.socksEnabled, lhs.socksHost, lhs.socksPort)
            == endpoint(rhs.socksEnabled, rhs.socksHost, rhs.socksPort)
            && (lhs.pacEnabled ? lhs.pacURL : nil) == (rhs.pacEnabled ? rhs.pacURL : nil)
            && lhs.autoDiscoveryEnabled == rhs.autoDiscoveryEnabled
    }

    /// True when an enabled endpoint of the snapshot is Rockxy's own loopback listener.
    static func pointsAtRockxy(_ snapshot: ServiceProxySnapshot, port: Int) -> Bool {
        LoopbackProxyOwnershipPolicy.enabledLoopbackPorts(in: [snapshot]).contains(port)
    }

    /// The services whose pre-capture settings routed traffic and are no longer in effect.
    ///
    /// A previous setting that pointed at Rockxy's own port is never offered back: restoring it
    /// would route macOS to a listener that has just stopped. A service whose current settings
    /// could not be read is left out, because a later write must be able to prove nothing changed.
    static func unrestoredServices(
        previous: [String: ServiceProxySnapshot],
        previousBypassDomains: [String: [String]],
        current: [String: ServiceProxySnapshot],
        rockxyPort: Int?
    )
        -> [UnrestoredPreviousProxy]
    {
        previous.keys.sorted().compactMap { service in
            guard let previousSnapshot = previous[service],
                  routesTraffic(previousSnapshot),
                  let currentSnapshot = current[service],
                  !effectiveRoutingMatches(previousSnapshot, currentSnapshot) else
            {
                return nil
            }
            if let rockxyPort, pointsAtRockxy(previousSnapshot, port: rockxyPort) {
                return nil
            }
            return UnrestoredPreviousProxy(
                service: service,
                previous: previousSnapshot,
                previousBypassDomains: previousBypassDomains[service],
                current: currentSnapshot
            )
        }
    }
}
