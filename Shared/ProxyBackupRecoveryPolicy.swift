import Foundation

// Decides what happens to a proxy backup that outlived the session that wrote it.

// MARK: - ProxyBackupRecoveryAction

enum ProxyBackupRecoveryAction: Equatable {
    case restore
    case preserve
    case clear
}

// MARK: - ProxyServiceOverrideState

/// The proxy fields recovery reads to decide whether one backed-up network service still
/// carries Rockxy's override. Readiness reporting inspects more fields and answers for the
/// routed service; ownership only asks whether this service still points at Rockxy.
struct ProxyServiceOverrideState: Equatable {
    init(
        service: String,
        httpEnabled: Bool,
        httpHost: String,
        httpPort: Int,
        httpsEnabled: Bool,
        httpsHost: String,
        httpsPort: Int,
        socksEnabled: Bool = false,
        pacEnabled: Bool = false,
        autoDiscoveryEnabled: Bool = false,
        hasGlobalBypass: Bool = false
    ) {
        self.service = service
        self.httpEnabled = httpEnabled
        self.httpHost = httpHost
        self.httpPort = httpPort
        self.httpsEnabled = httpsEnabled
        self.httpsHost = httpsHost
        self.httpsPort = httpsPort
        self.socksEnabled = socksEnabled
        self.pacEnabled = pacEnabled
        self.autoDiscoveryEnabled = autoDiscoveryEnabled
        self.hasGlobalBypass = hasGlobalBypass
    }

    let service: String
    let httpEnabled: Bool
    let httpHost: String
    let httpPort: Int
    let httpsEnabled: Bool
    let httpsHost: String
    let httpsPort: Int
    let socksEnabled: Bool
    let pacEnabled: Bool
    let autoDiscoveryEnabled: Bool
    let hasGlobalBypass: Bool
}

// MARK: - ProxyOverrideOwnership

/// Per-service ownership for recovery. This is deliberately an *any* predicate: a backup covers
/// several network services, and one service the user has since re-pointed must not make the
/// remaining Rockxy-owned services look unowned — that is how a stranded override survives with
/// its only restore point deleted.
enum ProxyOverrideOwnership {
    // MARK: Internal

    static let loopbackHost = "127.0.0.1"

    /// True when this service still carries Rockxy's strict HTTP+HTTPS loopback override on the
    /// persisted port. Both protocols must match: a half-configured service belongs to whoever
    /// changed it, not to Rockxy.
    static func isOwnedByRockxy(_ state: ProxyServiceOverrideState, port: Int) -> Bool {
        guard port > 0 else {
            return false
        }
        return state.httpEnabled
            && state.httpHost == loopbackHost
            && state.httpPort == port
            && state.httpsEnabled
            && state.httpsHost == loopbackHost
            && state.httpsPort == port
            && !state.socksEnabled
            && !state.pacEnabled
            && !state.autoDiscoveryEnabled
            && !state.hasGlobalBypass
    }

    /// The backed-up services Rockxy still owns right now, in the order they were supplied.
    /// Restoring these and only these leaves a user-changed or foreign service untouched.
    static func residualOwnedServices(in states: [ProxyServiceOverrideState], port: Int) -> [String] {
        states.filter { isOwnedByRockxy($0, port: port) }.map(\.service)
    }

    static func hasResidualOwnedService(in states: [ProxyServiceOverrideState], port: Int) -> Bool {
        states.contains { isOwnedByRockxy($0, port: port) }
    }

    /// The loopback port a backup without a persisted port is still overriding, taken from the
    /// first backed-up service that carries a complete HTTP+HTTPS loopback override. Backups
    /// written before the port was recorded have nothing to compare against otherwise, and an
    /// unidentifiable port means the restore point gets thrown away.
    static func inferredOwnedPort(in states: [ProxyServiceOverrideState]) -> Int? {
        for state in states where state.httpEnabled
            && state.httpsEnabled
            && state.httpHost == loopbackHost
            && state.httpsHost == loopbackHost
            && state.httpPort == state.httpsPort
            && state.httpPort > 0
            && !state.socksEnabled
            && !state.pacEnabled
            && !state.autoDiscoveryEnabled
            && !state.hasGlobalBypass
        {
            return state.httpPort
        }
        return nil
    }
}

// MARK: - ProxyBackupRecoveryPolicy

/// Decides backup lifetime from live ownership instead of elapsed wall-clock time or a loopback
/// probe. Any process can answer on a loopback port, so reachability never proved that the
/// capture session which took the override was still the one running.
enum ProxyBackupRecoveryPolicy {
    static func action(
        residualOwnedServicesExist: Bool,
        ownerSessionIsLive: Bool
    )
        -> ProxyBackupRecoveryAction
    {
        guard residualOwnedServicesExist else {
            return .clear
        }
        return ownerSessionIsLive ? .preserve : .restore
    }
}

// MARK: - ProxyBackupOwnerIdentityPolicy

/// Decides whether the process recorded in a backup is still the live, trusted Rockxy session
/// that took the override. Every clause has to hold: a recycled PID, a legacy record with no
/// identity, or a process that no longer satisfies caller validation all mean the session is
/// gone and its residual services must be restored.
enum ProxyBackupOwnerIdentityPolicy {
    static func ownerSessionIsLive(
        recordedOwnerPID: Int32?,
        recordedStartSignature: String?,
        ownerProcessIsAlive: Bool,
        liveStartSignature: String?,
        ownerPassesCallerValidation: Bool
    )
        -> Bool
    {
        guard ownerProcessIsAlive, ownerPassesCallerValidation else {
            return false
        }
        return ProcessStartIdentity.identifiesSameProcess(
            recordedPID: recordedOwnerPID,
            recordedStartSignature: recordedStartSignature,
            liveStartSignature: liveStartSignature
        )
    }
}

// MARK: - ProxyBackupSubset

/// Pure selection helpers that make subset restore deterministic and testable without touching
/// system state.
enum ProxyBackupSubset {
    /// Keeps the backup entries naming one of `services`, preserving the backup's order.
    static func select<Entry>(
        _ entries: [Entry],
        services: Set<String>,
        serviceName: (Entry) -> String
    )
        -> [Entry]
    {
        entries.filter { services.contains(serviceName($0)) }
    }

    /// The entries a restore attempt did not resolve: the services whose commands failed, plus
    /// the services still pointing at Rockxy afterwards. While this is non-empty the backup has
    /// to survive, because those services have no other restore point.
    static func unresolvedEntries<Entry>(
        _ entries: [Entry],
        failedServices: Set<String>,
        stillOwnedServices: Set<String>,
        serviceName: (Entry) -> String
    )
        -> [Entry]
    {
        entries.filter { entry in
            let service = serviceName(entry)
            return failedServices.contains(service) || stillOwnedServices.contains(service)
        }
    }
}
