import Darwin
import Foundation

// Defines `LoopbackProxyListener`, `LoopbackProxyOwnershipPolicy`, and
// `LoopbackProxyListenerResolver`, which tell another proxy app's loopback endpoint (a Clash-style
// client on 127.0.0.1:7890, say) apart from a Rockxy session before direct-mode routing adopts the
// current settings as the restore point.

// MARK: - LoopbackProxyListener

/// Who answers on a loopback proxy endpoint macOS is already configured to use.
enum LoopbackProxyListener: Equatable {
    /// A Rockxy build of any edition or namespace, including this process.
    case rockxy
    /// Another application, such as a local proxy client the user runs alongside Rockxy.
    case otherApplication
    /// Nothing visible is listening: the setting outlived the app that wrote it, or its listener
    /// belongs to another user (a root daemon) and cannot be inspected.
    case none
    /// The listener could not be determined in time.
    case unknown
}

// MARK: - LoopbackProxyOwnershipPolicy

/// Decides whether pre-existing loopback proxy settings may become a direct-mode restore point.
///
/// Direct mode must never adopt another Rockxy session's override as "the user's settings": the
/// restore would later point macOS at a listener that has gone away. Another proxy app's endpoint
/// is different — it *is* the user's configuration, and the only correct restore point.
enum LoopbackProxyOwnershipPolicy {
    /// What direct mode may do with the loopback proxies macOS is already configured to use.
    enum DirectBaselineDecision: Equatable {
        /// Every endpoint belongs to another app or to nothing; capture the settings as the restore point.
        case capture
        /// Another Rockxy session may own the routing.
        case refuseRockxySession
        /// The listener on this port could not be identified, so ownership cannot be proven either way.
        case refuseUnidentifiedListener(port: Int)
    }

    static let loopbackHost = "127.0.0.1"

    /// The distinct loopback ports that enabled HTTP, HTTPS, or SOCKS proxies point at.
    static func enabledLoopbackPorts(in snapshots: [ServiceProxySnapshot]) -> [Int] {
        var ports = Set<Int>()
        for snapshot in snapshots {
            if snapshot.httpEnabled, snapshot.httpHost == loopbackHost, snapshot.httpPort > 0 {
                ports.insert(snapshot.httpPort)
            }
            if snapshot.httpsEnabled, snapshot.httpsHost == loopbackHost, snapshot.httpsPort > 0 {
                ports.insert(snapshot.httpsPort)
            }
            if snapshot.socksEnabled, snapshot.socksHost == loopbackHost, snapshot.socksPort > 0 {
                ports.insert(snapshot.socksPort)
            }
        }
        return ports.sorted()
    }

    /// Decides whether pre-existing loopback proxies can become the direct-mode restore point.
    ///
    /// - A helper backup on disk means a helper-owned session may become visible at any moment,
    ///   so any loopback proxy is treated as that session's.
    /// - A Rockxy listener means another Rockxy session owns the routing.
    /// - An unidentified listener fails closed, as the check did before listeners were inspected.
    static func directBaselineDecision(
        listeners: [(port: Int, listener: LoopbackProxyListener)],
        helperBackupExists: Bool
    )
        -> DirectBaselineDecision
    {
        guard !listeners.isEmpty else {
            return .capture
        }
        guard !helperBackupExists else {
            return .refuseRockxySession
        }
        if listeners.contains(where: { $0.listener == .rockxy }) {
            return .refuseRockxySession
        }
        if let unidentified = listeners.first(where: { $0.listener == .unknown }) {
            return .refuseUnidentifiedListener(port: unidentified.port)
        }
        return .capture
    }

    /// Classifies the processes `lsof` reported for one port. `pids` is nil when `lsof` gave no
    /// answer. Any Rockxy listener wins, because one Rockxy owner is enough to refuse.
    static func classify(
        pids: [Int32]?,
        currentPID: Int32,
        isRockxyProcess: (Int32) -> Bool
    )
        -> LoopbackProxyListener
    {
        guard let pids else {
            return .unknown
        }
        guard !pids.isEmpty else {
            return .none
        }
        if pids.contains(where: { $0 == currentPID || isRockxyProcess($0) }) {
            return .rockxy
        }
        return .otherApplication
    }

    /// True when an application's Info.plist carries Rockxy's identity keys. Every Rockxy build —
    /// Community, Pro, development, and QA namespaces alike — declares them, while bundle
    /// identifiers differ between those builds.
    static func isRockxyApplication(infoDictionary: [String: Any]) -> Bool {
        infoDictionary["RockxyHelperMachServiceName"] is String
            || infoDictionary["RockxyFamilyNamespace"] is String
    }
}

// MARK: - LoopbackProxyListenerResolver

/// Resolves the listener behind a loopback port with a bounded `lsof` query.
enum LoopbackProxyListenerResolver {
    // MARK: Internal

    static func listener(
        onPort port: Int,
        timeout: DispatchTimeInterval = .milliseconds(1_500)
    )
        -> LoopbackProxyListener
    {
        let pids = ProcessResolver.listeningProcessIDs(onLocalPort: port, deadline: .now() + timeout)
        return LoopbackProxyOwnershipPolicy.classify(
            pids: pids,
            currentPID: getpid(),
            isRockxyProcess: isRockxyProcess
        )
    }

    // MARK: Private

    private static func isRockxyProcess(_ pid: Int32) -> Bool {
        var pathBuffer = [CChar](repeating: 0, count: 4_096)
        guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else {
            return false
        }
        let executablePath = String(cString: pathBuffer)
        guard let bundlePath = ClientApplicationIdentity.outerAppBundlePath(forExecutablePath: executablePath),
              let info = Bundle(path: bundlePath)?.infoDictionary else
        {
            return false
        }
        return LoopbackProxyOwnershipPolicy.isRockxyApplication(infoDictionary: info)
    }
}
